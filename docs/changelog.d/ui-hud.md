### ui-hud

- Input router (`InputRouter`): keyboard and controller actions from the project input map, rebinding saved to `input.cfg`, Backspace held 1 s and View+Menu panic straight to `EventBus.panic_requested`, the local rider's pedal gestures, and pedal-UI menu input (surge confirms, coast backs out outside ERG, stop for 5 s pauses solo).
- `PedalScanList`: single-switch scanning for menus, shops and pickers, with focus moves, disabled items and ERG auto-confirm after two scan cycles (`item_chosen(..., auto)` and `item_picked(..., via)`).
- HUD kit: power gauge with a target band that glows in band, cadence with its band, W' bar, phase timeline with next-phase preview, teammate strip with slot chips (color, shape, pattern, hollow), toasts, rescue, warm-up and pause banners, big readouts and the gear indicator; `HudLayer` places them at anchors or at art-pixel rects through the `PixelViewport` and follows the session bus.
- Shared Theme and `WlTheme` sizes and colors (Godot's default font until Atkinson Hyperlegible is added).
- `Sfx`: fifteen synthesized effects, game-registered clips, looping synth clips and a cadence metronome.
