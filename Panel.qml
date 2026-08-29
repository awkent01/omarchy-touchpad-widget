import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "awkent01.touchpad"
  ipcTarget: "awkent01.touchpad"
  manageIpc: false

  // ---- State ----
  property string deviceName: ""
  property bool touchpadEnabled: true
  property bool naturalScroll: false
  property bool tapToClick: true
  property bool disableWhileTyping: true
  property bool clickfingerBehavior: true
  property real scrollFactor: 0.4
  // Hyprland sensitivity is [-1.0, 1.0] with 0.0 as libinput's unaccelerated
  // baseline. There is no input:touchpad:sensitivity -- only the global
  // input:sensitivity, which would drag the trackpoint and any USB mouse along
  // with it -- so this is applied per-device to the touchpad alone.
  property real pointerSpeed: 0.0
  property real pendingPointerSpeed: 0.0

  // Pending scroll factor while dragging the slider.
  property real pendingScrollFactor: 0.4
  property bool scrollSetQueued: false

  // Carry sub-notch touchpad deltas between wheel events.
  property real wheelAccumulator: 0

  // ---- Cursor navigation ----
  // Sections: "header" (enable/disable toggle), "scroll" (scroll speed slider),
  // then toggle rows: "natural", "tap", "typing", "clickfinger"
  property string focusSection: "header"
  property int selectedIndex: 0
  property bool cursorActive: false

  readonly property var allSections: ["header", "scroll", "pointer", "natural", "tap", "typing", "clickfinger"]

  readonly property string icon: {
    if (!deviceName) return ""
    return touchpadEnabled ? "󰟸" : "󰤳"
  }

  // Agent-flavored phrases for the hero status line, rotated on a timer so the
  // panel feels alive -- the same trick the built-in network, bluetooth, and
  // power panels use. Two sets, picked by whether the pad is listening or not.
  readonly property var enabledPhrases: [
    "Tracking fingers",
    "Counting taps",
    "Reading swipes",
    "Sensing capacitance",
    "Herding pixels",
    "Chasing gestures",
    "Smoothing jitter",
    "Polling deltas",
    "Feeling around"
  ]
  readonly property var disabledPhrases: [
    "Keyboardpunk",
    "Palms rejected",
    "Homerow purist",
    "Hjkl forever",
    "Sensor napping",
    "Ignoring thumbs",
    "Refusing swipes",
    "Gone tactile"
  ]
  property int phraseIndex: 0

  // Whichever list is "active" given the current touchpad state. Empty when
  // there is no device, which is what parks the rotation on a static label.
  readonly property var activePhrases: {
    if (!deviceName) return []
    return touchpadEnabled ? enabledPhrases : disabledPhrases
  }
  readonly property bool rotatingPhrases: activePhrases.length > 0

  // Guard on the list itself rather than on deviceName. Bindings settle in
  // arbitrary order, so there is a tick where deviceName is already set but
  // activePhrases has not re-evaluated yet -- phraseIndex % 0 is NaN there,
  // and the lookup returns undefined, which QML refuses to assign to a string.
  readonly property string heroStatusText: {
    var list = activePhrases
    if (!list || list.length === 0) return "No device"
    return String(list[phraseIndex % list.length] || "No device")
  }

  readonly property color hoverFill: bar
    ? Style.hoverFillFor(bar.foreground, Color.accent)
    : "transparent"
  readonly property color selectedFill: bar
    ? Style.selectedFillFor(bar.foreground, Color.accent)
    : "transparent"

  function moveCursor(delta) {
    var sections = allSections
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) { focusSection = sections[0]; return }

    if (delta > 0) {
      if (sIdx < sections.length - 1) focusSection = sections[sIdx + 1]
    } else {
      if (sIdx > 0) focusSection = sections[sIdx - 1]
    }
  }

  function moveCursorH(delta) {
    if (focusSection === "scroll") {
      adjustScrollFactor(delta > 0 ? 0.1 : -0.1)
    } else if (focusSection === "pointer") {
      adjustPointerSpeed(delta > 0 ? 0.1 : -0.1)
    }
  }

  function activateCursor() {
    if (focusSection === "header") { toggleTouchpad(); return }
    if (focusSection === "natural") { toggleNaturalScroll(); return }
    if (focusSection === "tap") { toggleTapToClick(); return }
    if (focusSection === "typing") { toggleDisableWhileTyping(); return }
    if (focusSection === "clickfinger") { toggleClickfingerBehavior(); return }
  }

  // ---- Actions ----
  // The reload chained onto the enable is defensive, not a proven fix.
  //
  // We hit one failure where the pad stayed dead after toggling back on while
  // the panel reported ENABLED, and an explicit `hyprctl reload` revived it.
  // The obvious explanation -- that hl.device({ enabled = true }) cannot
  // re-attach an already-detached device -- was later tested directly and is
  // FALSE: `omarchy-toggle-touchpad off` then `on` recovers fine on its own,
  // with or without a config reload in between. So the original trigger is
  // still unidentified, and quite possibly was a transient unrelated to the
  // stock tool (the shell was being restarted repeatedly at the time).
  //
  // The reload stays because it is cheap, idempotent, and makes the enable
  // path robust whatever that transient was -- it also re-applies our own
  // persisted settings. Do not read it as documentation of a Hyprland bug.
  // It is ordered after omarchy-toggle-input-device clears the disabled-name
  // marker; reloading first would let disabled-input-device.lua re-disable.
  function toggleTouchpad() {
    if (!deviceName) return
    var next = !touchpadEnabled
    touchpadEnabled = next
    if (next) {
      Quickshell.execDetached(["bash", "-c",
        "omarchy-toggle-input-device touchpad on && hyprctl reload >/dev/null"])
    } else {
      Quickshell.execDetached(["omarchy-toggle-input-device", "touchpad", "off"])
    }
    // The optimistic flip above is a guess until the marker file and the
    // compositor agree. Re-read shortly after so a failed enable corrects
    // itself rather than leaving the panel claiming ENABLED over a dead pad.
    enableSettle.restart()
  }

  function toggleNaturalScroll() {
    var next = !naturalScroll
    naturalScroll = next
    setHyprOption("natural_scroll", next)
  }

  function toggleTapToClick() {
    var next = !tapToClick
    tapToClick = next
    setHyprOption("tap_to_click", next)
  }

  function toggleDisableWhileTyping() {
    var next = !disableWhileTyping
    disableWhileTyping = next
    setHyprOption("disable_while_typing", next)
  }

  function toggleClickfingerBehavior() {
    var next = !clickfingerBehavior
    clickfingerBehavior = next
    setHyprOption("clickfinger_behavior", next)
  }

  // Every caller passes a literal option name and an already-clamped value, but
  // this string is handed to `hyprctl eval` as Lua, so it is checked here
  // instead of resting on a caller audit -- the guarantee should be readable in
  // this function alone. An option name is a bare identifier; a number is
  // rendered as a plain decimal rather than through String(), which for an
  // unexpected magnitude could emit exponent notation.
  function setHyprOption(option, value) {
    if (!/^[a-z_]+$/.test(option)) return
    var luaValue
    if (typeof value === "boolean") {
      luaValue = value ? "true" : "false"
    } else {
      var n = Number(value)
      if (!isFinite(n)) return
      luaValue = n.toFixed(1)
    }
    Quickshell.execDetached(["hyprctl", "eval", "hl.config({ input = { touchpad = { " + option + " = " + luaValue + " } } })"])
    persistSettings()
  }

  // `hyprctl eval` only changes the running compositor. Omarchy's default
  // input.lua hardcodes natural_scroll = false, so the next config reload
  // (theme switch, saving any hypr/*.lua, hyprctl reload) re-applies the
  // default and our runtime change is lost. Mirror every setting into the
  // toggles state dir, which default/hypr/toggles.lua re-requires on each
  // reload -- and does so after hypr/input.lua, so it wins.
  function persistSettings() {
    var lua = "-- Generated by the awkent01.touchpad bar widget. Edit the widget, not this file.\n"
      + "-- Loaded on every Hyprland config reload by default/hypr/toggles.lua, which is\n"
      + "-- what keeps these from reverting to Omarchy's input.lua defaults.\n"
      + "hl.config({\n"
      + "  input = {\n"
      + "    touchpad = {\n"
      + "      natural_scroll = " + (naturalScroll ? "true" : "false") + ",\n"
      + "      tap_to_click = " + (tapToClick ? "true" : "false") + ",\n"
      + "      disable_while_typing = " + (disableWhileTyping ? "true" : "false") + ",\n"
      + "      clickfinger_behavior = " + (clickfingerBehavior ? "true" : "false") + ",\n"
      + "      scroll_factor = " + Model.clampScrollFactor(scrollFactor).toFixed(1) + ",\n"
      + "    },\n"
      + "  },\n"
      + "})\n"
      // Device names are read back as data at reload time, never written into
      // this file as code. Same rule default/hypr/disabled-input-device.lua
      // follows for the disabled-name marker.
      + "\n"
      + "-- Re-apply the per-device pointer sensitivity. Both values are read as\n"
      + "-- data; nothing below is generated from a device name.\n"
      + "--\n"
      + "-- Hyprland's config Lua has no lstat and no O_NOFOLLOW, so it cannot\n"
      + "-- prove what it opened the way touchpad-state can. Two things stand in\n"
      + "-- for that: touchpad-state refuses to write anything at all unless the\n"
      + "-- whole directory chain is ours and unwritable by anyone else, so no\n"
      + "-- one else can put a symlink or a FIFO on these paths; and the reads\n"
      + "-- below are byte-bounded and the values re-validated here, so a file\n"
      + "-- that did somehow change still cannot make a reload read without end\n"
      + "-- or hand hl.device something outside its range.\n"
      + "local paths = require(\"default.hypr.paths\")\n"
      + "local dir = paths.state_home .. \"/omarchy/toggles/hypr\"\n"
      + "local function read_value(path, limit)\n"
      + "  local f = io.open(path, \"r\")\n"
      + "  if not f then return nil end\n"
      + "  local chunk = f:read(limit)\n"
      + "  f:close()\n"
      + "  if not chunk then return nil end\n"
      + "  return chunk:match(\"^[^\\r\\n]*\")\n"
      + "end\n"
      + "local sens_name = read_value(dir .. \"/touchpad-sensitivity-name\", 256)\n"
      + "local sens_value = tonumber(read_value(dir .. \"/touchpad-sensitivity-value\", 32))\n"
      + "if sens_name and sens_name ~= \"\" and not sens_name:find(\"%c\")\n"
      + "    and sens_value and sens_value >= -1 and sens_value <= 1 then\n"
      + "  hl.device({ name = sens_name, sensitivity = sens_value })\n"
      + "end\n"

    // Only booleans and a clamped number reach the file -- no device names or
    // other outside strings are ever interpolated into generated Lua.
    //
    // The write goes through touchpad-state rather than a redirection here: the
    // path is predictable, so it has to land via an exclusive temporary renamed
    // over a destination that has been checked, not through a `>` that would
    // follow a planted symlink or block on a planted FIFO. Passing the content
    // as an argument also keeps it out of shell parsing entirely.
    Quickshell.execDetached([stateScript, "write", "touchpad-settings.lua", lua])
  }

  function adjustScrollFactor(delta) {
    var next = Model.clampScrollFactor(scrollFactor + delta)
    scrollFactor = next
    pendingScrollFactor = next
    scrollDebounce.restart()
  }

  function setScrollFactor(value) {
    var clamped = Model.clampScrollFactor(value)
    scrollFactor = clamped
    pendingScrollFactor = clamped
    scrollDebounce.restart()
  }

  function commitScrollFactor() {
    setHyprOption("scroll_factor", pendingScrollFactor)
  }

  function adjustPointerSpeed(delta) {
    var next = Model.clampSensitivity(pointerSpeed + delta)
    pointerSpeed = next
    pendingPointerSpeed = next
    pointerDebounce.restart()
  }

  function setPointerSpeed(value) {
    var clamped = Model.clampSensitivity(value)
    pointerSpeed = clamped
    pendingPointerSpeed = clamped
    pointerDebounce.restart()
  }

  // Applied per-device rather than through input:sensitivity so the trackpoint
  // and any plugged-in mouse keep their own speed. The device name lookup,
  // validation, escaping, and persistence all live in the touchpad-sensitivity
  // script beside this file -- keeping that logic out of a QML string literal
  // is what makes the Lua escaping reviewable and testable.
  readonly property string sensitivityScript:
    String(Qt.resolvedUrl("touchpad-sensitivity")).replace(/^file:\/\//, "")

  // Every read and write of this widget's state files goes through here. See
  // the header of touchpad-state for what it guarantees and why.
  readonly property string stateScript:
    String(Qt.resolvedUrl("touchpad-state")).replace(/^file:\/\//, "")

  function commitPointerSpeed() {
    if (!deviceName) return
    var v = Model.clampSensitivity(pendingPointerSpeed)
    pointerSpeed = v
    Quickshell.execDetached([sensitivityScript, v.toFixed(1)])
    persistSettings()
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
  }

  // ---- IPC ----
  IpcHandler {
    target: "awkent01.touchpad"

    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function show() { root.open() }
    function hide() { root.close() }
  }

  // ---- Lifecycle ----
  visible: deviceName !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (opened) {
      refresh()
      focusSection = "header"
      cursorActive = false
    }
  }

  // Poll while open so external changes are reflected.
  Timer {
    interval: 3000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  // Rotate the hero phrase while the panel is open and a device is present.
  // The swap is wrapped in a fade so the changeover reads as one motion
  // rather than a hard cut.
  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    triggeredOnStart: false
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = root.activePhrases.length
        if (n > 0) root.phraseIndex = (root.phraseIndex + 1) % n
      }
    }
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  // Toggling the pad swaps phrase sets, so restart the cycle from the top --
  // otherwise index 4 of "enabled" carries over as index 4 of "disabled" and
  // the label looks like it skipped. Leaving a rotating state entirely (device
  // unplugged) halts a mid-flight fade so "NO DEVICE" is never stuck dimmed.
  Connections {
    target: root
    function onActivePhrasesChanged() {
      phraseSwap.stop()
      heroStatus.opacity = 1.0
      root.phraseIndex = 0
    }
  }

  // Give omarchy-toggle-input-device and the reload time to land, then
  // reconcile the panel against real state.
  Timer {
    id: enableSettle
    interval: 600
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: scrollDebounce
    interval: 200
    repeat: false
    onTriggered: root.commitScrollFactor()
  }

  Timer {
    id: pointerDebounce
    interval: 200
    repeat: false
    onTriggered: root.commitPointerSpeed()
  }

  // ---- State process: reads all touchpad options in one shot ----
  Process {
    id: stateProc
    command: ["bash", "-c",
      "hyprctl devices -j 2>/dev/null; echo '---SPLIT---'; " +
      "hyprctl getoption input:touchpad:natural_scroll -j 2>/dev/null; echo '---SPLIT---'; " +
      "hyprctl getoption input:touchpad:scroll_factor -j 2>/dev/null; echo '---SPLIT---'; " +
      "hyprctl getoption 'input:touchpad:tap-to-click' -j 2>/dev/null; echo '---SPLIT---'; " +
      "hyprctl getoption input:touchpad:disable_while_typing -j 2>/dev/null; echo '---SPLIT---'; " +
      "hyprctl getoption input:touchpad:clickfinger_behavior -j 2>/dev/null; echo '---SPLIT---'; " +
      // Omarchy's own marker file, tested rather than read: this yields a
      // boolean and opens nothing, so a planted symlink or FIFO here can at
      // worst mislabel the toggle for one refresh -- it cannot redirect a
      // write or block this process. The file belongs to
      // omarchy-toggle-input-device, so hardening how it is *written* belongs
      // upstream rather than in a plugin that only reads it.
      "test -f \"$HOME/.local/state/omarchy/toggles/hypr/touchpad-disabled-name\" && echo disabled || echo enabled; " +
      "echo '---SPLIT---'; " +
      // Device options cannot be read back through hyprctl getoption, so the
      // value we last wrote is the only source of truth for the slider. Read it
      // through touchpad-state -- a plain `cat` on this predictable path would
      // follow a planted symlink, and would hang this whole process on a
      // planted FIFO, leaving the panel with no state at all. The helper path
      // is passed as an argument rather than spliced into the script text.
      "\"$1\" read touchpad-sensitivity-value || true",
      "touchpad-state", root.stateScript
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").split("---SPLIT---")
        if (parts.length < 8) return

        root.deviceName = Model.parseTouchpadDevice(parts[0])
        root.naturalScroll = Model.parseBool(parts[1])
        root.scrollFactor = Model.parseFloat(parts[2]) || 0.4
        root.pendingScrollFactor = root.scrollFactor
        root.tapToClick = Model.parseBool(parts[3])
        root.disableWhileTyping = Model.parseBool(parts[4])
        root.clickfingerBehavior = Model.parseBool(parts[5])
        root.touchpadEnabled = String(parts[6] || "").trim() !== "disabled"

        // null means "never set" -- fall back to Hyprland's 0.0 baseline
        // rather than letting an unreadable file read as a real value.
        var sens = Model.parseSensitivityFile(parts[7])
        root.pointerSpeed = sens === null ? 0.0 : sens
        root.pendingPointerSpeed = root.pointerSpeed
      }
    }
  }

  // ---- Bar icon ----
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleTouchpad()
      else root.toggle()
    }
  }

  // ---- Popup panel ----
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(14)

        // ========== Hero: Touchpad icon + status + power toggle ==========
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, powerSwitch.implicitHeight)

          Text {
            id: heroIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            opacity: root.touchpadEnabled ? 1.0 : 0.5
          }

          ToggleSwitch {
            id: powerSwitch
            visible: root.deviceName !== ""
            checked: root.touchpadEnabled
            hasCursor: root.cursorActive && root.focusSection === "header"
            foreground: root.bar.foreground
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            onHovered: function(on) {
              if (on) {
                root.cursorActive = true
                root.focusSection = "header"
              }
            }
            onToggled: root.toggleTouchpad()

            PanelToolTip {
              visible: powerSwitch.containsMouse
              text: root.touchpadEnabled ? "Disable touchpad" : "Enable touchpad"
              fontFamily: root.bar.fontFamily
            }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.rightMargin: powerSwitch.visible ? powerSwitch.width + Style.space(12) : 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Touchpad"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              id: heroStatus
              text: root.heroStatusText.toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        // ========== Scroll speed slider ==========
        Column {
          width: parent.width
          spacing: Style.space(8)
          opacity: root.touchpadEnabled ? 1.0 : 0.4

          Item {
            width: parent.width
            implicitHeight: scrollLabel.implicitHeight

            Text {
              id: scrollLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Scroll Speed"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: {
                var v = scrollSlider.dragging ? scrollSlider.liveValue : root.scrollFactor
                return Model.scrollSpeedLabel(v) + "  " + v.toFixed(1)
              }
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(minusBtn.implicitHeight, scrollRow.implicitHeight, plusBtn.implicitHeight)

            // Minus button
            CursorSurface {
              id: minusSurface
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(32)
              height: Style.space(32)
              hasCursor: false
              foreground: root.bar.foreground
              fill: root.hoverFill

              Text {
                id: minusBtn
                anchors.centerIn: parent
                text: "−"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.heading
                opacity: root.scrollFactor <= 0.1 ? 0.3 : 1.0
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.adjustScrollFactor(-0.1)
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.focusSection = "scroll"
                }
              }
            }

            // Slider track
            CursorSurface {
              id: scrollRow
              anchors.left: minusSurface.right
              anchors.right: plusSurface.left
              anchors.leftMargin: Style.space(4)
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              height: scrollSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "scroll"
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: scrollSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 0.1
                maximum: 2.0
                step: 0.1
                value: root.scrollFactor
                onMoved: function(v) { root.setScrollFactor(v) }
                onReleased: function(v) {
                  scrollDebounce.stop()
                  root.setScrollFactor(v)
                  root.commitScrollFactor()
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered) {
                  root.cursorActive = true
                  root.focusSection = "scroll"
                }
              }
            }

            // Plus button
            CursorSurface {
              id: plusSurface
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(32)
              height: Style.space(32)
              hasCursor: false
              foreground: root.bar.foreground
              fill: root.hoverFill

              Text {
                id: plusBtn
                anchors.centerIn: parent
                text: "+"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.heading
                opacity: root.scrollFactor >= 2.0 ? 0.3 : 1.0
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.adjustScrollFactor(0.1)
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.focusSection = "scroll"
                }
              }
            }
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        // ========== Pointer speed slider ==========
        // Range is Hyprland's [-1.0, 1.0], centered on 0.0 rather than running
        // low-to-high like the scroll slider above it.
        Column {
          width: parent.width
          spacing: Style.space(8)
          opacity: root.touchpadEnabled ? 1.0 : 0.4

          Item {
            width: parent.width
            implicitHeight: pointerLabel.implicitHeight

            Text {
              id: pointerLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Pointer Speed"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: {
                var v = pointerSlider.dragging ? pointerSlider.liveValue : root.pointerSpeed
                return Model.pointerSpeedLabel(v) + "  " + v.toFixed(1)
              }
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(pMinusBtn.implicitHeight, pointerRow.implicitHeight, pPlusBtn.implicitHeight)

            CursorSurface {
              id: pMinusSurface
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(32)
              height: Style.space(32)
              hasCursor: false
              foreground: root.bar.foreground
              fill: root.hoverFill

              Text {
                id: pMinusBtn
                anchors.centerIn: parent
                text: "−"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.heading
                opacity: root.pointerSpeed <= -1.0 ? 0.3 : 1.0
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.adjustPointerSpeed(-0.1)
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.focusSection = "pointer"
                }
              }
            }

            CursorSurface {
              id: pointerRow
              anchors.left: pMinusSurface.right
              anchors.right: pPlusSurface.left
              anchors.leftMargin: Style.space(4)
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              height: pointerSlider.implicitHeight + Style.spacing.controlGap
              hasCursor: root.cursorActive && root.focusSection === "pointer"
              foreground: root.bar.foreground
              outline: true

              PanelSlider {
                id: pointerSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: -1.0
                maximum: 1.0
                step: 0.1
                value: root.pointerSpeed
                onMoved: function(v) { root.setPointerSpeed(v) }
                onReleased: function(v) {
                  pointerDebounce.stop()
                  root.setPointerSpeed(v)
                  root.commitPointerSpeed()
                }
              }

              HoverHandler {
                onHoveredChanged: if (hovered) {
                  root.cursorActive = true
                  root.focusSection = "pointer"
                }
              }
            }

            CursorSurface {
              id: pPlusSurface
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(32)
              height: Style.space(32)
              hasCursor: false
              foreground: root.bar.foreground
              fill: root.hoverFill

              Text {
                id: pPlusBtn
                anchors.centerIn: parent
                text: "+"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.heading
                opacity: root.pointerSpeed >= 1.0 ? 0.3 : 1.0
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.adjustPointerSpeed(0.1)
                onContainsMouseChanged: if (containsMouse) {
                  root.cursorActive = true
                  root.focusSection = "pointer"
                }
              }
            }
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        // ========== Toggle rows ==========
        Column {
          width: parent.width
          spacing: Style.space(6)
          opacity: root.touchpadEnabled ? 1.0 : 0.4

          ToggleRow {
            width: parent.width
            label: "Natural Scrolling"
            description: "Scroll content in the direction of finger movement"
            checked: root.naturalScroll
            sectionName: "natural"
            enabled: root.touchpadEnabled
            onToggled: root.toggleNaturalScroll()
          }

          ToggleRow {
            width: parent.width
            label: "Tap to Click"
            description: "Tap the touchpad to click"
            checked: root.tapToClick
            sectionName: "tap"
            enabled: root.touchpadEnabled
            onToggled: root.toggleTapToClick()
          }

          ToggleRow {
            width: parent.width
            label: "Disable While Typing"
            description: "Ignore touchpad input while typing"
            checked: root.disableWhileTyping
            sectionName: "typing"
            enabled: root.touchpadEnabled
            onToggled: root.toggleDisableWhileTyping()
          }

          ToggleRow {
            width: parent.width
            label: "Two-Finger Right Click"
            description: "Use two-finger tap for right-click"
            checked: root.clickfingerBehavior
            sectionName: "clickfinger"
            enabled: root.touchpadEnabled
            onToggled: root.toggleClickfingerBehavior()
          }
        }
      }
    }
  }

  // ========== Reusable toggle row component ==========
  component ToggleRow: CursorSurface {
    id: toggleRow
    required property string label
    required property string description
    required property bool checked
    required property string sectionName
    property bool enabled: true

    signal toggled()

    hasCursor: root.cursorActive && root.focusSection === sectionName
    foreground: root.bar.foreground
    fill: root.hoverFill

    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = toggleRow.sectionName
      }
      onClicked: if (toggleRow.enabled) toggleRow.toggled()
    }

    Item {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(rowLabels.implicitHeight, rowSwitch.implicitHeight)

      Column {
        id: rowLabels
        anchors.left: parent.left
        anchors.right: rowSwitch.left
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          text: toggleRow.label
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width
        }

        Text {
          visible: toggleRow.description !== ""
          text: toggleRow.description
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
          wrapMode: Text.WordWrap
        }
      }

      ToggleSwitch {
        id: rowSwitch
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: toggleRow.checked
        foreground: root.bar.foreground
        onToggled: if (toggleRow.enabled) toggleRow.toggled()
      }
    }
  }
}
