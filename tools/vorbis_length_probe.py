#!/usr/bin/env python3
"""Compare src/vorbis_length.bend with stb_vorbis_stream_length_in_samples.

Reference. stb_vorbis.c as pinned raylib vendors it, included in the
reference program: stb_vorbis_open_memory on a stream, then a script of
calls, each stb_vorbis_stream_length_in_samples, stb_vorbis_get_frame_float
or stb_vorbis_get_samples_short_interleaved. After each call its answer is
hashed with the length the decoder keeps (total_samples) and everything
else it keeps, as the vorbis-frame gate hashes it: the length's search
moves the reader and puts it back, clears its end-of-data flag or sets it,
and can leave an error. The program's hashing and its check of the floats a
read converts are that gate's.

Candidate. Fr.memory.open, then L.stream.length, Fr.frame.float and
Fr.samples.read by the script.

The files: raylib's target.ogg, asked for its length first as LoadWave
does, after every sample is read and between reads; copies cut inside a
page and between pages, and with a byte of the last page's body changed (a
page whose checksum is wrong is no page); copies whose last page states
another position with its checksum made right (unknown, past 32 bits, 0), or
another stream structure version; and streams built here with their pages'
checksums: a small one, one whose audio shares the setup's page, ones over
64 KiB (where the search begins 64 KiB before the end) that end with their
last page, with bytes that are no page, with a page flagged as the last
before others, without a flagged page, with capture patterns and a whole
small page inside a body, with a header whose segment table the data ends
in before a small page, and with a page of empty segments cut short. CPU-1, CPU-2 and JavaScript
lanes.
"""
import json
import struct

from conformance import gradient_reference
import probekit
from probekit import ROOT, ProbeFailure
from vorbis_codebook_probe import Rng
from vorbis_ogg_probe import page, pages
import vorbis_frame_probe as fp

SOURCE = 'examples/audio/resources/target.ogg'
WORK = '.build/vorbis-length-probe/cases'
FLAGS = fp.FLAGS
MOST = fp.MOST
LENGTH = -1

# the vorbis-frame gate's hashing, its check of the floats a read converts and its buffer
SHARED = fp.NATIVE[:fp.NATIVE.index('static void run(')]

NATIVE = SHARED + r'''
static void run(const char *path, const int *ops, int count)
{
    unsigned char *data;
    int k, len, error = 0;
    unsigned roll = 2166136261u;
    stb_vorbis *f, *shadow;
    FILE *file = fopen(path, "rb");
    if (!file) exit(2);
    fseek(file, 0, SEEK_END);
    len = (int)ftell(file);
    fseek(file, 0, SEEK_SET);
    data = (unsigned char *)malloc(len? len : 1);
    if (fread(data, 1, len, file) != (size_t)len) exit(3);
    fclose(file);
    f = stb_vorbis_open_memory(data, len, &error, NULL);
    if (!f) { printf("[%d]\n", error); free(data); return; }
    shadow = stb_vorbis_open_memory(data, len, &error, NULL);
    if (!shadow) exit(4);
    roll = fnv(roll, digest(f)); roll = fnv(roll, f->sample_rate); roll = fnv(roll, f->first_audio_page_offset);
    printf("[%u, ", roll);
    for (k = 0; k < count; k++)
    {
        int i;
        unsigned got;
        if (ops[k] < 0)
        {
            got = stb_vorbis_stream_length_in_samples(f);
            if (stb_vorbis_stream_length_in_samples(shadow) != got) exit(5);
            roll = fnv(roll, got); roll = fnv(roll, f->total_samples);
            printf("%u, ", got);
        }
        else if (ops[k] == 0)
        {
            float **outputs;
            got = (unsigned)stb_vorbis_get_frame_float(f, NULL, &outputs);
            if ((unsigned)stb_vorbis_get_frame_float(shadow, NULL, &outputs) != got) exit(5);
            roll = fnv(roll, got);
        }
        else
        {
            if (ops[k] > MOST) exit(6);
            if (!clean(shadow, f->channels, ops[k])) { printf("-1]\n"); goto done; }
            got = (unsigned)stb_vorbis_get_samples_short_interleaved(f, f->channels, shorts, ops[k]);
            roll = fnv(roll, got);
            for (i = 0; i < (int)got*f->channels; i++) roll = fnv(roll, (unsigned short)shorts[i]);
        }
        roll = fnv(roll, digest(f));
        if (digest(shadow) != digest(f)) exit(7);
        printf("%u, ", roll);
    }
    printf("%u, %u, %u, %u]\n", f->total_samples, (unsigned)f->error, (unsigned)(f->eof != 0), (unsigned)(f->stream - f->stream_start));
done:
    stb_vorbis_close(f);
    stb_vorbis_close(shadow);
    free(data);
}

int main(void)
{
    // what the port takes the error to be
    if (VORBIS_cant_find_last_page != 36) return 8;
RUNS
    return 0;
}
'''.replace('MOST', str(MOST))

