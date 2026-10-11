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
  after       LoadRenderTexture after a hand-built framebuffer;
  blind       a framebuffer with a depth attachment alone (a shadow map's)
              as BeginTextureMode's target on an 8x8 window: the projection
              its size gives, the active framebuffer, and the screen after a
              clear and a rectangle that rlsw drops (the framebuffer is
              incomplete) and a rectangle drawn after EndTextureMode;
  blind-clear the same, then rlClearScreenBuffers: the clear color set
              during the texture mode;
  blind-bare  a framebuffer without attachments;
  blind-after rlUnloadFramebuffer after such a texture mode, then
              LoadRenderTexture (the same framebuffer id), drawn into and
              drawn on the screen;
  formats     rlLoadTexture(NULL, ...) in the float formats 8 to 13, which
              OpenGL 1.1 does not support (ids of textures without storage),
              and R16G16B16 as the color attachment (incomplete);
  blind-gbuffer  a deferred renderer's G-buffer: an R16G16B16 texture on
              channel 0, an R8G8B8A8 one on channel 2 (ignored) and a depth
              renderbuffer, bound with rlEnableFramebuffer to draw (the
              clear and the rectangle are dropped, the clear color is set),
              then rlBindFramebuffer for reading (a rectangle is dropped)
              and back to 0, and the R16G16B16 texture drawn (untextured).

Contracts, the reference not run: a texture format or size Jonlib refuses,
a framebuffer call during texture mode (rlgl would bind framebuffer 0),
Rlgl.render_texture for attachments that are not the framebuffer's,
Rlgl.render_texture_depth for a framebuffer with a color attachment, for
another depth id, for framebuffer 0 and for a size of 0, and a texture mode
on a framebuffer without a color attachment started during another one;
rlEnableFramebuffer to draw for a complete framebuffer, for framebuffer 0
and during texture mode, and a compressed texture format. CPU-1, CPU-2 and
JavaScript lanes.
"""
import probekit
from probekit import ProbeFailure

SCENARIOS = ('loader', 'bound', 'sizes', 'channels', 'kinds', 'as-depth', 'zero', 'reuse', 'two', 'after', 'blind', 'blind-clear', 'blind-bare', 'blind-after', 'formats',
             'blind-gbuffer')
CONTRACTS = {'format': 'format 0 0', 'size': 'size 0 0', 'texture-mode': 'texture-mode 0', 'target': 'target 1', 'target-other-depth': 'target-other-depth 0',
             'target-unattached': 'target-unattached 0', 'depth-target': 'depth-target 1', 'depth-target-color': 'depth-target-color 0',
             'depth-target-other': 'depth-target-other 0', 'depth-target-zero': 'depth-target-zero 0', 'depth-target-size': 'depth-target-size 0',
             'blind-nested': 'blind-nested 0', 'incomplete-complete': 'incomplete-complete 0', 'incomplete-zero': 'incomplete-zero 0',
             'incomplete-in-mode': 'incomplete-in-mode 0', 'format-compressed': 'format-compressed 0 0'}
COLORS = {'BLUE': (0, 121, 241, 255), 'GREEN': (0, 228, 48, 255), 'RED': (230, 41, 55, 255), 'YELLOW': (253, 249, 0, 255), 'WHITE': (255, 255, 255, 255)}


def word(name):
    r, g, b, a = COLORS[name]
    return (r << 24) | (g << 16) | (b << 8) | a


def pixels(row):
    """The words of a row's screen (its last field)."""
    text = row.split(' ')[-1]
    return [text[i:i + 8] for i in range(0, len(text), 8)]


def size(name):
    """The window's side: the scenarios that compare the screen use a small one."""
    return 8 if name.startswith('blind') else 64


C_SOURCE = r'''#include "raylib.h"
#include "rlgl.h"
#include <stdio.h>
#include <string.h>
static int done(unsigned id) { return rlFramebufferComplete(id)? 1 : 0; }
static void dump(void)
{
    unsigned char p[8*8*4];
    rlCopyFramebuffer(0, 0, 8, 8, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, p);
    printf(" ");
    for (int i = 0; i < 64; i++) printf("%02x%02x%02x%02x", p[4*i + 2], p[4*i + 1], p[4*i], p[4*i + 3]);
}
static void run(const char *name)
{
    int side = strncmp(name, "blind", 5)? 64 : 8;
    InitWindow(side, side, "");
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
    else if (!strcmp(name, "blind") || !strcmp(name, "blind-clear") || !strcmp(name, "blind-bare"))
    {
        RenderTexture2D target = { 0 };
        target.id = rlLoadFramebuffer();
        target.texture.width = 4;
        target.texture.height = 2;
        printf(" %u", target.id);
        if (strcmp(name, "blind-bare"))
        {
            target.depth.id = rlLoadTextureDepth(4, 2, false);
            printf(" %u", target.depth.id);
            rlFramebufferAttach(target.id, target.depth.id, RL_ATTACHMENT_DEPTH, RL_ATTACHMENT_TEXTURE2D, 0);
        }
        printf(" %d", done(target.id));
        BeginDrawing();
        ClearBackground(BLUE);
        DrawRectangle(0, 0, 2, 2, GREEN);
        BeginTextureMode(target);
        ClearBackground(WHITE);
        DrawRectangle(0, 0, 8, 8, RED);
        Matrix projection = rlGetMatrixProjection();
        unsigned a, b;
        memcpy(&a, &projection.m0, 4);
        memcpy(&b, &projection.m5, 4);
        printf(" %u %u %u", a, b, rlGetActiveFramebuffer());
        EndTextureMode();
        printf(" %u %u %u", target.id, target.texture.id, target.depth.id);
        if (!strcmp(name, "blind-clear")) rlClearScreenBuffers();
        DrawRectangle(2, 2, 2, 2, YELLOW);
        dump();
        EndDrawing();
    }
    else if (!strcmp(name, "blind-after"))
    {
        RenderTexture2D blind = { 0 };
        blind.id = rlLoadFramebuffer();
        blind.texture.width = 4;
        blind.texture.height = 2;
        blind.depth.id = rlLoadTextureDepth(4, 2, false);
        printf(" %u %u", blind.id, blind.depth.id);
        rlFramebufferAttach(blind.id, blind.depth.id, RL_ATTACHMENT_DEPTH, RL_ATTACHMENT_TEXTURE2D, 0);
        BeginTextureMode(blind);
        ClearBackground(WHITE);
        DrawRectangle(0, 0, 8, 8, RED);
        EndTextureMode();
        rlUnloadFramebuffer(blind.id);
        RenderTexture2D target = LoadRenderTexture(4, 4);
        printf(" %u %u %u", target.id, target.texture.id, target.depth.id);
        BeginTextureMode(target);
        ClearBackground(RED);
        DrawRectangle(0, 0, 2, 2, GREEN);
        EndTextureMode();
        BeginDrawing();
        ClearBackground(BLUE);
        DrawTexture(target.texture, 1, 1, WHITE);
        dump();
        EndDrawing();
    }
    else if (!strcmp(name, "formats"))
    {
        unsigned fbo = rlLoadFramebuffer();
        printf(" %u", fbo);
        for (int format = 8; format <= 11; format++) printf(" %u", rlLoadTexture(0, 16, 16, format, 1));
        printf(" %u", rlLoadTexture(0, 16, 16, 13, 1));
        unsigned half = rlLoadTexture(0, 16, 16, 12, 1);
        printf(" %u", half);
        rlFramebufferAttach(fbo, half, 0, 100, 0);
        printf(" %d", done(fbo));
        unsigned color = rlLoadTexture(0, 16, 16, 7, 1);
        printf(" %u", color);
        rlFramebufferAttach(fbo, color, 0, 100, 0);
        printf(" %d", done(fbo));
    }
    else if (!strcmp(name, "blind-gbuffer"))
    {
        unsigned fbo = rlLoadFramebuffer();
        unsigned position = rlLoadTexture(0, 8, 8, 12, 1);
        unsigned albedo = rlLoadTexture(0, 8, 8, 7, 1);
        rlActiveDrawBuffers(3);
        rlFramebufferAttach(fbo, albedo, RL_ATTACHMENT_COLOR_CHANNEL2, RL_ATTACHMENT_TEXTURE2D, 0);
        rlFramebufferAttach(fbo, position, RL_ATTACHMENT_COLOR_CHANNEL0, RL_ATTACHMENT_TEXTURE2D, 0);
        unsigned depth = rlLoadTextureDepth(8, 8, true);
        rlFramebufferAttach(fbo, depth, RL_ATTACHMENT_DEPTH, RL_ATTACHMENT_RENDERBUFFER, 0);
        printf(" %u %u %u %u %d", fbo, position, albedo, depth, done(fbo));
        BeginDrawing();
        ClearBackground(BLUE);
        rlEnableFramebuffer(fbo);
        rlClearColor(0, 0, 0, 0);
        rlClearScreenBuffers();
        DrawRectangle(0, 0, 8, 8, RED);
        printf(" %u", rlGetActiveFramebuffer());
        rlDisableFramebuffer();
        DrawRectangle(0, 0, 2, 2, GREEN);
        dump();
        rlClearScreenBuffers();
        rlBindFramebuffer(RL_READ_FRAMEBUFFER, fbo);
        DrawRectangle(0, 0, 8, 8, RED);
        rlBindFramebuffer(RL_DRAW_FRAMEBUFFER, 0);
        DrawRectangle(2, 2, 2, 2, YELLOW);
        DrawTexture((Texture2D){ position, 8, 8, 1, 12 }, 4, 4, WHITE);
        dump();
        EndDrawing();
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

# rlLoadTexture(NULL, width, height, format, 1) as the color texture, its id appended.
def load.as(st: St, +width: U32, +height: U32, +format: U32) -> St:
  St{frame, +fb, _, depth, text} = st
  color.loaded(J.Rlgl.load_texture(frame, width, height, format, 1), fb, depth, text)

def spare.parts(frame: J.Frame, parts: J.Rlgl.Framebuffer & J.Texture, color: Maybe<J.Texture>, depth: Maybe<J.Texture>, text: String) -> St:
  (+fb, _) = parts
  St{frame, fb, color, depth, text}

def spare.attached(r: J.Frame & (J.Rlgl.Framebuffer & J.Texture), color: Maybe<J.Texture>, depth: Maybe<J.Texture>, text: String) -> St:
  (frame, parts) = r
  spare.parts(frame, parts, color, depth, text)

def spare.seen(s: Seen, frame: J.Frame, +fb: J.Rlgl.Framebuffer, color: Maybe<J.Texture>, depth: Maybe<J.Texture>, text: String) -> St:
  Seen{texture, +id} = s
  match texture:
    case None{}: St{frame, fb, color, depth, text ++ " 0"}
    case Some{t}: spare.attached(J.Rlgl.framebuffer_attach(frame, fb, t, 2, 100, 0), color, depth, text ++ " " ++ U32.show(id))

def spare.loaded(r: J.Frame & Maybe<J.Texture>, +fb: J.Rlgl.Framebuffer, color: Maybe<J.Texture>, depth: Maybe<J.Texture>, text: String) -> St:
  (frame, texture) = r
  spare.seen(seen(texture), frame, fb, color, depth, text)

# An R8G8B8A8 texture, its id appended, attached to RL_ATTACHMENT_COLOR_CHANNEL2 (which rlsw ignores).
def load.spare(st: St) -> St:
  St{frame, +fb, color, depth, text} = st
  spare.loaded(J.Rlgl.load_texture(frame, 8, 8, 7, 1), fb, color, depth, text)

def hex.digit(+d: U32) -> Char:
  Chr{Bool.pick(U32, (d < 10 : U32), (d + 48 : U32), (d + 87 : U32))}

def hex.word(+w: U32, rest: String) -> String:
  SCon{hex.digit((w >> 28n : U32)), SCon{hex.digit(((w >> 24n) .&. 15 : U32)), SCon{hex.digit(((w >> 20n) .&. 15 : U32)),
    SCon{hex.digit(((w >> 16n) .&. 15 : U32)), SCon{hex.digit(((w >> 12n) .&. 15 : U32)), SCon{hex.digit(((w >> 8n) .&. 15 : U32)),
    SCon{hex.digit(((w >> 4n) .&. 15 : U32)), SCon{hex.digit((w .&. 15 : U32)), rest}}}}}}}}

def hex.words(n: Nat, +i: U32, read: Array<U32> & U32, acc: String) -> String:
  match n read:
    case 0n _: acc
    case 1n+k Tuple{pixels, +w}: hex.words(k, (i - 1 : U32), Array.get(U32, pixels, (i - 1 : U32)), hex.word(w, acc))

def hex.pixels(+count: U32, pixels: J.Surface.Pixels) -> String:
  match pixels:
    case J.Words{values}: hex.words(U32.to_nat(count), (count - 1 : U32), Array.get(U32, values, (count - 1 : U32)), "")
    case J.Quads{_}: "quads"

def hex.surface(surface: J.Surface) -> String:
  J.Surface{+w, +h, _, pixels} = surface
  hex.pixels((w * h : U32), pixels)

def hex.maybe(surface: Maybe<J.Surface>) -> String:
  match surface:
    case None{}: "null"
    case Some{s}: hex.surface(s)

# The screen's color buffer, appended.
def blind.shown(r: J.Frame & Maybe<J.Surface>, text: String) -> String:
  (_, surface) = r
  text ++ " " ++ hex.maybe(surface)

def blind.cleared(clear: Bool, frame: J.Frame) -> J.Frame:
  match clear:
    case True{}: J.Rlgl.clear_screen_buffers(frame)
    case False{}: frame

# After EndTextureMode: the RenderTexture handed back, rlClearScreenBuffers if asked, a yellow square and the screen.
def blind.ended(r: J.Frame & Maybe<J.RenderTexture>, +clear: Bool, text: String) -> String:
  (frame, target) = r
  match target:
    case None{}: text ++ " lost"
    case Some{t}: blind.shown(J.Frame.framebuffer(J.Draw.rectangle(blind.cleared(clear, frame), 2.0, 2.0, 2.0, 2.0, @YELLOW@)), text ++ target.ids(Some{t}))

def blind.inside(r: J.Frame & String, +clear: Bool) -> String:
  (frame, text) = r
  blind.ended(J.Frame.end_texture_mode(frame), clear, text)

def blind.active(r: J.Frame & U32, text: String) -> J.Frame & String:
  (frame, +id) = r
  (frame, text ++ " " ++ U32.show(id))

def matrix.scale(m: M.Matrix) -> String:
  M.Matrix{+m0, _, _, _, _, +m5, _, _, _, _, _, _, _, _, _, _} = m
  " " ++ U32.show(F32.bits(m0)) ++ " " ++ U32.show(F32.bits(m5))

def blind.projected(r: J.Frame & M.Matrix, text: String) -> J.Frame & String:
  (frame, m) = r
  blind.active(J.Rlgl.get_active_framebuffer(frame), text ++ matrix.scale(m))

# A blue screen with a green square, then the texture mode: a white clear and a red rectangle.
def blind.mode(frame: J.Frame, target: Maybe<J.RenderTexture>, +clear: Bool, text: String) -> String:
  match target:
    case None{}: text ++ " none"
    case Some{t}: blind.inside(blind.projected(J.Rlgl.get_matrix_projection(J.Draw.rectangle(J.Frame.clear_background(J.Frame.begin_texture_mode(
      J.Draw.rectangle(J.Frame.clear_background(J.Frame.begin_drawing(frame), @BLUE@), 0.0, 0.0, 2.0, 2.0, @GREEN@), t), @WHITE@), 0.0, 0.0, 8.0, 8.0, @RED@)), text), clear)

def blind.sized(s: Seen, frame: J.Frame, +fb: J.Rlgl.Framebuffer, +clear: Bool, text: String) -> String:
  Seen{_, +id} = s
  blind.mode(frame, J.Rlgl.render_texture_depth(fb, 4, 2, id), clear, text)

# The texture mode of the framebuffer's 4x2 RenderTexture2D without a color texture.
def blind.built(st: St, +clear: Bool) -> String:
  St{frame, +fb, _, depth, text} = st
  blind.sized(seen(depth), frame, fb, clear, text)

def after.shown(r: J.Frame & J.Texture, text: String) -> String:
  (frame, _) = r
  blind.shown(J.Frame.framebuffer(frame), text)

def after.screen(r: J.Frame & Maybe<J.RenderTexture>, text: String) -> String:
  (frame, target) = r
  match target:
    case None{}: text ++ " lost"
    case Some{J.RenderTexture{_, texture, _}}: after.shown(J.Draw.texture(J.Frame.clear_background(J.Frame.begin_drawing(frame), @BLUE@), texture, 1.0, 1.0, @WHITE@), text)

def after.named(r: J.Texture & J.TextureInfo, frame: J.Frame, +id: U32, +depth: U32, text: String) -> String:
  (texture, +info) = r
  after.screen(J.Frame.end_texture_mode(J.Draw.rectangle(J.Frame.clear_background(J.Frame.begin_texture_mode(frame, J.RenderTexture{id, texture, depth}), @RED@), 0.0, 0.0, 2.0, 2.0, @GREEN@)),
    text ++ " " ++ U32.show(id) ++ " " ++ U32.show(info.id(info)) ++ " " ++ U32.show(depth))

def after.painted(frame: J.Frame, target: J.RenderTexture, text: String) -> String:
  J.RenderTexture{+id, texture, +depth} = target
  after.named(J.Texture.info(texture), frame, id, depth, text)

def after.target(r: J.Frame & Maybe<J.RenderTexture>, text: String) -> String:
  (frame, target) = r
  match target:
    case None{}: text ++ " none"
    case Some{t}: after.painted(frame, t, text)

# rlUnloadFramebuffer, then LoadRenderTexture, drawn into and drawn on the screen.
def after.reloaded(st: St) -> String:
  St{frame, _, _, _, text} = st
  after.target(J.RenderTexture.load(frame, 4, 4), text)

def after.left(r: J.Frame & Maybe<J.RenderTexture>, +fb: J.Rlgl.Framebuffer, depth: Maybe<J.Texture>, text: String) -> String:
  (frame, _) = r
  after.reloaded(unloaded(St{frame, fb, None{}, depth, text}))

def after.moded(target: Maybe<J.RenderTexture>, frame: J.Frame, +fb: J.Rlgl.Framebuffer, depth: Maybe<J.Texture>, text: String) -> String:
  match target:
    case None{}: text ++ " none"
    case Some{t}: after.left(J.Frame.end_texture_mode(J.Draw.rectangle(J.Frame.clear_background(J.Frame.begin_texture_mode(frame, t), @WHITE@), 0.0, 0.0, 8.0, 8.0, @RED@)), fb, depth, text)

def after.entered(s: Seen, frame: J.Frame, +fb: J.Rlgl.Framebuffer, text: String) -> String:
  Seen{depth, +id} = s
  after.moded(J.Rlgl.render_texture_depth(fb, 4, 2, id), frame, fb, depth, text)

def after.blind(st: St) -> String:
  St{frame, +fb, _, depth, text} = st
  after.entered(seen(depth), frame, fb, text)

def depth.target.checked(s: Seen, +fb: J.Rlgl.Framebuffer, +width: U32, +shift: U32) -> String:
  Seen{_, +id} = s
  some(J.Rlgl.render_texture_depth(fb, width, 16, (id + shift : U32)))

# Rlgl.render_texture_depth with the given width and the depth attachment's id plus shift.
def depth.target(st: St, +width: U32, +shift: U32) -> String:
  St{_, +fb, _, depth, _} = st
  depth.target.checked(seen(depth), fb, width, shift)

def nested.inside(target: Maybe<J.RenderTexture>, frame: J.Frame) -> String:
  match target:
    case None{}: " none"
    case Some{t}: defined(J.Frame.is_defined(J.Frame.begin_texture_mode(frame, t)))

def nested.loaded(r: J.Frame & Maybe<J.RenderTexture>, +fb: J.Rlgl.Framebuffer) -> String:
  (frame, target) = r
  match target:
    case None{}: " none"
    case Some{t}: nested.inside(J.Rlgl.render_texture_depth(fb, 4, 2, 0), J.Frame.begin_texture_mode(frame, t))

# A texture mode on a framebuffer without attachments started during LoadRenderTexture's.
def nested(st: St) -> String:
  St{frame, +fb, _, _, _} = st
  nested.loaded(J.RenderTexture.load(frame, 8, 8), fb)

def gbuffer.second(r: J.Frame & J.Texture, text: String) -> String:
  (frame, _) = r
  blind.shown(J.Frame.framebuffer(frame), text)

# The screen so far; rlClearScreenBuffers; rlBindFramebuffer(RL_READ_FRAMEBUFFER, fb), a red rectangle;
# rlBindFramebuffer(RL_DRAW_FRAMEBUFFER, 0), a yellow square and the position texture.
def gbuffer.first(r: J.Frame & Maybe<J.Surface>, +fb: J.Rlgl.Framebuffer, position: J.Texture, text: String) -> String:
  (frame, surface) = r
  gbuffer.second(J.Draw.texture(J.Draw.rectangle(J.Rlgl.bind_framebuffer(J.Draw.rectangle(J.Rlgl.bind_framebuffer(J.Rlgl.clear_screen_buffers(frame), 36008, fb), 0.0, 0.0, 8.0, 8.0, @RED@),
    36009, J.Rlgl.Framebuffer.none()), 2.0, 2.0, 2.0, 2.0, @YELLOW@), position, 4.0, 4.0, @WHITE@), text ++ " " ++ hex.maybe(surface))

def gbuffer.active(r: J.Frame & U32, +fb: J.Rlgl.Framebuffer, position: J.Texture, text: String) -> String:
  (frame, +id) = r
  gbuffer.first(J.Frame.framebuffer(J.Draw.rectangle(J.Rlgl.disable_framebuffer(frame), 0.0, 0.0, 2.0, 2.0, @GREEN@)), fb, position, text ++ " " ++ U32.show(id))

# A blue screen; rlEnableFramebuffer(fb); rlClearColor(0, 0, 0, 0); rlClearScreenBuffers(); a red rectangle.
def gbuffer.pass(color: Maybe<J.Texture>, frame: J.Frame, +fb: J.Rlgl.Framebuffer, text: String) -> String:
  match color:
    case None{}: text ++ " missing"
    case Some{position}: gbuffer.active(J.Rlgl.get_active_framebuffer(J.Draw.rectangle(J.Rlgl.clear_screen_buffers(J.Rlgl.clear_color(J.Rlgl.enable_framebuffer_incomplete(
      J.Frame.clear_background(J.Frame.begin_drawing(frame), @BLUE@), fb), 0, 0, 0, 0)), 0.0, 0.0, 8.0, 8.0, @RED@)), fb, position, text)

def gbuffer(st: St) -> String:
  St{frame, +fb, color, _, text} = st
  gbuffer.pass(color, frame, fb, text)

# rlEnableFramebuffer to draw: the frame is undefined afterwards.
def incomplete(st: St) -> String:
  St{frame, +fb, _, _, _} = st
  defined(J.Frame.is_defined(J.Rlgl.enable_framebuffer_incomplete(frame, fb)))

def incomplete.inside(target: Maybe<J.RenderTexture>, frame: J.Frame, +fb: J.Rlgl.Framebuffer) -> String:
  match target:
    case None{}: " none"
    case Some{t}: defined(J.Frame.is_defined(J.Rlgl.enable_framebuffer_incomplete(J.Frame.begin_texture_mode(frame, t), fb)))

def incomplete.loaded(r: J.Frame & Maybe<J.RenderTexture>, +fb: J.Rlgl.Framebuffer) -> String:
  (frame, target) = r
  incomplete.inside(target, frame, fb)

# The same during LoadRenderTexture's texture mode.
def incomplete.mode(st: St) -> String:
  St{frame, +fb, _, _, _} = st
  incomplete.loaded(J.RenderTexture.load(frame, 8, 8), fb)

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
    case 10: blind.built(complete(attach.depth(load.depth(load.fb(start(frame, name)), 4, 2, False{}), 100, 100)), False{})
    case 11: blind.built(complete(attach.depth(load.depth(load.fb(start(frame, name)), 4, 2, False{}), 100, 100)), True{})
    case 12: blind.built(complete(load.fb(start(frame, name))), False{})
    case 13: after.blind(attach.depth(load.depth(load.fb(start(frame, name)), 4, 2, False{}), 100, 100))
    case 14: text.of(complete(attach.color(load.color(complete(attach.color(load.as(load.as(load.as(load.as(load.as(load.as(load.fb(start(frame, name)), 16, 16, 8), 16, 16, 9), 16, 16, 10),
      16, 16, 11), 16, 16, 13), 16, 16, 12), 0, 100)), 16, 16), 0, 100)))
    case 15: gbuffer(complete(attach.depth(load.depth(attach.color(load.spare(load.as(load.fb(start(frame, name)), 8, 8, 12)), 0, 100), 8, 8, True{}), 100, 200)))
    case 16: refused.texture(J.Rlgl.load_texture(frame, 8, 8, 4, 1), name)
    case 17: refused.texture(J.Rlgl.load_texture_depth(frame, 0, 8, False{}), name)
    case 18: in.mode(J.RenderTexture.load(frame, 8, 8), name)
    case 19: name ++ target.made(attach.depth(attach.color(load.depth(load.color(load.fb(start(frame, name)), 16, 16), 16, 16, False{}), 0, 100), 100, 100), 0)
    case 20: name ++ target.made(attach.depth(attach.color(load.depth(load.color(load.fb(start(frame, name)), 16, 16), 16, 16, False{}), 0, 100), 100, 100), 1)
    case 21: name ++ target.made(attach.color(load.depth(load.color(load.fb(start(frame, name)), 16, 16), 16, 16, False{}), 0, 100), 0)
    case 22: name ++ depth.target(attach.depth(load.depth(load.fb(start(frame, name)), 16, 16, False{}), 100, 100), 16, 0)
    case 23: name ++ depth.target(attach.depth(attach.color(load.depth(load.color(load.fb(start(frame, name)), 16, 16), 16, 16, False{}), 0, 100), 100, 100), 16, 0)
    case 24: name ++ depth.target(attach.depth(load.depth(load.fb(start(frame, name)), 16, 16, False{}), 100, 100), 16, 1)
    case 25: name ++ depth.target(attach.depth(load.depth(start(frame, name), 16, 16, False{}), 100, 100), 16, 0)
    case 26: name ++ depth.target(attach.depth(load.depth(load.fb(start(frame, name)), 16, 16, False{}), 100, 100), 0, 0)
    case 27: name ++ nested(load.fb(start(frame, name)))
    case 28: name ++ incomplete(attach.color(load.color(load.fb(start(frame, name)), 8, 8), 0, 100))
    case 29: name ++ incomplete(start(frame, name))
    case 30: name ++ incomplete.mode(load.fb(start(frame, name)))
    case _: refused.texture(J.Rlgl.load_texture(frame, 8, 8, 14, 1), name)

def run(frame: Maybe<J.Frame>, +kind: U32, +name: String) -> String:
  match frame:
    case None{}: name ++ " window"
    case Some{f}: scenario(kind, f, name)

def main() -> IO(Unit):
  do IO<Unit>:
'''


for _name in COLORS:
    PROGRAM = PROGRAM.replace(f'@{_name}@', str(word(_name)))


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
    green, yellow, red, white, blue = (f'{word(name):08x}' for name in ('GREEN', 'YELLOW', 'RED', 'WHITE', 'BLUE'))
    screen, cleared, after = (pixels(rows[name]) for name in ('blind', 'blind-clear', 'blind-after'))
    if len(screen) != 64 or screen[0] != green or screen.count(yellow) != 4 or screen.count(blue) != 56 or rows['blind'].split(' ')[3] != '0':
        raise ProbeFailure(f'rlgl-framebuffer: the reference drew into a framebuffer without a color attachment: {rows["blind"]}')
    if cleared.count(white) != 60 or cleared.count(yellow) != 4 or after.count(red) != 12 or after.count(green) != 4 or after.count(blue) != 48:
        raise ProbeFailure(f'rlgl-framebuffer: the reference does not behave as the blind scenarios assume: {rows}')
    first, second = (pixels(' '.join(rows['blind-gbuffer'].split(' ')[:k])) for k in (8, 9))
    if rows['blind-gbuffer'].split(' ')[5:7] != ['0', '1'] or first.count(blue) != 60 or first.count(green) != 4 or second.count('00000000') != 44 or second.count(yellow) != 4 \
            or second.count(white) != 16 or rows['formats'].split(' ')[-3] != '0' or rows['formats'].split(' ')[-1] != '1':
        raise ProbeFailure(f'rlgl-framebuffer: the reference does not behave as the G-buffer scenarios assume: {rows["formats"]} / {rows["blind-gbuffer"]}')
    names = list(SCENARIOS) + list(CONTRACTS)
    expected = [rows[name] if name in rows else CONTRACTS[name] for name in names]

    def render(selected, gpu):
        return PROGRAM_TEXT + ''.join(f'    IO.print(run(J.Frame.init_window({size(name)}, {size(name)}), {index}, "{name}"))\n' for index, name in selected)

    lanes = probe.candidates(render, list(enumerate(names)), batch=32, parse=lambda text, selected: [line.rstrip() for line in text.splitlines() if line.strip()])
    probe.compare(expected, lanes, describe=lambda index: names[index])
    probe.finish(scenarios=len(SCENARIOS), contracts=len(CONTRACTS))


PROGRAM_TEXT = PROGRAM


if __name__ == '__main__':
    main()
