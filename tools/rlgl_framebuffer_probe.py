#!/usr/bin/env python3
"""Compare Jonlib's rlgl framebuffer objects with the pinned raylib on rlsw.

Each scenario runs natively after InitWindow (PLATFORM=Memory) and with
Jonlib on a new frame, and prints the ids the loaders give and what
rlFramebufferComplete answers along the way:

  loader      the examples' LoadRenderTextureDepthTex: rlLoadFramebuffer,
              rlLoadTexture(NULL, w, h, R8G8B8A8, 1), rlLoadTextureDepth,
              completeness before any attachment, with the color texture and
              with both;
  bound       the same through rlEnableFramebuffer (Jonlib: Rlgl.Bound);
  sizes       a depth attachment of another size;
  channels    RL_ATTACHMENT_COLOR_CHANNEL1 and 7 (ignored by rlsw), then
              channel 0 with a cubemap face as the texture type;
  kinds       the depth attachment as a renderbuffer first, the color
              texture as a renderbuffer, the stencil and a depth attachment
              with a cubemap texture type (both ignored);
  as-depth    the color texture as the depth attachment;
  zero        rlFramebufferComplete(0);
  reuse       the ids after rlUnloadFramebuffer;
  two         two framebuffers and their textures;
  after       LoadRenderTexture after a hand-built framebuffer.

Contracts, the reference not run: a texture format or size Jonlib refuses,
a framebuffer call during texture mode (rlgl would bind framebuffer 0), and
Rlgl.render_texture for attachments that are not the framebuffer's. CPU-1,
CPU-2 and JavaScript lanes.
"""
import probekit
from probekit import ProbeFailure

SCENARIOS = ('loader', 'bound', 'sizes', 'channels', 'kinds', 'as-depth', 'zero', 'reuse', 'two', 'after')
CONTRACTS = {'format': 'format 0 0', 'size': 'size 0 0', 'texture-mode': 'texture-mode 0', 'target': 'target 1', 'target-other-depth': 'target-other-depth 0',
             'target-unattached': 'target-unattached 0'}

