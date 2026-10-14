#!/usr/bin/env python3
"""Compare src/xm_mixer.bend with jar_xm's mixer.

Reference. jar_xm.h as pinned raylib vendors it, included in the reference
program with its implementation: a module is loaded and a script of calls
is run on it: frames generated (jar_xm_generate_samples), the song's length
and a reset. After each call every float it wrote is hashed, with the
count of samples generated and the whole context as the xm-player gate
hashes it. A run prints the rolling hash after each call.

What jar_xm leaves undefined ends a run with -1, found as in the xm-player
gate (the compiler's traps, jar_xm's block of memory under a guard, each
row's place worked out before its tick), and the port's player must have
stopped in the same call. For that the frames of most runs are generated
by the program's copy of jar_xm_generate_samples' loop, which makes the
tick itself where one is due and then calls jar_xm_mixdown; the modules
whose rows cannot leave their patterns are also played by
jar_xm_generate_samples itself. The copy looks at one more thing before
each frame: a channel whose next sample would be read past its sample's
floats, which lie inside jar_xm's block where nothing faults.

Candidate. Mx.generate, Pl.remaining.samples and Pl.reset on
Pl.player.new of the module, by the script.

The modules are the xm-player gate's: raylib's mini1111.xm, played as
raylib plays it (the length, the reset, then frames by the thousand), and
the built ones. CPU-1, CPU-2 and JavaScript lanes.
"""
import json

from conformance import gradient_reference
import probekit
from probekit import ROOT, ProbeFailure
import xm_module_probe as xp
import xm_player_probe as pp

SOURCE = pp.SOURCE
WORK = '.build/xm-mixer-probe/cases'
FLAGS = pp.FLAGS
# a script's calls: a number of frames (by the program's loop), the length (by its copy), a reset, the length by jar_xm's own
# function, and frames by jar_xm_generate_samples itself (OWN_FRAMES - n)
REMAINING, RESET, OWN = pp.REMAINING, pp.RESET, pp.OWN
OWN_FRAMES = -1000
MOST = 8192

# the xm-player gate's reference up to its runs: the guarded block, the handler, the hashes, the row's place, the length's copy
SHARED = pp.NATIVE[:pp.NATIVE.index('static void run(')]

NATIVE = SHARED + r'''
// Whether a channel's next sample would be read past its sample's floats: the float at its position, or the one after (the loop's
// start after the loop's end; none past a sample that does not loop). A stereo sample's right side is its second half.
static int beyond(jar_xm_channel_context_t *ch)
{
    jar_xm_sample_t *s = ch->sample;
    unsigned count, far, at, b, after;
    int follows;
    if (!ch->instrument || !s || ch->sample_position < 0 || s->length == 0) return 0;
    // a position that is no unsigned int traps by itself
    if (!(ch->sample_position + 1.0f < 4294967296.0f)) return 0;
    count = s->stereo? 2*s->length : s->length; far = s->stereo? s->length : 0;
    at = (uint32_t)ch->sample_position; b = (uint32_t)(ch->sample_position + 1);
    follows = s->loop_type != jar_xm_NO_LOOP || b < s->length;
    after = (s->loop_type != jar_xm_NO_LOOP && b == s->loop_end)? s->loop_start : b;
    return at + far >= count || (follows && (after + far >= count || after >= count));
}

// jar_xm_generate_samples' loop with each tick made here where one is due (its row looked at first) and each channel looked at
// before its frame: 0 where something is undefined
static int frames(jar_xm_context_t *ctx, float *output, int count)
{
    int i, c;
    ctx->generated_samples += count;
    for (i = 0; i < count; i++)
    {
        if (ctx->remaining_samples_in_tick <= 0)
        {
            if (outside(ctx)) return 0;
            jar_xm_tick(ctx);
            if (past() || !(ctx->remaining_samples_in_tick > 0)) return 0;
        }
        for (c = 0; c < ctx->module.num_channels; c++) if (beyond(ctx->channels + c)) return 0;
        jar_xm_mixdown(ctx, output + 2*i, output + 2*i + 1);
    }
    return 1;
}

static float output[2*MOST];

static void run(const char *path, const int *ops, int count, unsigned rate)
{
    unsigned char *data;
    size_t size;
    FILE *file = fopen(path, "rb");
    jar_xm_context_t *ctx = NULL;
    volatile int k;
    volatile unsigned roll = 2166136261u;
    if (!file) exit(2);
    fseek(file, 0, SEEK_END);
    size = (size_t)ftell(file);
    fseek(file, 0, SEEK_SET);
    data = (unsigned char *)malloc(size + 1);
    if (fread(data, 1, size, file) != size) exit(3);
    fclose(file);
    if (jar_xm_create_context_safe(&ctx, (const char *)data, size, rate)) exit(4);
    jar_xm_set_max_loop_count(ctx, 0);
    printf("[");
    for (k = 0; k < count; k++)
    {
        int i, made = 0;
        if (sigsetjmp(trapped, 1) != 0) { printf("-1]\n"); free(data); return; }
        if (ops[k] == -1 || ops[k] == -3)
        {
            long long total = ops[k] == -3? (long long)jar_xm_get_remaining_samples(ctx) : remaining(ctx);
            if (total < 0 || past()) { printf("-1]\n"); free(data); return; }
            if (total >> 32) exit(5);
            roll = fnv(roll, (unsigned)total);
        }
        else if (ops[k] == -2) jar_xm_reset(ctx);
        else if (ops[k] > 0)
        {
            made = ops[k];
            if (made > MOST) exit(6);
            if (!frames(ctx, output, made)) { printf("-1]\n"); free(data); return; }
        }
        else
        {
            made = OWN_FRAMES - ops[k];
            if (made > MOST) exit(6);
            jar_xm_generate_samples(ctx, output, (size_t)made);
            if (past()) { printf("-1]\n"); free(data); return; }
        }
        for (i = 0; i < 2*made; i++) roll = fnv(roll, bits(output[i]));
        roll = fnv(roll, (unsigned)ctx->generated_samples); roll = fnv(roll, digest(ctx));
        printf("%u%s", roll, k + 1 < count? ", " : "");
    }
    printf("]\n");
    free(data);
}

// A run in a process of its own: jar_xm's random waveform is one state for every module a process plays.
static void alone(const char *path, const int *ops, int count, unsigned rate)
{
    pid_t child;
    int status = 0;
    fflush(stdout);
    child = fork();
    if (child < 0) exit(10);
    if (child == 0) { run(path, ops, count, rate); fflush(stdout); _exit(0); }
    if (waitpid(child, &status, 0) != child || !WIFEXITED(status) || WEXITSTATUS(status) != 0) exit(11);
}

int main(void)
{
    signal(SIGILL, on_trap); signal(SIGTRAP, on_trap); signal(SIGSEGV, on_trap); signal(SIGBUS, on_trap);
@RUNS@
    return 0;
}
'''.replace('OWN_FRAMES', str(OWN_FRAMES)).replace('MOST', str(MOST))

