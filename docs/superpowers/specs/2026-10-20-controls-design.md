# Controls: Gamepad, Keyboard, Mouse and Two-Handed Touch Design

Date: 2026-10-20
Status: Approved in conversation

## Purpose

Today the ship has one control scheme: a finger (or a mouse click) sets where the nose points, and holding it fires the engine once the nose is aligned. The developer asked for:

- gamepad support: the left stick steers and A fires; a second layout steers with the right stick and fires with D-pad up;
- customisable bindings for gamepad, keyboard and mouse (the mouse should aim without a click, with a separate fire input);
- two two-handed touch modes: a virtual joystick with a fire button, and a finger that aims with a separate fire button;
- a free choice of which side of the screen holds which touch control.

## Decisions

| Topic | Decision |
|---|---|
| Steering model | **Point to heading** for every stick and key scheme: the input direction is where the nose should point. The ship turns there at `Tuning.turn_rate`. With no input, the heading holds. |
| Fire button | In every scheme with a separate fire input, the engine fires on press, with no alignment gate. One-finger touch keeps today's gate (`Tuning.align_degrees`). |
| Keyboard | Two ways at once: 8-direction steering keys (default WASD and arrows), and mouse aim with a key or mouse button to fire. |
| Mouse | The nose follows the cursor with no click; a rebindable button fires (default: left click). A setting restores today's click-to-aim-and-fire. |
| Gamepad presets | A: left stick steers, A fires. B: right stick steers, D-pad up fires. Every binding can be changed. |
| Devices | Gamepad, keyboard, mouse and touch all stay live; the last device used drives the ship. |
| Virtual joystick | Floating: it appears where the thumb lands on its half of the screen and centres there. |
| Finger + button | The finger aims anywhere on screen except a round fire button in a bottom corner. |
| Sides | The player chooses which side holds the fire button; the other control takes the other side. |
| Default touch mode | One finger, as today. |
| Menus | Fully usable with a gamepad or keyboard: focus navigation, A/Enter selects, B/Esc goes back. |
| Training rings | In any scheme other than one-finger touch, a ring counts as held while the steering points within 30° of it and fire is held. |
| Demos and server | Unchanged. Demos record ship state, not input, so recordings and server checks do not depend on the control scheme. |

## Ship

`scenes/ship.gd` keeps its physics and gains two fields:

- `steering: bool`: turn toward `aim_point` without firing.
- `align_gate: bool`: fire only once the nose is within `Tuning.align_degrees` of `aim_point`. Defaults to `true`.

In `_integrate_forces` the ship turns while `steering or thrusting`. The pressed-and-aligned latch (`_press_aligned`) applies only when `align_gate` is true; otherwise `firing = boosting or (thrusting and fuel > 0.0)`. The ship's `_unhandled_input` moves to the input layer. `accept_input` stays on the ship and the input layer honours it.

## Input layer

`scenes/ship_input.gd` (`class_name ShipInput extends Node`) is created by `Level` beside the ship. It reads `Settings`, turns events into the ship's `aim_point`, `steering`, `thrusting` and `align_gate`, and draws the virtual touch controls on a `CanvasLayer` above the HUD.

### Actions

`project.godot` declares the actions with the defaults below. At startup, `Settings` replaces their events with any saved bindings.

| Action | Keyboard | Mouse | Gamepad A | Gamepad B |
|---|---|---|---|---|
| `steer_left` | A, Left | | Left stick −X | Right stick −X |
| `steer_right` | D, Right | | Left stick +X | Right stick +X |
| `steer_up` | W, Up | | Left stick −Y | Right stick −Y |
| `steer_down` | S, Down | | Left stick +Y | Right stick +Y |
| `fire` | Space | Left button | A (button 0) | D-pad up |
| `pause` | Esc | | Start | Start |

Choosing a gamepad preset rewrites only the gamepad events of these actions. Keyboard and mouse bindings stay as they are.

### Schemes

The last device to send an event chooses the scheme. GUI controls consume their own events first, as today.