C_SOURCE = r'''#include "raylib.h"
#include "rlgl.h"
#include <stdio.h>
#include <string.h>
static int done(unsigned id) { return rlFramebufferComplete(id)? 1 : 0; }
static void run(const char *name)
{
    InitWindow(64, 64, "");
    printf("%s", name);
    if (!strcmp(name, "loader") || !strcmp(name, "bound"))
    {
        unsigned fbo = rlLoadFramebuffer();
        rlEnableFramebuffer(fbo);
        unsigned color = rlLoadTexture(0, 64, 48, 7, 1);
        unsigned depth = rlLoadTextureDepth(64, 48, false);
        printf(" %u %u %u", fbo, color, depth);
        if (!strcmp(name, "loader")) printf(" %d", done(fbo));
        rlFramebufferAttach(fbo, color, RL_ATTACHMENT_COLOR_CHANNEL0, RL_ATTACHMENT_TEXTURE2D, 0);
        if (!strcmp(name, "loader")) printf(" %d", done(fbo));
        rlFramebufferAttach(fbo, depth, RL_ATTACHMENT_DEPTH, RL_ATTACHMENT_TEXTURE2D, 0);
        printf(" %d", done(fbo));
        rlDisableFramebuffer();
    }
    else if (!strcmp(name, "sizes"))
    {
        unsigned fbo = rlLoadFramebuffer();
        unsigned color = rlLoadTexture(0, 64, 48, 7, 1);
        unsigned depth = rlLoadTextureDepth(32, 32, true);
        rlFramebufferAttach(fbo, color, 0, 100, 0);
        rlFramebufferAttach(fbo, depth, 100, 200, 0);
        printf(" %u %u %u %d", fbo, color, depth, done(fbo));
    }
    else if (!strcmp(name, "channels"))
    {
        unsigned fbo = rlLoadFramebuffer();
        unsigned color = rlLoadTexture(0, 16, 16, 7, 1);
        printf(" %u %u", fbo, color);
        rlFramebufferAttach(fbo, color, 1, 100, 0); printf(" %d", done(fbo));
        rlFramebufferAttach(fbo, color, 7, 100, 0); printf(" %d", done(fbo));
        rlFramebufferAttach(fbo, color, 0, 3, 0); printf(" %d", done(fbo));
    }
    else if (!strcmp(name, "kinds"))
    {
        unsigned fbo = rlLoadFramebuffer();
        unsigned color = rlLoadTexture(0, 16, 16, 7, 1);
        unsigned depth = rlLoadTextureDepth(16, 16, true);
        printf(" %u %u %u", fbo, color, depth);
        rlFramebufferAttach(fbo, depth, 100, 200, 0); printf(" %d", done(fbo));
        rlFramebufferAttach(fbo, color, 0, 200, 0); printf(" %d", done(fbo));
        rlFramebufferAttach(fbo, color, 200, 100, 0); printf(" %d", done(fbo));
        rlFramebufferAttach(fbo, color, 100, 0, 0); printf(" %d", done(fbo));
    }
    else if (!strcmp(name, "as-depth"))
    {
        unsigned fbo = rlLoadFramebuffer();
        unsigned color = rlLoadTexture(0, 16, 16, 7, 1);
        printf(" %u %u", fbo, color);
        rlFramebufferAttach(fbo, color, 100, 100, 0); printf(" %d", done(fbo));
        rlFramebufferAttach(fbo, color, 0, 100, 0); printf(" %d", done(fbo));
    }
    else if (!strcmp(name, "zero")) printf(" %d", done(0));
    else if (!strcmp(name, "reuse"))
    {
        unsigned fbo = rlLoadFramebuffer();
        unsigned color = rlLoadTexture(0, 16, 16, 7, 1);
        unsigned depth = rlLoadTextureDepth(16, 16, false);
        rlFramebufferAttach(fbo, color, 0, 100, 0);
        rlFramebufferAttach(fbo, depth, 100, 100, 0);
        printf(" %u %u %u", fbo, color, depth);
        rlUnloadFramebuffer(fbo);
        unsigned again = rlLoadFramebuffer();
        unsigned other = rlLoadTextureDepth(16, 16, false);
        printf(" %u %u", again, other);
    }
    else if (!strcmp(name, "two"))
    {
        unsigned a = rlLoadFramebuffer();
        unsigned b = rlLoadFramebuffer();
        unsigned ta = rlLoadTexture(0, 8, 8, 7, 1);
        unsigned tb = rlLoadTexture(0, 8, 8, 7, 1);
        rlFramebufferAttach(b, tb, 0, 100, 0);
        printf(" %u %u %u %u %d", a, b, ta, tb, done(b));
    }
    else if (!strcmp(name, "after"))
    {
        unsigned fbo = rlLoadFramebuffer();
        unsigned color = rlLoadTexture(0, 16, 16, 7, 1);
        unsigned depth = rlLoadTextureDepth(16, 16, false);
        RenderTexture2D target = LoadRenderTexture(16, 16);
        printf(" %u %u %u %u %u %u", fbo, color, depth, target.id, target.texture.id, target.depth.id);
    }
    printf("\n");
    CloseWindow();
}
int main(void)
{
    SetTraceLogLevel(LOG_NONE);
SCENARIOS
    return 0;
}
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M

# The frame, the framebuffer and its two textures, and the row so far.
type St is Type:
  St{frame: J.Frame, fb: J.Rlgl.Framebuffer, color: Maybe<J.Texture>, depth: Maybe<J.Texture>, text: String}

def bit(value: Bool) -> String:
  match value:
    case True{}: " 1"
    case False{}: " 0"

def fb.loaded(r: J.Frame & J.Rlgl.Framebuffer, color: Maybe<J.Texture>, depth: Maybe<J.Texture>, text: String) -> St:
  (frame, +fb) = r
  St{frame, fb, color, depth, text ++ " " ++ U32.show(J.Rlgl.Framebuffer.id(fb))}

def load.fb(st: St) -> St:
  St{frame, _, color, depth, text} = st
  fb.loaded(J.Rlgl.load_framebuffer(frame), color, depth, text)

def info.id(info: J.TextureInfo) -> U32:
  J.TextureInfo{id, _, _, _, _} = info
  id

type Seen is Type:
  Seen{texture: Maybe<J.Texture>, id: U32}

def seen.info(r: J.Texture & J.TextureInfo) -> Seen:
  (texture, +info) = r
  Seen{Some{texture}, info.id(info)}

def seen(texture: Maybe<J.Texture>) -> Seen:
  match texture:
    case None{}: Seen{None{}, 0}
    case Some{t}: seen.info(J.Texture.info(t))

def color.seen(s: Seen, frame: J.Frame, +fb: J.Rlgl.Framebuffer, depth: Maybe<J.Texture>, text: String) -> St:
  Seen{texture, +id} = s
  St{frame, fb, texture, depth, text ++ " " ++ U32.show(id)}

def color.loaded(r: J.Frame & Maybe<J.Texture>, +fb: J.Rlgl.Framebuffer, depth: Maybe<J.Texture>, text: String) -> St:
  (frame, texture) = r
  color.seen(seen(texture), frame, fb, depth, text)

def load.color(st: St, +width: U32, +height: U32) -> St:
  St{frame, +fb, _, depth, text} = st
  color.loaded(J.Rlgl.load_texture(frame, width, height, 7, 1), fb, depth, text)

def depth.seen(s: Seen, frame: J.Frame, +fb: J.Rlgl.Framebuffer, color: Maybe<J.Texture>, text: String) -> St:
  Seen{texture, +id} = s
  St{frame, fb, color, texture, text ++ " " ++ U32.show(id)}

def depth.loaded(r: J.Frame & Maybe<J.Texture>, +fb: J.Rlgl.Framebuffer, color: Maybe<J.Texture>, text: String) -> St:
  (frame, texture) = r
  depth.seen(seen(texture), frame, fb, color, text)

def load.depth(st: St, +width: U32, +height: U32, +renderbuffer: Bool) -> St:
  St{frame, +fb, color, _, text} = st
  depth.loaded(J.Rlgl.load_texture_depth(frame, width, height, renderbuffer), fb, color, text)

def color.attached.parts(frame: J.Frame, parts: J.Rlgl.Framebuffer & J.Texture, depth: Maybe<J.Texture>, text: String) -> St:
  (+fb, texture) = parts
  St{frame, fb, Some{texture}, depth, text}

def color.attached(r: J.Frame & (J.Rlgl.Framebuffer & J.Texture), depth: Maybe<J.Texture>, text: String) -> St:
  (frame, parts) = r
  color.attached.parts(frame, parts, depth, text)

# rlFramebufferAttach of the color texture with the given attachment and texture types.
def attach.color(st: St, +attach: U32, +kind: U32) -> St:
  St{frame, +fb, color, depth, text} = st
  match color:
    case None{}: St{frame, fb, None{}, depth, text ++ " missing"}
    case Some{t}: color.attached(J.Rlgl.framebuffer_attach(frame, fb, t, attach, kind, 0), depth, text)

def depth.attached.parts(frame: J.Frame, parts: J.Rlgl.Framebuffer & J.Texture, color: Maybe<J.Texture>, text: String) -> St:
  (+fb, texture) = parts
  St{frame, fb, color, Some{texture}, text}

def depth.attached(r: J.Frame & (J.Rlgl.Framebuffer & J.Texture), color: Maybe<J.Texture>, text: String) -> St:
  (frame, parts) = r
  depth.attached.parts(frame, parts, color, text)

# rlFramebufferAttach of the depth attachment.
def attach.depth(st: St, +attach: U32, +kind: U32) -> St:
  St{frame, +fb, color, depth, text} = st
  match depth:
    case None{}: St{frame, fb, color, None{}, text ++ " missing"}
    case Some{t}: depth.attached(J.Rlgl.framebuffer_attach(frame, fb, t, attach, kind, 0), color, text)

def completed(r: J.Frame & Bool, +fb: J.Rlgl.Framebuffer, color: Maybe<J.Texture>, depth: Maybe<J.Texture>, text: String) -> St:
  (frame, ok) = r
  St{frame, fb, color, depth, text ++ bit(ok)}

def complete(st: St) -> St:
  St{frame, +fb, color, depth, text} = st
  completed(J.Rlgl.framebuffer_complete(frame, fb), fb, color, depth, text)

def text.of(st: St) -> String:
  St{_, _, _, _, text} = st
  text

def start(frame: J.Frame, name: String) -> St:
  St{frame, J.Rlgl.Framebuffer.none(), None{}, None{}, name}

# The same through rlEnableFramebuffer: the loads and the first attach on the bound frame.
def bound.depth(r: J.Rlgl.Bound & Maybe<J.Texture>, +fb: J.Rlgl.Framebuffer, color: Maybe<J.Texture>, text: String) -> St:
  (bound, depth) = r
  match color:
    case None{}: St{J.Rlgl.Bound.disable(bound), fb, None{}, depth, text ++ " missing"}
    case Some{t}: color.attached(J.Rlgl.Bound.attach(bound, fb, t, 0, 100, 0), depth, text)

def bound.color(r: J.Rlgl.Bound & Maybe<J.Texture>, +fb: J.Rlgl.Framebuffer, text: String) -> St:
  (bound, color) = r
  bound.depth(J.Rlgl.Bound.load_texture_depth(bound, 64, 48, False{}), fb, color, text)

def bound.loaded(r: J.Frame & J.Rlgl.Framebuffer, text: String) -> St:
  (frame, +fb) = r
  bound.color(J.Rlgl.Bound.load_texture(J.Rlgl.enable_framebuffer(frame, fb), 64, 48, 7, 1), fb, text ++ " " ++ U32.show(J.Rlgl.Framebuffer.id(fb)))

def ids.depth(s: Seen, frame: J.Frame, +fb: J.Rlgl.Framebuffer, color: Maybe<J.Texture>, text: String) -> St:
  Seen{texture, +id} = s
  St{frame, fb, color, texture, text ++ " " ++ U32.show(id)}

def ids.color(s: Seen, frame: J.Frame, +fb: J.Rlgl.Framebuffer, depth: Maybe<J.Texture>, text: String) -> St:
  Seen{texture, +id} = s
  ids.depth(seen(depth), frame, fb, texture, text ++ " " ++ U32.show(id))

# The ids of the two textures, appended.
def ids(st: St) -> St:
  St{frame, +fb, color, depth, text} = st
  ids.color(seen(color), frame, fb, depth, text)

def frame.of(st: St) -> J.Frame:
  St{frame, _, _, _, _} = st
  frame

def unloaded(st: St) -> St:
  St{frame, +fb, color, depth, text} = st
  St{J.Rlgl.unload_framebuffer(frame, fb, depth), J.Rlgl.Framebuffer.none(), color, None{}, text}

def target.color(s: Seen) -> String:
  Seen{_, id} = s
  " " ++ U32.show(id)

def target.ids(target: Maybe<J.RenderTexture>) -> String:
  match target:
    case None{}: " none"
    case Some{J.RenderTexture{id, texture, depth}}: " " ++ U32.show(id) ++ target.color(seen(Some{texture})) ++ " " ++ U32.show(depth)

def after.loaded(r: J.Frame & Maybe<J.RenderTexture>, text: String) -> String:
  (_, target) = r
  text ++ target.ids(target)

# LoadRenderTexture after the hand-built framebuffer.
def after(st: St) -> String:
  St{frame, _, _, _, text} = st
  after.loaded(J.RenderTexture.load(frame, 16, 16), text)

# A second framebuffer and two textures; the second texture goes to the second framebuffer.
def two(st: St) -> St:
  complete(attach.color(load.color(load.color(load.fb(st), 8, 8), 8, 8), 0, 100))

def defined(r: J.Frame & Bool) -> String:
  (_, ok) = r
  bit(ok)

def made(texture: Maybe<J.Texture>) -> String:
  match texture:
    case None{}: " 0"
    case Some{_}: " 1"

def refused.texture(r: J.Frame & Maybe<J.Texture>, text: String) -> String:
  (frame, texture) = r
  text ++ made(texture) ++ defined(J.Frame.is_defined(frame))

def in.mode.loaded(r: J.Frame & J.Rlgl.Framebuffer) -> String:
  (frame, _) = r
  defined(J.Frame.is_defined(frame))

def in.mode(r: J.Frame & Maybe<J.RenderTexture>, text: String) -> String:
  (frame, target) = r
  match target:
    case None{}: text ++ " none"
    case Some{t}: text ++ in.mode.loaded(J.Rlgl.load_framebuffer(J.Frame.begin_texture_mode(frame, t)))

def some(target: Maybe<J.RenderTexture>) -> String:
  match target:
    case None{}: " 0"
    case Some{_}: " 1"

def target.built(color: Maybe<J.Texture>, +fb: J.Rlgl.Framebuffer, +depth: U32) -> String:
  match color:
    case None{}: " missing"
    case Some{t}: some(J.Rlgl.render_texture(fb, t, depth))

def target.checked(s: Seen, color: Maybe<J.Texture>, +fb: J.Rlgl.Framebuffer, +shift: U32) -> String:
  Seen{_, +id} = s
  target.built(color, fb, (id + shift : U32))

# Rlgl.render_texture with the depth attachment's id plus shift.
def target.made(st: St, +shift: U32) -> String:
  St{_, +fb, color, depth, _} = st
  target.checked(seen(depth), color, fb, shift)

def scenario(kind: U32, frame: J.Frame, +name: String) -> String:
  match kind:
    case 0: text.of(complete(attach.depth(complete(attach.color(complete(load.depth(load.color(load.fb(start(frame, name)), 64, 48), 64, 48, False{})), 0, 100)), 100, 100)))
    case 1: text.of(complete(attach.depth(ids(bound.loaded(J.Rlgl.load_framebuffer(frame), name)), 100, 100)))
    case 2: text.of(complete(attach.depth(attach.color(load.depth(load.color(load.fb(start(frame, name)), 64, 48), 32, 32, True{}), 0, 100), 100, 200)))
    case 3: text.of(complete(attach.color(complete(attach.color(complete(attach.color(load.color(load.fb(start(frame, name)), 16, 16), 1, 100)), 7, 100)), 0, 3)))
    case 4: text.of(complete(attach.color(complete(attach.color(complete(attach.color(complete(attach.depth(load.depth(load.color(load.fb(start(frame, name)), 16, 16), 16, 16, True{}), 100, 200)), 0, 200)), 200, 100)), 100, 0)))
    case 5: text.of(complete(attach.color(complete(attach.color(load.color(load.fb(start(frame, name)), 16, 16), 100, 100)), 0, 100)))
    case 6: text.of(complete(start(frame, name)))
    case 7: text.of(load.depth(load.fb(unloaded(attach.depth(attach.color(load.depth(load.color(load.fb(start(frame, name)), 16, 16), 16, 16, False{}), 0, 100), 100, 100))), 16, 16, False{}))
    case 8: text.of(two(load.fb(start(frame, name))))
    case 9: after(load.depth(load.color(load.fb(start(frame, name)), 16, 16), 16, 16, False{}))
    case 10: refused.texture(J.Rlgl.load_texture(frame, 8, 8, 4, 1), name)
    case 11: refused.texture(J.Rlgl.load_texture_depth(frame, 0, 8, False{}), name)
    case 12: in.mode(J.RenderTexture.load(frame, 8, 8), name)
    case 13: name ++ target.made(attach.depth(attach.color(load.depth(load.color(load.fb(start(frame, name)), 16, 16), 16, 16, False{}), 0, 100), 100, 100), 0)
    case 14: name ++ target.made(attach.depth(attach.color(load.depth(load.color(load.fb(start(frame, name)), 16, 16), 16, 16, False{}), 0, 100), 100, 100), 1)
    case _: name ++ target.made(attach.color(load.depth(load.color(load.fb(start(frame, name)), 16, 16), 16, 16, False{}), 0, 100), 0)

def run(frame: Maybe<J.Frame>, +kind: U32, +name: String) -> String:
  match frame:
    case None{}: name ++ " window"
    case Some{f}: scenario(kind, f, name)

def main() -> IO(Unit):
  do IO<Unit>:
'''


