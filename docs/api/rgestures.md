# rgestures.h: complete API/support checklist

[Progress dashboard](../PROGRESS.md)

Generated from the pinned source; proposed Bend names are planning targets, not existing functions.
Each row inherits its milestone verification recipe and the six completion gates in the machine-readable ledger.

| Stable ID / source | Kind | Reference contract | Bend mapping | Status | Step |
|---|---|---|---|---|---|
| [`rgestures:macro:RGESTURES_H`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L44) | macro | `#define RGESTURES_H` | `import ./jonlib.bend` (implemented) | partial | `configuration` |
| [`rgestures:macro:PI`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L47) | macro | `#define PI 3.14159265358979323846` | `Math.PI` (implemented) | partial | `numerics` |
| [`rgestures:macro:MAX_TOUCH_POINTS`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L54) | macro | `#define MAX_TOUCH_POINTS 8` | `Config.MAX_TOUCH_POINTS` (implemented) | partial | `configuration` |
| [`rgestures:enum:bool`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L66) | enum | `bool — false = 0; true = !false` | `Bool` (implemented) | partial | `types` |
| [`rgestures:enumerator:false`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L66) | enumerator | `false = 0` | `False{}` (implemented) | partial | `types` |
| [`rgestures:enumerator:true`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L66) | enumerator | `true = !false` | `True{}` (implemented) | partial | `types` |
| [`rgestures:macro:RL_BOOL_TYPE`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L67) | macro | `#define RL_BOOL_TYPE` | `Config.RL_BOOL_TYPE` (proposed) | not-started | `configuration` |
| [`rgestures:switch:RL_VECTOR2_TYPE`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L71) | switch | `#if !defined(RL_VECTOR2_TYPE)` | `M.Vector2` (implemented) | partial | `configuration` |
| [`rgestures:type:Vector2`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L73) | type | `Vector2 — float x; float y` | `jonmath.Vector2` (implemented) | partial | `types` |
| [`rgestures:switch:RGESTURES_STANDALONE`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L79) | switch | `#if defined(RGESTURES_STANDALONE)` | `import ./jonlib.bend` (implemented) | partial | `configuration` |
| [`rgestures:enum:Gesture`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L82) | enum | `Gesture — GESTURE_NONE        = 0; GESTURE_TAP         = 1; GESTURE_DOUBLETAP   = 2; GESTURE_HOLD        = 4; GESTURE_DRAG        = 8; GESTURE_SWIPE_RIGHT = 16; GESTURE_SWIPE_LEFT  = 32; GESTURE_SWIPE_UP    = 64; GESTURE_SWIPE_DOWN  = 128; GESTURE_PINCH_IN    = 256; GESTURE_PINCH_OUT   = 512` | `U32 constants Gesture.*` (implemented) | partial | `types` |
| [`rgestures:enumerator:GESTURE_NONE`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L83) | enumerator | `GESTURE_NONE = 0` | `Gesture.GESTURE_NONE` (implemented) | partial | `types` |
| [`rgestures:enumerator:GESTURE_TAP`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L84) | enumerator | `GESTURE_TAP = 1` | `Gesture.GESTURE_TAP` (implemented) | partial | `types` |
| [`rgestures:enumerator:GESTURE_DOUBLETAP`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L85) | enumerator | `GESTURE_DOUBLETAP = 2` | `Gesture.GESTURE_DOUBLETAP` (implemented) | partial | `types` |
| [`rgestures:enumerator:GESTURE_HOLD`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L86) | enumerator | `GESTURE_HOLD = 4` | `Gesture.GESTURE_HOLD` (implemented) | partial | `types` |
| [`rgestures:enumerator:GESTURE_DRAG`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L87) | enumerator | `GESTURE_DRAG = 8` | `Gesture.GESTURE_DRAG` (implemented) | partial | `types` |
| [`rgestures:enumerator:GESTURE_SWIPE_RIGHT`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L88) | enumerator | `GESTURE_SWIPE_RIGHT = 16` | `Gesture.GESTURE_SWIPE_RIGHT` (implemented) | partial | `types` |
| [`rgestures:enumerator:GESTURE_SWIPE_LEFT`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L89) | enumerator | `GESTURE_SWIPE_LEFT = 32` | `Gesture.GESTURE_SWIPE_LEFT` (implemented) | partial | `types` |
| [`rgestures:enumerator:GESTURE_SWIPE_UP`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L90) | enumerator | `GESTURE_SWIPE_UP = 64` | `Gesture.GESTURE_SWIPE_UP` (implemented) | partial | `types` |
| [`rgestures:enumerator:GESTURE_SWIPE_DOWN`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L91) | enumerator | `GESTURE_SWIPE_DOWN = 128` | `Gesture.GESTURE_SWIPE_DOWN` (implemented) | partial | `types` |
| [`rgestures:enumerator:GESTURE_PINCH_IN`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L92) | enumerator | `GESTURE_PINCH_IN = 256` | `Gesture.GESTURE_PINCH_IN` (implemented) | partial | `types` |
| [`rgestures:enumerator:GESTURE_PINCH_OUT`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L93) | enumerator | `GESTURE_PINCH_OUT = 512` | `Gesture.GESTURE_PINCH_OUT` (implemented) | partial | `types` |
| [`rgestures:enum:TouchAction`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L97) | enum | `TouchAction — TOUCH_ACTION_UP = 0; TOUCH_ACTION_DOWN; TOUCH_ACTION_MOVE; TOUCH_ACTION_CANCEL` | `U32 constants TouchAction.*` (implemented) | partial | `types` |
| [`rgestures:enumerator:TOUCH_ACTION_UP`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L98) | enumerator | `TOUCH_ACTION_UP = 0` | `TouchAction.TOUCH_ACTION_UP` (implemented) | partial | `types` |
| [`rgestures:enumerator:TOUCH_ACTION_DOWN`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L99) | enumerator | `TOUCH_ACTION_DOWN` | `TouchAction.TOUCH_ACTION_DOWN` (implemented) | partial | `types` |
| [`rgestures:enumerator:TOUCH_ACTION_MOVE`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L100) | enumerator | `TOUCH_ACTION_MOVE` | `TouchAction.TOUCH_ACTION_MOVE` (implemented) | partial | `types` |
| [`rgestures:enumerator:TOUCH_ACTION_CANCEL`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L101) | enumerator | `TOUCH_ACTION_CANCEL` | `TouchAction.TOUCH_ACTION_CANCEL` (implemented) | partial | `types` |
| [`rgestures:type:GestureEvent`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L105) | type | `GestureEvent — int touchAction; int pointCount; int pointId[MAX_TOUCH_POINTS]; Vector2 position[MAX_TOUCH_POINTS]` | `GestureEvent` (implemented) | partial | `types` |
| [`rgestures:function:ProcessGestureEvent`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L125) | function | `void ProcessGestureEvent(GestureEvent event)` | `Gestures.process_event_for / Gestures.process_event` (implemented) | partial | `input` |
| [`rgestures:function:UpdateGestures`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L126) | function | `void UpdateGestures(void)` | `Gestures.update` (implemented) | partial | `input` |
| [`rgestures:function:SetGesturesEnabled`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L129) | function | `void SetGesturesEnabled(unsigned int flags)` | `Gestures.set_enabled` (implemented) | partial | `input` |
| [`rgestures:function:IsGestureDetected`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L130) | function | `bool IsGestureDetected(int gesture)` | `Gestures.is_detected` (implemented) | partial | `input` |
| [`rgestures:function:GetGestureDetected`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L131) | function | `int GetGestureDetected(void)` | `Gestures.get_detected` (implemented) | partial | `input` |
| [`rgestures:function:GetGestureHoldDuration`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L133) | function | `float GetGestureHoldDuration(void)` | `Gestures.get_hold_duration` (implemented) | partial | `input` |
| [`rgestures:function:GetGestureDragVector`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L134) | function | `Vector2 GetGestureDragVector(void)` | `Gestures.get_drag_vector` (implemented) | partial | `input` |
| [`rgestures:function:GetGestureDragAngle`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L135) | function | `float GetGestureDragAngle(void)` | `Gestures.get_drag_angle` (implemented) | partial | `input` |
| [`rgestures:function:GetGesturePinchVector`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L136) | function | `Vector2 GetGesturePinchVector(void)` | `Gestures.get_pinch_vector` (implemented) | partial | `input` |
| [`rgestures:function:GetGesturePinchAngle`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L137) | function | `float GetGesturePinchAngle(void)` | `Gestures.get_pinch_angle` (implemented) | partial | `input` |
| [`rgestures:switch:RGESTURES_IMPLEMENTATION`](https://github.com/raysan5/raylib/blob/02566453880e06bec97f5b8160fa6fe1e98397ca/src/rgestures.h#L152) | switch | `#if defined(RGESTURES_IMPLEMENTATION)` | `import ./jonlib.bend` (implemented) | partial | `configuration` |

## Language adaptations

C-to-Bend mappings with no behavior difference reachable through the API ([policy](../API-TRACKING.md#language-adaptations)). They are not gaps and do not complete an item.

- `rgestures:macro:RGESTURES_H`: An include guard has no Bend counterpart (language adaptation)
- `rgestures:macro:PI`: C preprocessor macros have no Bend counterpart (a zero-argument function)
- `rgestures:macro:MAX_TOUCH_POINTS`: C preprocessor macros have no Bend counterpart (a zero-argument function)
- `rgestures:enum:bool`: C int-compatible bool conversions
- `rgestures:enumerator:false`: C int-compatible bool conversions
- `rgestures:enumerator:true`: C int-compatible bool conversions
- `rgestures:switch:RL_VECTOR2_TYPE`: A type-definition guard has no Bend counterpart (language adaptation)
- `rgestures:switch:RGESTURES_STANDALONE`: A standalone build with private type copies is not separate (language adaptation)
- `rgestures:enum:Gesture`: C enum types and implicit int conversions have no Bend counterpart (U32 constants)
- `rgestures:enumerator:GESTURE_NONE`: C enum types and implicit int conversions have no Bend counterpart (U32 constants)
- `rgestures:enumerator:GESTURE_TAP`: C enum types and implicit int conversions have no Bend counterpart (U32 constants)
- `rgestures:enumerator:GESTURE_DOUBLETAP`: C enum types and implicit int conversions have no Bend counterpart (U32 constants)
- `rgestures:enumerator:GESTURE_HOLD`: C enum types and implicit int conversions have no Bend counterpart (U32 constants)
- `rgestures:enumerator:GESTURE_DRAG`: C enum types and implicit int conversions have no Bend counterpart (U32 constants)
- `rgestures:enumerator:GESTURE_SWIPE_RIGHT`: C enum types and implicit int conversions have no Bend counterpart (U32 constants)
- `rgestures:enumerator:GESTURE_SWIPE_LEFT`: C enum types and implicit int conversions have no Bend counterpart (U32 constants)
- `rgestures:enumerator:GESTURE_SWIPE_UP`: C enum types and implicit int conversions have no Bend counterpart (U32 constants)
- `rgestures:enumerator:GESTURE_SWIPE_DOWN`: C enum types and implicit int conversions have no Bend counterpart (U32 constants)
- `rgestures:enumerator:GESTURE_PINCH_IN`: C enum types and implicit int conversions have no Bend counterpart (U32 constants)
- `rgestures:enumerator:GESTURE_PINCH_OUT`: C enum types and implicit int conversions have no Bend counterpart (U32 constants)
- `rgestures:enum:TouchAction`: C enum types and implicit int conversions have no Bend counterpart (U32 constants)
- `rgestures:enumerator:TOUCH_ACTION_UP`: C enum types and implicit int conversions have no Bend counterpart (U32 constants)
- `rgestures:enumerator:TOUCH_ACTION_DOWN`: C enum types and implicit int conversions have no Bend counterpart (U32 constants)
- `rgestures:enumerator:TOUCH_ACTION_MOVE`: C enum types and implicit int conversions have no Bend counterpart (U32 constants)
- `rgestures:enumerator:TOUCH_ACTION_CANCEL`: C enum types and implicit int conversions have no Bend counterpart (U32 constants)
- `rgestures:switch:RGESTURES_IMPLEMENTATION`: A single-header implementation switch has no Bend counterpart (language adaptation)

Full conditional variants, source lines, type/API dependencies, evidence and next actions are retained in [`api/ledger.json`](../../api/ledger.json).
