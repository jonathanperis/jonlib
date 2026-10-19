# raylib [shaders] example - lightmap rendering, ported to Jonlib.
# Adapted from raylib 6.2 examples/shaders/shaders_lightmap_rendering.c
# (zlib/libpng, Copyright (c) 2019-2025 Jussi Viitala (@nullstare) and Ramon
# Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A 16x16 plane with the cubicmap atlas and a second set of texture
# coordinates for a lightmap, which three tinted sparks drawn into a 16x16
# render texture make, under an orbital camera. On the software renderer
# shaders, vertex buffers and blend modes do not exist (docs/SHADERS.md,
# docs/RLGL.md): rlLoadVertexBuffer answers 0, the lightmap shader is id 0 and
# the plane shows the atlas alone, with the lightmap drawn beside it, which
# is what the reference draws too. The perspective needs the libm profile's
# binary64 tan (docs/PERSPECTIVE.md); a refused UpdateCamera refuses the
# frame and every later one. LoadTexture of a .png is the PNG loader
# (Surface.load_png). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# textures: the atlas (the plane's albedo); light: the spark, kept loaded.
type State is Type:
  State{camera: +Maybe<J.Camera3D>, mesh: J.Mesh, material: J.Material, textures: List<J.Texture>, light: List<J.Texture>, lightmap: Maybe<J.RenderTexture>, shader: J.Shader}