def native_source():
    return C_SOURCE.replace('SCENARIOS', ''.join(f'    run("{name}");\n' for name in SCENARIOS))


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('rlgl-framebuffer', args)
    output = [line.rstrip() for line in probe.native(native_source(), 'reference').splitlines() if line.split(' ')[0] in SCENARIOS]
    if [line.split(' ')[0] for line in output] != list(SCENARIOS):
        raise ProbeFailure('rlgl-framebuffer: the reference did not print every scenario')
    rows = dict(zip(SCENARIOS, output))
    if rows['loader'] != 'loader 1 2 3 0 1 1' or rows['zero'] != 'zero 1' or rows['sizes'][-1] != '0':
        raise ProbeFailure(f'rlgl-framebuffer: the reference does not behave as the scenarios assume: {rows}')
    names = list(SCENARIOS) + list(CONTRACTS)
    expected = [rows[name] if name in rows else CONTRACTS[name] for name in names]

    def render(selected, gpu):
        return PROGRAM_TEXT + ''.join(f'    IO.print(run(J.Frame.init_window(64, 64), {index}, "{name}"))\n' for index, name in selected)

    lanes = probe.candidates(render, list(enumerate(names)), batch=32, parse=lambda text, selected: [line.rstrip() for line in text.splitlines() if line.strip()])
    probe.compare(expected, lanes, describe=lambda index: names[index])
    probe.finish(scenarios=len(SCENARIOS), contracts=len(CONTRACTS))


PROGRAM_TEXT = PROGRAM


if __name__ == '__main__':
    main()