# the xm-player gate's hashing of a player
DIGEST = pp.PROGRAM[:pp.PROGRAM.index('# The state of a run:')].replace('import ../../src/xm_player.bend as Pl\n', 'import ../../src/xm_player.bend as Pl\nimport ../../src/xm_mixer.bend as Mx\n')

PROGRAM = DIGEST + '''# The state of a run: the player, the rolling hash and what is printed.
type Run is Data:
  Run{player: Pl.Player, roll: U32, out: String}

def Run.player(run: Run) -> Pl.Player:
  Run{player, _, _} = run
  player

def mixed.floats(xs: +List<F32>, +h: U32) -> U32:
  match xs:
    case Nil{}: h
    case Con{+x, +rest}: mixed.floats(rest, mix(h, word(x)))

# After a call: the count of samples generated and the whole player; nothing is printed for a player that has stopped.
def told(+player: Pl.Player, +roll: U32, +out: String) -> Run:
  Run{player, mix(mix(roll, Mx.generated.of(player)), digest(player)), Bool.pick(String, U32.is_eq(Pl.Player.why(player), 0), out ++ Bool.pick(String, String.eq(out, "["), "", ", ") ++ U32.show(mix(mix(roll, Mx.generated.of(player)), digest(player))), out)}

def framed(made: Mx.Generated, run: Run) -> Run:
  Mx.Generated{+player, +samples} = made
  Run{_, +roll, +out} = run
  told(player, mixed.floats(samples, roll), out)

def lengthed(length: Pl.Counted, run: Run) -> Run:
  Pl.Counted{+player, +samples} = length
  Run{_, +roll, +out} = run
  told(player, mix(roll, samples), out)

def rewound(+player: Pl.Player, run: Run) -> Run:
  Run{_, +roll, +out} = run
  told(player, roll, out)

def call(kind: U32, +count: U32, +run: Run) -> Run:
  match kind:
    case 1: lengthed(Pl.remaining.samples(Run.player(run)), run)
    case 2: rewound(Pl.reset(Run.player(run)), run)
    case _: framed(Mx.generate(Run.player(run), count), run)

def ending(run: Run) -> String:
  Run{+player, _, +out} = run
  Bool.pick(String, U32.is_eq(Pl.Player.why(player), 0), out ++ "]", out ++ Bool.pick(String, String.eq(out, "["), "", ", ") ++ "-1]")

# A call: 1 a length, 2 a reset, otherwise frames (their count, or 4294966296 less it for jar_xm's own function).
def calls(ops: +List<U32>, on: Bool, +run: Run) -> String:
  match ops on:
    case _ False{}: ending(run)
    case Nil{} True{}: ending(run)
    case Con{+op, +rest} True{}:
      +next = call(Bool.pick(U32, U32.is_eq(op, 4294967295) || U32.is_eq(op, 4294967293), 1, Bool.pick(U32, U32.is_eq(op, 4294967294), 2, 0)), Bool.pick(U32, (op >= 2147483648 : U32), (4294966296 - op : U32), op), run)
      calls(rest, U32.is_eq(Pl.Player.why(Run.player(next)), 0), next)

def played(loaded: Xm.Loaded, +ops: +List<U32>, +rate: U32) -> String:
  match loaded:
    case Xm.Loaded{+module}: calls(ops, True{}, Run{Pl.player.new(M.LIBM{}, module, rate, 24492), 2166136261, "["})
    case _: "[-9]"

def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>, +ops: +List<U32>, +rate: U32) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("unread")
    case Done{+bytes}: IO.print(played(Xm.load(bytes), ops, rate))

def main() -> IO(Unit):
  do IO<Unit>:
'''


