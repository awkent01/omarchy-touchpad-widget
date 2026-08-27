// Touchpad state helpers.

// Parse hyprctl getoption JSON for a boolean option.
function parseBool(json) {
  try {
    var obj = JSON.parse(json)
    return !!obj.bool
  } catch (e) {
    return false
  }
}

// Parse hyprctl getoption JSON for a float option.
function parseFloat(json) {
  try {
    var obj = JSON.parse(json)
    return Number(obj.float) || 0
  } catch (e) {
    return 0
  }
}

// Parse hyprctl devices JSON and return the touchpad device name.
function parseTouchpadDevice(json) {
  try {
    var obj = JSON.parse(json)
    var mice = obj.mice || []
    for (var i = 0; i < mice.length; i++) {
      var name = String(mice[i].name || "").toLowerCase()
      if (name.indexOf("touchpad") !== -1 || name.indexOf("trackpad") !== -1)
        return mice[i].name
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

if (typeof module !== "undefined") {
  module.exports = {
    parseBool: parseBool,
    parseFloat: parseFloat,
    parseTouchpadDevice: parseTouchpadDevice,
    clampScrollFactor: clampScrollFactor,
    scrollSpeedLabel: scrollSpeedLabel
  }
}