# the vorbis-frame gate's hashing of a decoder
DIGEST = fp.PROGRAM[:fp.PROGRAM.index('type Run is Data:')].replace('import ../../src/store.bend as R\n', 'import ../../src/store.bend as R\nimport ../../src/vorbis_length.bend as L\n')

PROGRAM = DIGEST + '''type Run is Data:
  Run{frames: Fr.Frames, kept: U32, roll: U32, out: String}

def Run.frames(run: Run) -> Fr.Frames:
  Run{frames, _, _, _} = run
  frames

def Run.kept(run: Run) -> U32:
  Run{_, kept, _, _} = run
  kept

def Run.roll(run: Run) -> U32:
  Run{_, _, roll, _} = run
  roll

def Run.out(run: Run) -> String:
  Run{_, _, _, out} = run
  out

def stepped.length(measured: L.Measured, +roll: U32, +out: String) -> Run:
  L.Measured{+frames, +total, +value} = measured
  Run{frames, total, mix(mix(mix(roll, value), total), digest(frames)), out ++ U32.show(value) ++ ", "}

def stepped.frame(got: Fr.Got, +kept: U32, +roll: U32, +out: String) -> Run:
  Fr.Got{+frames, +value} = got
  Run{frames, kept, mix(mix(roll, value), digest(frames)), out}

def stepped.read(read: Fr.Read, +kept: U32, +roll: U32, +out: String) -> Run:
  Fr.Read{+frames, +n, +samples, _} = read
  Run{frames, kept, mix(mixed(samples, mix(roll, n)), digest(frames)), out}

# A call: the stream's length for -1, stb_vorbis_get_frame_float for 0, otherwise stb_vorbis_get_samples_short_interleaved.
def step(kind: U32, +op: U32, +plan: K.Plan, +first: U32, +run: Run) -> Run:
  match kind:
    case 0: stepped.frame(Fr.frame.float(plan, Run.frames(run)), Run.kept(run), Run.roll(run), Run.out(run))
    case 1: stepped.length(L.stream.length(Run.frames(run), first, Run.kept(run)), Run.roll(run), Run.out(run))
    case _: stepped.read(Fr.samples.read(plan, Run.frames(run), op), Run.kept(run), Run.roll(run), Run.out(run))

def ending(run: Run) -> String:
  Run{+frames, +kept, _, +out} = run
  out ++ U32.show(kept) ++ ", " ++ U32.show(V.Reader.error(Fr.Frames.reader(frames))) ++ ", " ++ U32.show(flag(V.Stream.eof(V.Reader.stream(Fr.Frames.reader(frames))))) ++ ", " ++ U32.show(V.Stream.at(V.Reader.stream(Fr.Frames.reader(frames)))) ++ "]"

def told(run: Run) -> Run:
  Run{+frames, +kept, +roll, +out} = run
  Run{frames, kept, roll, out ++ U32.show(roll) ++ ", "}

# The calls in turn: a length's answer, the rolling hash after each call, and the end; -1 where a read is refused.
def run(ops: +List<U32>, on: Bool, +plan: K.Plan, +first: U32, +state: Run) -> String:
  match ops on:
    case _ False{}: Run.out(state) ++ "-1]"
    case Nil{} True{}: ending(state)
    case Con{+op, +rest} True{}:
      +next = step(Bool.pick(U32, U32.is_eq(op, 0), 0, Bool.pick(U32, U32.is_eq(op, 4294967295), 1, 2)), op, plan, first, state)
      +fine = Bool.not(Fr.Frames.refused(Run.frames(next)))
      run(rest, fine, plan, first, Bool.pick(Run, fine, told(next), state))

def opened(started: Fr.Started, +ops: +List<U32>) -> String:
  match started:
    case Fr.Unready{S.Failed{+code}}: "[" ++ U32.show(code) ++ "]"
    case Fr.Unready{_}: "[-2]"
    case Fr.Ready{+plan, +frames, +rate, +first}:
      run(ops, Bool.not(Fr.Frames.refused(frames)), plan, first, Run{frames, 0, mix(mix(mix(2166136261, digest(frames)), rate), first), "[" ++ U32.show(mix(mix(mix(2166136261, digest(frames)), rate), first)) ++ ", "})

def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>, +ops: +List<U32>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("unread")
    case Done{+bytes}: IO.print(opened(Fr.memory.open(M.LIBM{}, bytes), ops))

def main() -> IO(Unit):
  do IO<Unit>:
'''


