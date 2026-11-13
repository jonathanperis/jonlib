# Documentation index

Every page under `docs/`, grouped by area. New to the project? Read the
[README](../README.md), then [ARCHITECTURE.md](ARCHITECTURE.md), then the
[roadmap](ROADMAP.md). `tools/check_project.py` fails when a page is missing
from this index.

## Start here

What Jonlib is, how it is organized and where it stands.

- [ARCHITECTURE.md](ARCHITECTURE.md): Architecture
- [ROADMAP.md](ROADMAP.md): Roadmap
- [PROGRESS.md](PROGRESS.md): API progression dashboard
- [API.md](API.md): Public API
- [MODULES.md](MODULES.md): Jon* module names and imports
- [COMPATIBILITY.md](COMPATIBILITY.md): Compatibility ledger

## Verification and process

How parity is established, tracked and run.

- [VERIFICATION.md](VERIFICATION.md): Verification
- [API-TRACKING.md](API-TRACKING.md): API inventory and progression policy
- [CI.md](CI.md): Continuous integration
- [EXAMPLES.md](EXAMPLES.md): raylib examples as Bend ports
- [MACOS-VALIDATION.md](MACOS-VALIDATION.md): macOS validation
- [METAL-INVESTIGATION.md](METAL-INVESTIGATION.md): Metal dispatch failure and the declared compiler overlay
- [METAL-WITNESSES.md](METAL-WITNESSES.md): Forced-Metal witnesses
- [PERFORMANCE.md](PERFORMANCE.md): Performance

## Core: window, input, frames and drawing

- [DRIVER.md](DRIVER.md): Desktop driver and examples
- [INPUT.md](INPUT.md): Input, automation events, gestures and timing
- [FRAME.md](FRAME.md): Headless frame and shapes
- [RLGL.md](RLGL.md): rlgl immediate mode and the remaining shapes
- [TEXTURES.md](TEXTURES.md): 2D camera, render state, render textures and textures
- [PERSPECTIVE.md](PERSPECTIVE.md): Perspective projection
- [CAMERA.md](CAMERA.md): Cameras
- [SHADERS.md](SHADERS.md): Shaders
- [VR.md](VR.md): VR stereo
- [LOGGING.md](LOGGING.md): Logging and memory
- [FILES.md](FILES.md): Files and paths

## Images

The `Surface` type, pixel formats and image operations.

- [FORMATS.md](FORMATS.md): Pixel formats, raw image data and `ImageFormat`
- [PIXELS.md](PIXELS.md): Pixel sizing, raw access and dithering
- [FLOAT-FORMATS.md](FLOAT-FORMATS.md): Float and half-float formats
- [FLOAT-RGB.md](FLOAT-RGB.md): RGB float images
- [R32.md](R32.md): Bounded R32 image storage
- [IMAGE-COLORS.md](IMAGE-COLORS.md): Bulk and point image colors
- [IMAGE-CHANNELS.md](IMAGE-CHANNELS.md): Grayscale channel extraction
- [PALETTES.md](PALETTES.md): Text-byte images, grayscale and palettes
- [RESAMPLING.md](RESAMPLING.md): Cropping and resampling
- [MIPMAPS.md](MIPMAPS.md): Mipmaps
- [BLUR.md](BLUR.md): RGBA8 Gaussian blur
- [CONVOLUTION.md](CONVOLUTION.md): RGBA8 kernel convolution
- [GRADIENTS.md](GRADIENTS.md): Gradient profiles and parallel generation
- [CELLULAR.md](CELLULAR.md): Cellular generation
- [PERLIN.md](PERLIN.md): Perlin image profiles
- [ROTATION.md](ROTATION.md): Rotation and power-of-two profiles

## Image files and codecs

- [CODECS.md](CODECS.md): Image codecs
- [IMAGE-FILES.md](IMAGE-FILES.md): Image memory and file loading
- [IMAGE-EXPORT.md](IMAGE-EXPORT.md): Image export
- [IMAGE-CODE.md](IMAGE-CODE.md): Image-as-code export
- [RAW-FILES.md](RAW-FILES.md): Raw image files
- [PNG.md](PNG.md): PNG decoding
- [JPEG.md](JPEG.md): JPEG
- [BMP.md](BMP.md): BMP memory/file decoding and checked image export
- [TGA.md](TGA.md): TGA decoding and default RLE export
- [PNM.md](PNM.md): Binary PGM/PPM decoding
- [PIC.md](PIC.md): Softimage PIC decoding
- [PSD.md](PSD.md): PSD memory decoding and alpha profiles
- [HDR.md](HDR.md): Owned Radiance RGBE float images
- [GIF.md](GIF.md): First-frame GIF decoding
- [GIF-ANIMATION.md](GIF-ANIMATION.md): Bounded owned image animations
- [GIF-ENCODER.md](GIF-ENCODER.md): GIF recording (msf_gif)

## Data utilities

- [DEFLATE.md](DEFLATE.md): Bounded raw DEFLATE decompression
- [COMPRESSION.md](COMPRESSION.md): Native raw compression
- [BASE64.md](BASE64.md): Native Base64 utilities
- [CHECKSUMS.md](CHECKSUMS.md): Native checksum values
- [SHA.md](SHA.md): Native SHA-1 and SHA-256 values

## Text and fonts

- [FONTS.md](FONTS.md): Fonts and text drawing
- [TEXT.md](TEXT.md): Text and codepoints

## 3D models

- [MODELS.md](MODELS.md): Models: meshes, materials, BeginMode3D, 3D shapes and model files

## Audio

- [AUDIO.md](AUDIO.md): Audio waves and sounds

## Jonmath

raymath, numerical profiles and the float kernels behind them.

- [MATH.md](MATH.md): Jonmath profiles
- [ANGLES.md](ANGLES.md): Angle profiles and checked angle APIs
- [INVERSE-TRIG.md](INVERSE-TRIG.md): Inverse trigonometry profiles
- [MODERN-ANGLE.md](MODERN-ANGLE.md): Private glibc 2.41 atan2f kernel
- [MODERN-ANGLE-BOUNDS.md](MODERN-ANGLE-BOUNDS.md): Pinned atan2f arithmetic-domain derivation
- [SINCOSF.md](SINCOSF.md): glibc sinf/cosf profile
- [NATIVE-MATH-PROFILES.md](NATIVE-MATH-PROFILES.md): Native math profiles
- [BINARY64.md](BINARY64.md): Private binary64 emulation
- [COLLISION.md](COLLISION.md): Collision query profiles
- [SPLINES.md](SPLINES.md): Spline point profiles
- [RANDOM.md](RANDOM.md): Owned random streams

## Companion modules

- [GUI.md](GUI.md): Jongui: raygui controls
- [EASINGS.md](EASINGS.md): Joneasings: reasings.h
- [LIGHTS.md](LIGHTS.md): Jonlights: rlights.h

## Generated pages

[PROGRESS.md](PROGRESS.md) and the per-header checklists in [`api/`](api/) are
generated by `python3 tools/api_plan.py build` from
[`api/progress.json`](../api/progress.json); do not edit them by hand.
[docs/api/raylib.md](api/raylib.md), [raymath](api/raymath.md),
[rlgl](api/rlgl.md), [rcamera](api/rcamera.md), [rgestures](api/rgestures.md),
[configuration](api/config.md).
