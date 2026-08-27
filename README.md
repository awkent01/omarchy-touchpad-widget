# Touchpad — Omarchy bar widget

A bar widget for [Omarchy](https://omarchy.org)'s Quickshell bar that puts the
common Hyprland touchpad settings behind a single click.

![kind: bar-widget](https://img.shields.io/badge/kind-bar--widget-blue)
![category: Input](https://img.shields.io/badge/category-Input-lightgrey)

![The panel, enabled and disabled](docs/panel-states.png)

Enabled and disabled. The hero line cycles a phrase every 2.8s; the whole panel
takes its colors from your active Omarchy theme, so yours will not be red unless
you are also running a red one.

In the bar, between the speaker and the display widgets:

![The widget in the bar](docs/bar-widget.png)

## Features

- **Enable / disable** the touchpad
- **Scroll speed** slider (0.1–2.0) with named tiers, adjustable by scroll wheel or drag
- **Pointer speed** slider (−1.0–+1.0), scoped to the touchpad alone
- **Natural scrolling** toggle
- **Tap to click** toggle
- **Disable while typing** toggle
- **Clickfinger behavior** toggle
- Full keyboard cursor navigation across every control
- IPC handlers (`open` / `close` / `toggle` / `show` / `hide`) for keybinds
- Rotating hero status phrases, in the style of the built-in panels

## Status phrases

Like Omarchy's built-in network, bluetooth, and power panels, the hero status
line cycles a phrase every 2.8s while the panel is open, cross-faded rather
than hard-cut. Which set rotates depends on the pad:

| State | Phrases |
| --- | --- |
| Enabled | Tracking fingers, Counting taps, Reading swipes, Sensing capacitance, Herding pixels, Chasing gestures, Smoothing jitter, Polling deltas, Feeling around |
| Disabled | Keyboardpunk, Palms rejected, Homerow purist, Hjkl forever, Sensor napping, Ignoring thumbs, Refusing swipes, Gone tactile |
| No device | `NO DEVICE` (static) |

Edit `enabledPhrases` / `disabledPhrases` near the top of `Panel.qml` to make
them your own.

The scroll speed slider is labeled the same way in spirit, but keyed to the
value rather than a timer -- it updates live as you drag, alongside the number:

| Factor | Label |
| --- | --- |
| 0.1 – 0.2 | Glacial |
| 0.3 – 0.4 | Decaf |
| 0.5 – 0.6 | Cruising |
| 0.7 – 1.0 | Caffeinated |
| 1.1 – 1.5 | Overclocked |
| 1.6 – 2.0 | Ludicrous |

Omarchy's default is `0.4`. Change the tiers in `scrollSpeedLabel()` in `Model.js`.

## Settings persistence

`hyprctl eval` only changes the *running* compositor, and Omarchy's default
`hypr/input.lua` hardcodes `natural_scroll = false` — so the next config reload
(theme switch, saving any `hypr/*.lua`, `hyprctl reload`) would wipe out any
runtime change.

To survive that, every change is also mirrored to:

```
~/.local/state/omarchy/toggles/hypr/touchpad-settings.lua
```

Omarchy's `default/hypr/toggles.lua` re-requires that directory on each reload,
*after* `hypr/input.lua`, so these settings win. Only booleans and a clamped
number are ever written into the generated Lua — no device names or other
outside strings are interpolated.

Edit the widget, not that file; it is regenerated on every change.

## Pointer speed is per-device on purpose

Hyprland has no `input:touchpad:sensitivity`. The only global knob is
`input:sensitivity`, which would drag the trackpoint and any plugged-in mouse
along with the touchpad -- wrong for a widget named Touchpad. So sensitivity is
applied to the touchpad device by name:

```lua
hl.device({ name = "<touchpad>", sensitivity = 0.4 })
```

Two consequences:

- **It cannot be read back.** `hyprctl getoption device:<name>:sensitivity`
  answers `no such option`, and `hyprctl devices` reports only `defaultSpeed`.
  The value last written to
  `~/.local/state/omarchy/toggles/hypr/touchpad-sensitivity-value` is the only
  source of truth the slider has.
- **The device name is data, never code.** Names come from USB descriptors.
  They are written to a sibling `-name` file and read back by the generated
  Lua at reload time; nothing interpolates a name into generated Lua or into a
  QML string. The escaping and validation for the one `hyprctl eval` that does
  need the name live in the `touchpad-sensitivity` script, where they can be
  tested directly. Omarchy carries a migration (`1787618700.sh`) for exactly
  this class of bug, so the plugin follows the same rule.

`hyprctl keyword` is not an option here -- Omarchy uses the Lua config parser,
which answers `keyword can't work with non-legacy parsers. Use eval.`

## Enabling is not symmetric with disabling

Disabling is immediate: `hl.device({ enabled = false })` detaches the device
right away. Enabling is not -- setting `enabled = true` updates the config
value but does not re-attach a device the compositor has already detached, so
the pad stays dead until the next config reload.

So the enable path chains a reload, ordered *after*
`omarchy-toggle-input-device` clears its `touchpad-disabled-name` marker.
Reloading first would just let `disabled-input-device.lua` read the marker
back and re-disable the device.

This also means the marker file is not a trustworthy source of truth for the
UI: `omarchy-toggle-input-device on` removes it *before* it applies anything,
so a failed enable leaves the marker gone and the pad dead. The panel re-reads
real state shortly after any toggle rather than trusting its optimistic flip.

## Install

```bash
git clone https://github.com/awkent01/omarchy-touchpad-widget.git \
  ~/.config/omarchy/plugins/awkent01.touchpad
```

Then add the widget to your bar from Omarchy's bar settings and reload the shell.

## Files

| File | Purpose |
| --- | --- |
| `manifest.json` | Plugin manifest (schema v1, `bar-widget` kind) |
| `Panel.qml` | The widget UI, state polling, IPC, and persistence |
| `Model.js` | Pure helpers: `hyprctl` JSON parsing, clamping, speed labels |
| `touchpad-sensitivity` | Applies + persists per-device pointer sensitivity |

## Requirements

- Omarchy with the Quickshell bar
- Hyprland (`hyprctl` on `PATH`)

## Development

Saving a file under `~/.config/omarchy/plugins/` hot-reloads the plugin, and
the journal will say so:

```bash
journalctl --user -f | grep touchpad   # "Local plugin changed, reloading: ..."
```

That log line means the *file* was picked up -- it does not mean the running
widget was rebuilt. Edits to bindings and values apply live, but structural
changes (adding root properties, new `id`s, new Timer/Animation elements) leave
the already-instantiated widget on the old component. The panel keeps rendering
the old text with no QML error to warn you. When that happens:

```bash
omarchy restart shell
```

Note that `omarchy-shell shell rescanPlugins` tears the plugin down and rebuilds
it, so an IPC call fired immediately after returns `Target not found` until it
re-registers. Retry a moment later.

Useful checks:

```bash
omarchy-shell awkent01.touchpad open      # open the panel without clicking
hyprctl layers | grep keyboard-panel      # confirm the panel surface exists
grim -o eDP-1 /tmp/panel.png              # look at what actually rendered
```

## License

MIT