# -----------------------------------------------------------------------------
# Pages with their checksums

def table():
    out = []
    for index in range(256):
        value = index << 24
        for _ in range(8):
            value = (value << 1 ^ (0x04C11DB7 if value & 0x80000000 else 0)) & 0xFFFFFFFF
        out.append(value)
    return out


TABLE = table()


def crc(data):
    """An Ogg page's checksum: polynomial 0x04c11db7, no reflection, from 0."""
    value = 0
    for byte in data:
        value = (value << 8 & 0xFFFFFFFF) ^ TABLE[byte ^ value >> 24]
    return value


def summed(data, at=0, size=None):
    """The data with the checksum of the page at `at` (as long as its header says, or `size`) made right."""
    size = 27 + data[at + 26] + sum(data[at + 27:at + 27 + data[at + 26]]) if size is None else size
    zeroed = data[at:at + 22] + bytes(4) + data[at + 26:at + size]
    return data[:at + 22] + struct.pack('<I', crc(zeroed)) + data[at + 26:]


def checksummed(data):
    """A well-formed stream with every page's checksum made right."""
    for at, _ in pages(data):
        data = summed(data, at)
    return data


def junk(rng, sequence, granule, segments, flag=0):
    """A page of seeded bytes that are no packets, with its checksum."""
    return summed(page(flag, granule, sequence, segments, body=bytes(rng.next(256) for _ in range(sum(segments)))))


def big(rng, count=3, last=None, granules=None, inside=None):
    """A stream over 64 KiB: the built headers, a page of audio and `count` pages of about 30 KiB of seeded bytes each; page `last`
    (the last of them, if none is said) is flagged. `inside` are (offset, bytes) put in the first of those pages' body."""
    out = checksummed(fp.headers(5) + fp.audio(fp.blocks()[:1], [500], last=-1))
    for index in range(count):
        flagged = index == (count - 1 if last is None else last)
        segments = [255] * 117 + [rng.next(255)]
        body = bytearray(rng.next(256) for _ in range(sum(segments)))
        for at, data in (inside or ()) if index == 0 else ():
            body[at:at + len(data)] = data
        out += summed(page(4 if flagged else 0, 1000 * (index + 1) if granules is None else granules[index], 3 + index, segments, body=bytes(body)))
    return out