- **Stick or keys.** `dir = Input.get_vector("steer_left", "steer_right", "steer_up", "steer_down")`. When `dir` is non-zero, `steering = true` and `aim_point = ship.global_position + dir.normalized() * 1000.0`. When `dir` is zero, `steering = false` and the heading holds. `thrusting = Input.is_action_pressed("fire")`, `align_gate = false`.
- **Mouse aims** (real mouse: `event.device != InputEvent.DEVICE_ID_EMULATION`; `Settings.mouse_aims` true). Motion sets `steering = true` and `aim_point` to the cursor in world space, re-projected every physics step as touch is today. `fire` sets `thrusting`, `align_gate = false`.
- **Mouse clicks** (`Settings.mouse_aims` false). Today's behaviour: a left press aims and fires, with the gate.
- **Touch, one finger.** Today's behaviour, with the gate.
- **Touch, virtual stick + button.** A touch that starts on the stick's half of the screen anchors a floating stick at that point. The offset from the anchor, clamped to the stick radius and with a deadzone of 15% of the radius, gives `dir` exactly as for a physical stick. A touch on the button half holds `thrusting`. Each touch is tracked by `event.index`, so both thumbs work at once.
- **Touch, finger + button.** A round fire button sits in the bottom corner of the chosen side. A touch on it holds `thrusting`. Any other touch aims: `steering = true` and `aim_point` follows the finger. `align_gate = false`.

Touch schemes use `InputEventScreenTouch` and `InputEventScreenDrag` for multi-touch. One-finger touch keeps using the emulated mouse events, as today.

### Pause

`pause` in a level pauses the tree and opens a card with Resume, Restart and Menu. It reuses the HUD's existing `retry_requested` and `menu_requested` signals. The Android back button keeps its current behaviour.

## Settings and the Controls screen

`scripts/settings.gd` gains:

| Field | Values | Default |
|---|---|---|
| `touch_scheme` | `"finger"`, `"stick"`, `"finger_button"` | `"finger"` |
| `fire_side` | `"left"`, `"right"` | `"right"` |
| `mouse_aims` | bool | `true` |
| `pad_preset` | `"a"`, `"b"` | `"a"` |
| bindings | action → `Array[InputEvent]` | the `project.godot` defaults |

These fields are saved in `settings.cfg` under `[input]`. `ConfigFile` stores `InputEvent` resources as text, the same format `project.godot` uses. A missing or unreadable section keeps the defaults. Applying bindings rewrites `InputMap` with `action_erase_events` and then `action_add_event`.

The Settings overlay in `main.gd` gains a **Controls** button. It opens an `Overlay` with:

1. touch scheme (three options) and fire side (left/right), with a small diagram of the chosen layout;
2. the mouse mode toggle;
3. gamepad preset A/B;
4. one row per action listing its current events, with **Change** (the next key, mouse button or gamepad button replaces the binding of that device type; Esc cancels) and **Add** (appends one);
5. **Reset to defaults**.

Gamepad stick axes are chosen through the preset and are not captured as single events.

## Menus

Every screen grabs focus on its first button when it opens: the main menu, training list, overlays, the HUD result card, the pause card, tours, tutorial captions, the My Levels screen and the demo viewer. Godot's built-in `ui_up`/`ui_down`/`ui_left`/`ui_right`/`ui_accept` then work with the D-pad, left stick and keyboard. `ui_cancel` (B, Esc) closes the top overlay, or goes back where the Android back button does today. The level editor stays touch- and mouse-only.

## Training

`Tutorial` asks `ShipInput` for the active scheme. In one-finger touch, rings work as today. In every other scheme:

- the ring counts as held while the steering direction is within 30° of the direction from the ship to the ring centre, and `fire` is held;
- while held, `aim_point` is set to the ring as now, so the ship flies toward it;
- captions that say "touch" use scheme-specific wording, for example "Point at the ring and hold fire" instead of "Touch and hold the ring".

A `wait` ring still freezes the ship until it is first held.

## Testing

Tests follow the existing `tests/test_*.gd` style and drive `ShipInput` with synthetic events:

- each scheme turns its events into the expected `aim_point`, `steering`, `thrusting` and `align_gate`;
- with `align_gate` false, the engine fires on the first tick while the nose is still turning; with it true, it waits as today;
- the virtual stick: anchoring, deadzone, clamping, and two simultaneous touches;
- the ring-held rule at 29° and 31°, with and without fire;
- bindings and settings survive a save/load round trip, and a corrupt `[input]` section falls back to the defaults.

The desktop smoke run covers keyboard, mouse aim and menu focus. A physical gamepad and an Android device are needed to check the pad presets and the two-handed touch modes.

## Out of scope

- Size or opacity settings for virtual controls.
- Rotate-left/right steering.
- Per-controller presets beyond A and B.
- Gamepad or keyboard control of the level editor.