def own(count):
    """Frames by jar_xm_generate_samples itself."""
    return OWN_FRAMES - count


def cases(source):
    """name -> (module, calls, the device's rate). The built modules are played at 8000 Hz, where a tick is a hundred samples or so
    and a few thousand frames go through many rows."""
    out = {
        # as raylib plays a module: the length, the reset, then the stream's frames
        'mini': (source, [OWN, RESET, own(4096), own(4096), own(2048), own(1)], 48000),
        # ... and by the program's loop, with a reset between
        'mini-frames': (source, [3000, 1, 999, RESET, 2500], 48000),
        'mini-slow': (source, [6000, own(3000)], 8000),
    }
    for name, data in pp.built().items():
        if name.startswith('tame'):
            out[name] = (data, [own(5000), OWN, RESET, own(3000)], 8000)
            out[name + '-frames'] = (data, [6000, REMAINING, RESET, 2000], 8000)
        elif name.startswith('all'):
            out[name] = (data, [4000, 4000], 8000)
        else:
            out[name] = (data, [3000, RESET, 1500], 8000)
    return out


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('xm-mixer', args)
    libm = gradient_reference()
    folder = ROOT / WORK
    folder.mkdir(parents=True, exist_ok=True)
    files = cases((args.raylib_source / SOURCE).read_bytes())
    items = []
    for name, (data, calls, rate) in files.items():
        if xp.model(data)[0] != 'loaded':
            raise ProbeFailure(f'xm-mixer: {name} is no module to play: {xp.model(data)}')
        (folder / f'{name}.xm').write_bytes(data)
        items.append((name, f'{WORK}/{name}.xm', calls, rate))
    runs = '\n'.join(f'    {{ static const int ops[] = {{{", ".join(str(op) for op in calls)}}}; alone({json.dumps(str(ROOT / path))}, ops, {len(calls)}, {rate}); }}' for _, path, calls, rate in items)
    expected = [json.loads(line) for line in probe.native(NATIVE.replace('@RUNS@', runs), 'reference', extra_flags=FLAGS, link_raylib=False).splitlines()]
    if len(expected) != len(items):
        raise ProbeFailure(f'xm-mixer: the reference printed {len(expected)} rows for {len(items)} modules')
    rows = {name: row for (name, _, _, _), row in zip(items, expected)}
    undefined = sorted(name for name, row in rows.items() if row[-1] == -1)
    # what the modules are for: raylib's and the tame ones play through, by jar_xm's own function and by the program's loop; what
    # is built to be undefined is; the modules of every effect are some of each
    if (any(rows[name][-1] == -1 or len(rows[name]) != len(files[name][1]) for name in rows if name.startswith('mini') or name.startswith('tame') or name == 'finetune-high')
            or any(rows[name][-1] != -1 for name in ('delay-bare', 'finetune-low', 'sustain-past', 'break-past')) or sum(1 for name in undefined if name.startswith('all')) < 2
            or sum(1 for name in rows if name.startswith('all') and len(rows[name]) > 1) < 3):
        raise ProbeFailure(f'xm-mixer: the reference rows are not the ones this probe was written for: undefined {undefined}')

    def render(selected, gpu):
        return PROGRAM.replace('LIBM', libm) + ''.join(
            f'    {"Unit <- " if k + 1 < len(selected) else ""}IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data({json.dumps(path)}), result => loaded(result, [{", ".join(str(op & 0xFFFFFFFF) for op in calls)}], {rate}))\n'
            for k, (_, path, calls, rate) in enumerate(selected))

    def parse(text, selected):
        got = [json.loads(line) for line in text.splitlines() if line.strip()]
        if len(got) != len(selected):
            raise ValueError('xm-mixer: candidate output did not finish')
        return got

    lanes = probe.candidates(render, items, batch=6, parse=parse, timeout=1700)
    probe.compare(expected, lanes, describe=lambda index: f'{items[index][0]} (jar_xm {expected[index][-2:]})')
    probe.finish(modules=len(items), frames=sum(op if op > 0 else OWN_FRAMES - op for _, _, calls, _ in items for op in calls if op > 0 or op <= OWN_FRAMES), undefined=len(undefined), libm=libm)


if __name__ == '__main__':
    main()