def built():
    """name -> stream."""
    rng = Rng(0x1E9647)
    small = checksummed(fp.headers(5) + fp.audio(fp.blocks(), [500, 800]))
    # ... with no page flagged as the last: the search goes on to the data's end
    open_ended = checksummed(fp.headers(5) + fp.audio(fp.blocks(), [500, 800], last=-1))
    tiny = summed(page(4, 77, 9, []))
    out = {
        'small': small,
        # the audio shares the setup's page: the search begins at the data's start, where a page is no candidate
        'shared-page': checksummed(fp.headers(5, more=fp.blocks()[0]) + fp.audio(fp.blocks()[1:], [800])),
        # pages without checksums are no pages
        'unsummed': fp.headers(5) + fp.audio(fp.blocks(), [500, 800]),
        'big': big(rng),
        # ... followed by more than 64 KiB that are no page
        'big-junk-after': big(rng) + bytes(rng.next(256) for _ in range(66000)),
        # ... not flagged, and followed by a capture pattern with another version, letters of one, and two at the data's end
        'big-some-after': big(rng, last=-1) + bytes([0x4F, 0x67, 0x67, 0x53, 1, 0x4F, 0x4F, 0x67]) + bytes(rng.next(256) for _ in range(900)) + b'Og',
        # ... with a page flagged as the last before another, and with none flagged
        'big-early-last': big(rng, count=4, last=2),
        'big-none-last': big(rng, count=3, last=-1),
        # ... whose last page's position is past 32 bits, and all ones
        'big-past-32-bits': big(rng, granules=[1000, 2000, 0x500000007]),
        'big-unknown': big(rng, granules=[1000, 2000, 0xFFFFFFFFFFFFFFFF]),
        # ... where the search begins inside a body that has capture patterns and a page's header without its checksum
        'big-captures': big(rng, inside=[(29000, b'OggS'), (29200, tiny[:22] + bytes(4) + tiny[26:]), (29500, b'OggS' + bytes(23))]),
        # ... and a whole page of no segments, flagged as the last: it is a page
        'big-page-inside': big(rng, inside=[(29000, b'OggS'), (29200, tiny)]),
        # a header whose segment table the data ends in, before a small page that is whole: the search ends at the header
        'table-cut': open_ended + page(0, 900, 4, [])[:26] + bytes([255]) + summed(page(4, 123456, 8, [10, 20])),
        # a page of empty segments, cut short: the zeros past the data's end are the ones it has
        'zeros-cut': open_ended + summed(page(4, 4321, 4, [0] * 12))[:-5],
        # ... and one cut inside its header
        'header-cut': open_ended + summed(page(4, 4321, 4, [0] * 12))[:20],
    }
    return out


# -----------------------------------------------------------------------------
# The calls

FIRST = [LENGTH, 88200, LENGTH]                              # as LoadWave: the length, then every sample at once
AFTER = [MOST, LENGTH, LENGTH, 2]                            # after the data's end is read
BETWEEN = [LENGTH, 0, 10, LENGTH, 0, 0, 300, LENGTH, MOST, LENGTH]
SOME = [LENGTH, 0, 10, LENGTH, 0, LENGTH]
TWICE = [LENGTH, LENGTH, 64, LENGTH]