def start() -> J.Camera3D:
  J.Camera3D{M.Vector3{4.0, 6.0, 8.0}, M.Vector3{0.0, 0.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, J.CameraProjection.CAMERA_PERSPECTIVE()}

def kept(updated: Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match updated:
    case None{}: None{}
    case Some{+c}: Some{c}

def update.camera(+libm: M.Libm, +core: J.Core, camera: +Maybe<J.Camera3D>) -> +Maybe<J.Camera3D>:
  match camera:
    case None{}: None{}
    case Some{+c}: kept(J.Camera.update_for(M.Uncontracted{}, libm, core, c, J.CameraMode.CAMERA_ORBITAL()))

def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{+camera, +mesh, +material, textures, light, lightmap, +shader} = state
  (core, State{update.camera(libm, core, camera), mesh, material, textures, light, lightmap, shader})

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps(result: Maybe<(J.Core & U32)>, state: State, frame: J.Frame, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.label(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 670.0, 148.0, 10.0, J.Color.GREEN())

# The lightmap beside the scene, its size and the frame rate.
def draw.shown(r: J.Frame & J.Texture, +id: U32, +depth: U32, +core: J.Core, +camera: J.Camera3D, +mesh: J.Mesh, +material: J.Material, textures: List<J.Texture>, light: List<J.Texture>, +shader: J.Shader) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  draw.fps(J.Core.get_fps(core, J.Core.get_time(core)), State{Some{camera}, mesh, material, textures, light, Some{J.RenderTexture{id, texture, depth}}, shader},
    draw.label(J.Text.format("LIGHTMAP: %ix%i pixels", [J.TextInt{16}, J.TextInt{16}]), frame), core)

# DrawTexturePro(lightmap.texture, (0, 0, -MAP_SIZE, -MAP_SIZE), (GetRenderWidth() - MAP_SIZE*8 - 10, 10, MAP_SIZE*8, MAP_SIZE*8), (0, 0), 0, WHITE).
def draw.lightmap(lightmap: Maybe<J.RenderTexture>, frame: J.Frame, +core: J.Core, +camera: J.Camera3D, +mesh: J.Mesh, +material: J.Material, textures: List<J.Texture>, light: List<J.Texture>, +shader: J.Shader) -> J.Core & (State & J.Frame):
  match lightmap:
    case None{}: (core, (State{Some{camera}, mesh, material, textures, light, None{}, shader}, J.Frame.refuse(frame)))
    case Some{J.RenderTexture{+id, texture, +depth}}:
      draw.shown(J.Draw.texture_pro(frame, texture, J.Rectangle{0.0, 0.0, F32.neg(16.0), F32.neg(16.0)}, J.Rectangle{662.0, 10.0, 128.0, 128.0}, M.Vector2{0.0, 0.0}, 0.0, J.Color.WHITE()),
        id, depth, core, camera, mesh, material, textures, light, shader)

def draw.scene(r: J.Frame & List<J.Texture>, lightmap: Maybe<J.RenderTexture>, +core: J.Core, +camera: J.Camera3D, +mesh: J.Mesh, +material: J.Material, light: List<J.Texture>, +shader: J.Shader) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  draw.lightmap(lightmap, J.Frame.end_mode_3d(frame), core, camera, mesh, material, textures, light, shader)

# DrawMesh(mesh, material, MatrixIdentity()) inside BeginMode3D.
def draw.at(camera: +Maybe<J.Camera3D>, +libm: M.Libm, +core: J.Core, +mesh: J.Mesh, +material: J.Material, textures: List<J.Texture>, light: List<J.Texture>, lightmap: Maybe<J.RenderTexture>, +shader: J.Shader, frame: J.Frame) -> J.Core & (State & J.Frame):
  match camera:
    case None{}: (core, (State{None{}, mesh, material, textures, light, lightmap, shader}, J.Frame.refuse(frame)))
    case Some{+c}: draw.scene(J.Draw.mesh(J.Frame.begin_mode_3d_for(libm, frame, c), textures, mesh, material, M.Matrix.identity()), lightmap, core, c, mesh, material, light, shader)

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+camera, +mesh, +material, textures, light, lightmap, +shader} = state
  draw.at(camera, libm, core, mesh, material, textures, light, lightmap, shader, J.Frame.clear_background(frame, J.Color.RAYWHITE()))

# The main loop's body; libm is the profile of UpdateCamera's sinf/cosf/atan2f and BeginMode3D's tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# GenMeshPlane(MAP_SIZE, MAP_SIZE, 1, 1) with mesh.texcoords2 = (0, 0), (1, 0), (0, 1), (1, 1).
def plane.mapped(mesh: J.Mesh) -> J.Mesh:
  J.Mesh{vertices, triangles, positions, texcoords, _, normals, tangents, colors, indices} = mesh
  J.Mesh{vertices, triangles, positions, texcoords, Some{[0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0]}, normals, tangents, colors, indices}

def plane(mesh: Maybe<J.Mesh>) -> J.Mesh:
  match mesh:
    case None{}: J.Mesh{0, 0, None{}, None{}, None{}, None{}, None{}, None{}, None{}}
    case Some{m}: plane.mapped(m)

# material.maps[MATERIAL_MAP_ALBEDO].texture = texture; material.maps[MATERIAL_MAP_METALNESS].texture = lightmap.texture.
def material.with(material: Maybe<J.Material>, +fallback: J.Material) -> J.Material:
  match material:
    case None{}: fallback
    case Some{m}: m

def material(+albedo: J.TextureInfo, +lightmap: J.TextureInfo) -> J.Material:
  +first = material.with(J.Material.set_texture(J.Material.load_default(), 0, albedo), J.Material.load_default())
  material.with(J.Material.set_texture(first, 1, lightmap), first)

# mesh.vboId[SHADER_LOC_VERTEX_TEXCOORD02] = rlLoadVertexBuffer(texcoords2, 8 floats, false), rlEnableVertexArray(mesh.vaoId),
# rlSetVertexAttribute(5, 2, RL_FLOAT, 0, 0, 0), rlEnableVertexAttribute(5), rlDisableVertexArray(): none has a body here.
def buffers.bound(r: J.Frame & Bool) -> J.Frame:
  (frame, _) = r
  J.Rlgl.disable_vertex_array(J.Rlgl.enable_vertex_attribute(J.Rlgl.set_vertex_attribute(frame, 5, 2, 5126, False{}, 0, 0), 5))

def buffers(r: J.Frame & U32) -> J.Frame:
  (frame, _) = r
  buffers.bound(J.Rlgl.enable_vertex_array(frame, 0))

def setup.done(+core: J.Core, frame: J.Frame, +material: J.Material, textures: List<J.Texture>, light: List<J.Texture>, lightmap: Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (buffers(J.Rlgl.load_vertex_buffer(frame, 32, False{})), State{Some{start()}, plane(J.Mesh.gen_plane(16.0, 16.0, 1, 1)), material, textures, light, lightmap,
    J.Shader.load(Some{"resources/shaders/glsl330/lightmap.vs"}, Some{"resources/shaders/glsl330/lightmap.fs"})}))

# GenTextureMipmaps(&lightmap.texture) and SetTextureFilter(lightmap.texture, TEXTURE_FILTER_TRILINEAR), then the material.
def setup.filtered(pair: J.Texture & J.TextureInfo, +id: U32, +depth: U32, +core: J.Core, frame: J.Frame, +albedo: J.TextureInfo, textures: List<J.Texture>, light: List<J.Texture>) -> J.Core & (J.Frame & State):
  (texture, +info) = pair
  setup.done(core, frame, material(albedo, info), textures, light, Some{J.RenderTexture{id, texture, depth}})

def setup.baked(r: J.Frame & Maybe<J.RenderTexture>, +core: J.Core, +albedo: J.TextureInfo, textures: List<J.Texture>, light: List<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, lightmap) = r
  match lightmap:
    case None{}: setup.done(core, frame, J.Material.load_default(), textures, light, None{})
    case Some{J.RenderTexture{+id, texture, +depth}}: setup.filtered(J.Texture.info(J.Texture.set_filter(J.Texture.gen_mipmaps(texture), 2)), id, depth, core, frame, albedo, textures, light)

def bake.end(r: J.Frame & J.Texture, +core: J.Core, +albedo: J.TextureInfo, textures: List<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, light) = r
  setup.baked(J.Frame.end_texture_mode(J.Frame.begin_blend_mode(frame, 0)), core, albedo, textures, [light])

# The third spark: (MAP_SIZE*0.8, MAP_SIZE*0.8, MAP_SIZE, MAP_SIZE) about its center, GREEN; BeginBlendMode(BLEND_ALPHA); EndTextureMode().
def bake.third(r: J.Frame & J.Texture, +w: F32, +h: F32, +core: J.Core, +albedo: J.TextureInfo, textures: List<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, light) = r
  bake.end(J.Draw.texture_pro(frame, light, J.Rectangle{0.0, 0.0, w, h}, J.Rectangle{(16.0 * 0.8 : F32), (16.0 * 0.8 : F32), 16.0, 16.0}, M.Vector2{8.0, 8.0}, 0.0, J.Color.GREEN()), core, albedo, textures)

# The second spark: (MAP_SIZE*0.8, MAP_SIZE/2, 2*MAP_SIZE, 2*MAP_SIZE) about (MAP_SIZE, MAP_SIZE), BLUE.
def bake.second(r: J.Frame & J.Texture, +w: F32, +h: F32, +core: J.Core, +albedo: J.TextureInfo, textures: List<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, light) = r
  bake.third(J.Draw.texture_pro(frame, light, J.Rectangle{0.0, 0.0, w, h}, J.Rectangle{(16.0 * 0.8 : F32), 8.0, 32.0, 32.0}, M.Vector2{16.0, 16.0}, 0.0, J.Color.BLUE()), w, h, core, albedo, textures)

# BeginTextureMode(lightmap): BLACK, BLEND_ADDITIVE (no blend modes here), the first spark over (0, 0, 2*MAP_SIZE, 2*MAP_SIZE) about (MAP_SIZE, MAP_SIZE), RED.
def bake.first(pair: J.Texture & J.TextureInfo, frame: J.Frame, target: J.RenderTexture, +core: J.Core, +albedo: J.TextureInfo, textures: List<J.Texture>) -> J.Core & (J.Frame & State):
  (light, +info) = pair
  J.TextureInfo{_, +w, +h, _, _} = info
  bake.second(J.Draw.texture_pro(J.Frame.begin_blend_mode(J.Frame.clear_background(J.Frame.begin_texture_mode(frame, target), J.Color.BLACK()), 1), light,
    J.Rectangle{0.0, 0.0, U32.to_f32(w), U32.to_f32(h)}, J.Rectangle{0.0, 0.0, 32.0, 32.0}, M.Vector2{16.0, 16.0}, 0.0, J.Color.RED()), U32.to_f32(w), U32.to_f32(h), core, albedo, textures)

def bake(r: J.Frame & Maybe<J.RenderTexture>, light: J.Texture, +core: J.Core, +albedo: J.TextureInfo, textures: List<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, target) = r
  match target:
    case None{}: setup.done(core, frame, J.Material.load_default(), textures, [light], None{})
    case Some{t}: bake.first(J.Texture.info(light), frame, t, core, albedo, textures)

# RenderTexture lightmap = LoadRenderTexture(MAP_SIZE, MAP_SIZE).
def setup.light(r: J.Frame & Maybe<J.Texture>, +core: J.Core, +albedo: J.TextureInfo, textures: List<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, light) = r
  match light:
    case None{}: setup.done(core, frame, J.Material.load_default(), textures, Nil{}, None{})
    case Some{t}: bake(J.RenderTexture.load(frame, 16, 16), t, core, albedo, textures)

def upload(frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: J.Texture.load_from_image(frame, image)

# Texture light = LoadTexture("resources/spark_flame.png").
def setup.atlas.info(pair: J.Texture & J.TextureInfo, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  (texture, +info) = pair
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/spark_flame.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.light(upload(frame, result), core, info, [texture])))

# GenTextureMipmaps(&texture) and SetTextureFilter(texture, TEXTURE_FILTER_TRILINEAR): one level, LINEAR.
def setup.atlas(r: J.Frame & Maybe<J.Texture>, +dir: String, +core: J.Core) -> IO(J.Core & (J.Frame & State)):
  (frame, atlas) = r
  match atlas:
    case None{}: IO.pure(J.Core & (J.Frame & State), setup.done(core, frame, J.Material.load_default(), Nil{}, Nil{}, None{}))
    case Some{t}: setup.atlas.info(J.Texture.info(J.Texture.set_filter(J.Texture.gen_mipmaps(t), 2)), dir, core, frame)

# SetConfigFlags(FLAG_MSAA_4X_HINT) before InitWindow: Desktop.run_flags.
# After InitWindow(800, 450): the plane and its second texture coordinates,
# the shader, the atlas and the spark textures, the baked lightmap and the
# material, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/cubicmap_atlas.png"),
    result => setup.atlas(upload(frame, result), dir, core))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run_flags(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, J.ConfigFlags.FLAG_MSAA_4X_HINT(), "raylib [shaders] example - lightmap rendering", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
