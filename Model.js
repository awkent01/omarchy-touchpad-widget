// Touchpad state helpers.

// Ceilings on everything that arrives from outside this file. hyprctl output is
// already byte-capped at the producer (see stateProc in Panel.qml), and a device
// name comes from a USB descriptor, but nothing downstream should depend on that
// having happened -- a parser that will chew on an unbounded string is a parser
// that can be made to hang the shell.
var MAX_JSON_CHARS = 262144
var MAX_DEVICE_ENTRIES = 512
var MAX_DEVICE_NAME_CHARS = 128
var MAX_DEVICE_NAME_BYTES = 256

// Refuse rather than truncate: a truncated device name is a name that matches
// the wrong device, which is worse than not matching one at all.
function tooLarge(json) {
  return String(json || "").length > MAX_JSON_CHARS
}

// Parse hyprctl getoption JSON for a boolean option.
function parseBool(json) {
  if (tooLarge(json)) return false
  try {
    var obj = JSON.parse(json)
    return !!obj.bool
  } catch (e) {
    return false
  }
}

// Parse hyprctl getoption JSON for a float option.
function parseFloat(json) {
  if (tooLarge(json)) return 0
  try {
    var obj = JSON.parse(json)
    return Number(obj.float) || 0
  } catch (e) {
    return 0
  }
}

// Parse hyprctl devices JSON and return the touchpad device name.
//
// The list is capped and so is each name: this JSON is the one input here that
// an attacker with a USB port has a hand in, and the name it yields is used to
// address a device and is embedded in generated Lua. A name carrying control
// characters is rejected outright rather than escaped -- no real device needs
// one, and it keeps the value printable everywhere it lands.
function parseTouchpadDevice(json) {
  if (tooLarge(json)) return ""
  try {
    var obj = JSON.parse(json)
    var mice = obj.mice || []
    var limit = Math.min(mice.length, MAX_DEVICE_ENTRIES)
    for (var i = 0; i < limit; i++) {
      var raw = String(mice[i].name || "")
      if (raw.length === 0 || raw.length > MAX_DEVICE_NAME_CHARS) continue
      if (/[\x00-\x1f\x7f]/.test(raw)) continue
      var name = raw.toLowerCase()
      if (name.indexOf("touchpad") !== -1 || name.indexOf("trackpad") !== -1)
        return raw
    }
  } catch (e) {}
  return ""
}

// Clamp scroll factor to [0.1, 2.0] and round to 1 decimal.
function clampScrollFactor(value) {
  var v = Number(value) || 0.4
  if (v < 0.1) v = 0.1
  if (v > 2.0) v = 2.0
  return Math.round(v * 10) / 10
}

// Label for the current scroll speed. Rendered live beside the number while
// the slider is dragged, so unlike the hero phrases these are keyed to the
// value rather than rotated on a timer. Thresholds span the clamp range.
function scrollSpeedLabel(factor) {
  if (factor <= 0.2) return "Glacial"
  if (factor <= 0.4) return "Decaf"
  if (factor <= 0.6) return "Cruising"
  if (factor <= 1.0) return "Caffeinated"
  if (factor <= 1.5) return "Overclocked"
  return "Ludicrous"
}

// Clamp pointer sensitivity to Hyprland's [-1.0, 1.0] and round to 1 decimal.
// 0.0 is libinput's unaccelerated baseline, not a midpoint of "off" and "on".
function clampSensitivity(value) {
  var v = Number(value)
  if (!isFinite(v)) v = 0
  if (v < -1.0) v = -1.0
  if (v > 1.0) v = 1.0
  return Math.round(v * 10) / 10
}

// Label for pointer sensitivity. Centered on 0.0 = system default, so the
// scale reads outward in both directions rather than slow-to-fast.
function pointerSpeedLabel(sensitivity) {
  var v = clampSensitivity(sensitivity)
  if (v <= -0.7) return "Sedated"
  if (v <= -0.3) return "Unhurried"
  if (v < 0) return "Relaxed"
  if (v === 0) return "Stock"
  if (v < 0.4) return "Perky"
  if (v < 0.7) return "Twitchy"
  return "Caffeinated"
}

// Parse a single-line data file holding a sensitivity value. Returns null when
// the file is absent or unparseable so callers can fall back to the default
// rather than silently treating a missing value as 0.0.
function parseSensitivityFile(text) {
  var raw = String(text || "").trim()
  if (raw === "") return null
  var v = Number(raw)
  if (!isFinite(v)) return null
  return clampSensitivity(v)
}

if (typeof module !== "undefined") {
  module.exports = {
    parseBool: parseBool,
    parseFloat: parseFloat,
    parseTouchpadDevice: parseTouchpadDevice,
    clampScrollFactor: clampScrollFactor,
    clampSensitivity: clampSensitivity,
    pointerSpeedLabel: pointerSpeedLabel,
    parseSensitivityFile: parseSensitivityFile,
    scrollSpeedLabel: scrollSpeedLabel
  }
}
