# Touchpad — Omarchy bar widget

A bar widget for [Omarchy](https://omarchy.org)'s Quickshell bar that puts the
common Hyprland touchpad settings behind a single click.

![kind: bar-widget](https://img.shields.io/badge/kind-bar--widget-blue)
![category: Input](https://img.shields.io/badge/category-Input-lightgrey)

## Features

- **Enable / disable** the touchpad
- **Scroll speed** slider (0.1–2.0) with named tiers, adjustable by scroll wheel or drag
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

## Requirements

- Omarchy with the Quickshell bar
- Hyprland (`hyprctl` on `PATH`)

## License

MIT