def cases(source):
    """name -> (stream, calls)."""
    where = pages(source)
    last, size = where[-1]
    out = {'whole': (source, FIRST), 'whole-after': (source, AFTER), 'whole-between': (source, BETWEEN)}
    # the data cut in the last page, at its start, and in the page before
    for cut in (len(source) - 1, last + 40, last, last - 700):
        out[f'cut-{cut}'] = (source[:cut], TWICE)
    # a byte of the last page's body changed, and of the first audio page's
    for name, at in (('body-last', last + size - 9), ('body-first', where[2][0] + where[2][1] - 9)):
        out[name] = (source[:at] + bytes([source[at] ^ 0x10]) + source[at + 1:], TWICE)
    # the last page with another position, its checksum made right: unknown, past 32 bits, 0 and one before the samples' end
    for name, granule in (('unknown', 0xFFFFFFFFFFFFFFFF), ('past-32-bits', 0x100000000), ('zero', 0), ('early', 30000), ('high-ones', 0xFFFFFFFF00000005), ('low-ones', 0xFFFFFFFF)):
        out[name] = (summed(source[:last + 6] + struct.pack('<Q', granule) + source[last + 14:], last), SOME if name in ('zero', 'early') else TWICE)
    # ... with another version, and not flagged as the last
    out['version'] = (summed(source[:last + 4] + b'\x01' + source[last + 5:], last), TWICE)
    out['unflagged'] = (summed(source[:last + 5] + b'\x00' + source[last + 6:], last), TWICE)
    for name, data in built().items():
        out[name] = (data, BETWEEN if name == 'small' else TWICE)
    return out


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('vorbis-length', args)
    libm = gradient_reference()
    folder = ROOT / WORK
    folder.mkdir(parents=True, exist_ok=True)
    files = cases((args.raylib_source / SOURCE).read_bytes())
    items = []
    for name, (data, calls) in files.items():
        (folder / f'{name}.ogg').write_bytes(data)
        items.append((name, f'{WORK}/{name}.ogg', calls))
    runs = '\n'.join(f'    {{ static const int ops[] = {{{", ".join(str(op) for op in calls)}}}; run({json.dumps(str(ROOT / path))}, ops, {len(calls)}); }}' for _, path, calls in items)
    expected = [json.loads(line) for line in probe.native(NATIVE.replace('RUNS', runs), 'reference', extra_flags=FLAGS, link_raylib=False).splitlines()]
    if len(expected) != len(items):
        raise ProbeFailure(f'vorbis-length: the reference printed {len(expected)} rows for {len(items)} items')
    rows = {name: row for (name, _, _), row in zip(items, expected)}
    kept = {name: row[-4] for name, row in rows.items()}
    wanted = {'whole': 44100, 'whole-after': 44100, 'unknown': 0xFFFFFFFF, 'past-32-bits': 0xFFFFFFFE, 'zero': 0, 'early': 30000, 'high-ones': 0xFFFFFFFE, 'low-ones': 0xFFFFFFFF, 'small': 800, 'shared-page': 0xFFFFFFFF,
              'unsummed': 0xFFFFFFFF, 'big': 3000, 'big-junk-after': 0xFFFFFFFF, 'big-some-after': 3000, 'big-early-last': 3000, 'big-none-last': 3000, 'big-past-32-bits': 0xFFFFFFFE, 'big-unknown': 0xFFFFFFFF,
              'big-captures': 3000, 'big-page-inside': 77, 'table-cut': 800, 'zeros-cut': 4321, 'header-cut': 800}
    # what the corpus is for: each stream's length is the one its pages were given (a page that is cut, whose checksum is wrong or
    # whose version is another gives the page before it), no read is refused, and the error is there with the lengths not known
    wrong = {name: kept[name] for name, value in wanted.items() if kept[name] != value}
    if (wrong or any(row[-1] == -1 or len(row) < 6 for row in expected) or len({kept[name] for name in files if name.startswith('cut-')}) < 2 or any(kept[name] == 44100 for name in files if name.startswith('cut-')) or kept['body-last'] == 44100 or kept['body-first'] != 44100 or kept['version'] == 44100
            or kept['unflagged'] != 44100 or any((row[-3] == 36) != (row[-4] == 0xFFFFFFFF) for name, row in rows.items() if name != 'low-ones') or rows['low-ones'][-3] != 0
            or any(len(data) < 65536 + 4096 for name, (data, _) in files.items() if name.startswith('big'))):
        raise ProbeFailure(f'vorbis-length: the reference runs are not the ones this probe was written for: {wrong} of {kept}')

    def render(selected, gpu):
        lines = []
        for k, (name, path, calls) in enumerate(selected):
            bound = 'Unit <- ' if k + 1 < len(selected) else ''
            lines.append(f'    {bound}IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data({json.dumps(path)}), result => loaded(result, [{", ".join(str(op & 0xFFFFFFFF) for op in calls)}]))\n')
        return PROGRAM.replace('LIBM', libm) + ''.join(lines)

    def parse(text, selected):
        got = [json.loads(line) for line in text.splitlines() if line.strip()]
        if len(got) != len(selected):
            raise ValueError('vorbis-length: candidate output did not finish')
        return got

    lanes = probe.candidates(render, items, batch=6, parse=parse, timeout=1700)

    def describe(index):
        for got in lanes.values():
            a, b = expected[index], got[index]
            if a != b:
                at = next((k for k, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
                return f'{items[index][0]}: differs at {at} of {len(a)} (stb ends {a[-4:]}, jonlib {b[-4:]})'
        return items[index][0]

    probe.compare(expected, lanes, describe=describe)
    probe.finish(files=len(items), calls=sum(len(calls) for _, _, calls in items), lengths=sum(calls.count(LENGTH) for _, _, calls in items), unknown=sum(1 for value in kept.values() if value == 0xFFFFFFFF), libm=libm)


if __name__ == '__main__':
    main()
