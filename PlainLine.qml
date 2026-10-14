import QtQuick
import qs.Commons
import qs.Ui
import "PlainEdit.js" as Edit

// One line of text drawn with Text. Key handling lives here.
// The row loader creates this only while that row is being renamed.
FocusScope {
  id: root

  property string placeholderText: ""
  property int maximumLength: 80
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property int fontPixelSize: Style.font.body
  property bool hovered: false

  signal accepted(string value)
  signal rejected()

  property string draft: ""
  property int cursor: 0
  property int anchor: 0
  property bool settled: false
  readonly property string editText: draft
  readonly property bool hasSelection: cursor !== anchor
  readonly property var borderSpec: Border.controlSpec(activeFocus ? "focus" : (hovered ? "hover-cursor" : "normal"), foreground, accent)
  readonly property real padL: Style.space(6) + Border.left(borderSpec)
  readonly property real padR: Style.space(6) + Border.right(borderSpec)
  readonly property real padT: Style.space(2) + Border.top(borderSpec)
  readonly property real padB: Style.space(2) + Border.bottom(borderSpec)

  implicitHeight: line.implicitHeight + padT + padB
  activeFocusOnTab: false

  function load(value, selectAllText) {
    var next = String(value || "")
    if (maximumLength > 0 && next.length > maximumLength) next = next.slice(0, maximumLength)
    draft = next
    anchor = 0
    cursor = selectAllText ? next.length : next.length
    if (!selectAllText) anchor = cursor
    caretOn = true
  }

  function commit() {
    if (settled) return
    settled = true
    accepted(editText)
  }

  function cancel() {
    if (settled) return
    settled = true
    rejected()
  }

  function apply(next) {
    draft = next.text
    cursor = next.cursor
    anchor = next.anchor
    caretOn = true
  }

  function place(index, extend) {
    var n = Edit.clampIndex(editText, index)
    cursor = n
    if (!extend) anchor = n
    caretOn = true
  }

  property var advances: [0]

  function rebuildAdvances() {
    var src = editText
    var next = [0]
    var acc = ""
    for (var i = 0; i < src.length; i++) {
      acc += src.charAt(i)
      metrics.text = acc
      next.push(metrics.advanceWidth)
    }
    advances = next
  }

  onEditTextChanged: rebuildAdvances()
  onFontFamilyChanged: rebuildAdvances()
  onFontPixelSizeChanged: rebuildAdvances()
  Component.onCompleted: rebuildAdvances()

  function advance(index) {
    var list = advances
    if (!list || !list.length) return 0
    var i = index | 0
    if (i < 0) return 0
    if (i >= list.length) return list[list.length - 1]
    return list[i]
  }

  function indexAt(x) {
    var local = x - track.x
    var n = editText.length
    var best = 0
    var bestDist = Number.POSITIVE_INFINITY
    for (var i = 0; i <= n; i++) {
      var dist = Math.abs(advance(i) - local)
      if (dist < bestDist) {
        bestDist = dist
        best = i
      }
    }
    return best
  }

  Keys.onPressed: function(event) {
    if (!root.enabled) return
    if (event.key === Qt.Key_Escape) {
      event.accepted = true
      root.cancel()
      return
    }
    var mods = event.modifiers
    var command = (mods & (Qt.ControlModifier | Qt.MetaModifier)) !== 0
    var shift = (mods & Qt.ShiftModifier) !== 0
    if (command && (event.key === Qt.Key_V || event.key === Qt.Key_C || event.key === Qt.Key_X || event.key === Qt.Key_Insert)) {
      event.accepted = true
      return
    }
    if (shift && event.key === Qt.Key_Insert) {
      event.accepted = true
      return
    }
    if (command && event.key === Qt.Key_A) {
      root.anchor = 0
      root.cursor = root.editText.length
      root.caretOn = true
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (event.isAutoRepeat) {
        event.accepted = true
        return
      }
      event.accepted = true
      root.commit()
      return
    }
    var extend = shift
    if (event.key === Qt.Key_Backspace) {
      root.apply(Edit.backspace(root.editText, root.cursor, root.anchor))
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Delete) {
      root.apply(Edit.deleteForward(root.editText, root.cursor, root.anchor))
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Left) {
      var left = Edit.move(root.editText, root.cursor, root.anchor, -1, extend)
      root.cursor = left.cursor
      root.anchor = left.anchor
      root.caretOn = true
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Right) {
      var right = Edit.move(root.editText, root.cursor, root.anchor, 1, extend)
      root.cursor = right.cursor
      root.anchor = right.anchor
      root.caretOn = true
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Home) {
      var toStart = Edit.home(root.editText, root.anchor, extend)
      root.cursor = toStart.cursor
      root.anchor = toStart.anchor
      root.caretOn = true
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_End) {
      var toEnd = Edit.end(root.editText, root.anchor, extend)
      root.cursor = toEnd.cursor
      root.anchor = toEnd.anchor
      root.caretOn = true
      event.accepted = true
      return
    }
    if ((mods & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) !== 0) return
    if (!event.text || !Edit.usable(event.text.charAt(0))) return
    root.apply(Edit.insert(root.editText, root.cursor, root.anchor, event.text, root.maximumLength))
    event.accepted = true
  }

  property bool caretOn: true

  Connections {
    target: root
    function onActiveFocusChanged() {
      if (!root.activeFocus) return
      root.caretOn = true
    }
  }

  Timer {
    interval: 530
    repeat: true
    running: root.activeFocus && !root.hasSelection
    onTriggered: root.caretOn = !root.caretOn
  }

  HoverHandler {
    id: lineHover
    onHoveredChanged: root.hovered = lineHover.hovered
  }

  BorderSurface {
    anchors.fill: parent
    color: Style.controlFill(root.activeFocus, root.hovered, root.foreground, root.accent)
    borderSpec: root.borderSpec
    radius: Style.cornerRadius
  }

  Item {
    id: view
    anchors.fill: parent
    anchors.leftMargin: root.padL
    anchors.rightMargin: root.padR
    anchors.topMargin: root.padT
    anchors.bottomMargin: root.padB
    clip: true

    Item {
      id: track
      height: line.implicitHeight
      width: Math.max(line.implicitWidth, 1)
      y: Math.max(0, (view.height - height) / 2)
      x: {
        var caret = root.advance(root.cursor)
        var overflow = caret + 2 - view.width
        return overflow > 0 ? -overflow : 0
      }

      Rectangle {
        visible: root.hasSelection
        x: root.advance(Math.min(root.cursor, root.anchor))
        width: Math.max(1, root.advance(Math.max(root.cursor, root.anchor)) - x)
        height: parent.height
        color: Style.selectionFillFor(root.foreground, root.accent)
      }

      Text {
        id: line
        text: root.editText === "" ? root.placeholderText : root.editText
        textFormat: Text.PlainText
        color: root.editText === "" ? Qt.darker(root.foreground, 1.6) : root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.fontPixelSize
      }

      Rectangle {
        visible: root.activeFocus && !root.hasSelection && root.caretOn
        x: root.advance(root.cursor)
        y: 0
        width: 1
        height: parent.height
        color: root.foreground
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.IBeamCursor
      acceptedButtons: Qt.LeftButton
      enabled: root.enabled
      preventStealing: true
      onPressed: function(mouse) {
        root.forceActiveFocus()
        root.place(root.indexAt(mouse.x), false)
        root.pressIndex = root.cursor
        mouse.accepted = true
      }
      onPositionChanged: function(mouse) {
        if ((mouse.buttons & Qt.LeftButton) === 0) return
        root.cursor = root.indexAt(mouse.x)
        root.anchor = root.pressIndex
        root.caretOn = true
      }
    }
  }

  property int pressIndex: 0

  TextMetrics {
    id: metrics
    font.family: line.font.family
    font.pixelSize: line.font.pixelSize
  }
}
