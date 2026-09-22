import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Restart glyph in the bar. The popup lists firmware operating systems and,
// after a countdown, sets BootNext and reboots. Colors, type, and the popup
// surface all come from the shell theme the way the built-in panels do.
Panel {
  id: root

  moduleName: "io.github.07dcolem.target-boot"
  ipcTarget: "io.github.07dcolem.target-boot"
  manageIpc: false

  readonly property string cli: {
    var url = Qt.resolvedUrl("bin/target-boot").toString()
    if (url.indexOf("file://") === 0) url = url.substring(7)
    try { return decodeURIComponent(url) } catch (e) { return url }
  }
  readonly property string rebootGlyph: "󰜉"
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool showInactive: setting("showInactive", false) === true
  readonly property color hoverFill: Style.hoverFillFor(foreground, Color.accent)
  readonly property color selectedFill: Style.selectedFillFor(foreground, Color.accent)

  property var firmware: ({ ok: false, entries: [], bootCurrent: null, bootNext: null, bootOrder: [] })
  property string payloadText: ""
  property string errorText: ""
  property bool cursorActive: false
  property int selectedIndex: 0
  property bool cursorReady: false

  property bool departing: false
  property bool busy: false
  property bool committed: false
  property string departingId: ""
  property string departingLabel: ""
  property int countdown: Model.countdownStart()
  property int pendingCountdown: Model.countdownStart()
  property string shownLine: ""

  readonly property var visibleEntries: Model.visibleEntries(firmware, showInactive)
  readonly property string bootNextId: firmware && firmware.bootNext ? String(firmware.bootNext) : ""
  readonly property string bootNextLabel: {
    var entry = Model.entryById(firmware ? firmware.entries : [], bootNextId)
    return entry && entry.label ? String(entry.label) : ""
  }
  readonly property string statusLine: Model.departingLine(countdown, departingLabel)
  readonly property string caption: {
    if (bootNextLabel !== "")
      return "Next boot is " + bootNextLabel + ". Pick another operating system to replace it."
    return "Pick an operating system. It counts down, sets next boot, and reboots."
  }

  readonly property int barSlot: Style.bar.iconSlot
  implicitWidth: bar && bar.vertical ? bar.barSize : barSlot
  implicitHeight: bar && bar.vertical ? barSlot : (bar ? bar.barSize : Style.bar.sizeHorizontal)

  function refresh() {
    listProc.running = false
    listProc.command = [cli, "list"]
    listProc.running = true
  }

  function syncCursor() {
    var rows = visibleEntries
    if (!cursorReady) {
      var current = Model.indexOfCurrent(rows)
      selectedIndex = current >= 0 ? current : 0
      cursorReady = true
      return
    }
    if (selectedIndex >= rows.length) selectedIndex = Math.max(0, rows.length - 1)
  }

  function moveCursor(delta) {
    if (departing) return
    cursorActive = true
    selectedIndex = Model.moveIndex(selectedIndex, delta, visibleEntries.length)
  }

  function activateCursor() {
    if (departing || busy || committed) return
    var rows = visibleEntries
    if (selectedIndex < 0 || selectedIndex >= rows.length) return
    beginDeparture(rows[selectedIndex].id)
  }

  function playArrive() {
    countLabel.opacity = 0
    countLabel.scale = 0.9
    countLabel.y = Style.space(6)
    lineLabel.opacity = 0
    nameLabel.opacity = 0
    arrive.restart()
  }

  function beginDeparture(id) {
    if (busy || committed) return
    var clean = Model.normalizeId(id)
    if (!clean) {
      errorText = "Boot id must be four hex digits"
      return
    }
    var entry = Model.entryById(firmware ? firmware.entries : [], clean)
    if (!entry) {
      errorText = "That operating system is not in the firmware list"
      return
    }
    errorText = ""
    var already = departing
    departingId = clean
    departingLabel = String(entry.label || clean)
    countdown = Model.countdownStart()
    pendingCountdown = countdown
    shownLine = ""
    departing = true
    countdownTimer.restart()
    if (already) playArrive()
    if (!opened) open()
  }

  function cancelDeparture() {
    if (busy || committed) return
    countdownTimer.stop()
    countSwap.stop()
    arrive.stop()
    departing = false
  }

  function advanceDeparture() {
    if (!departing || busy || committed) return
    var step = Model.stepCountdown(countdown)
    if (step.commit) {
      commitReboot()
      return
    }
    pendingCountdown = step.countdown
    countSwap.restart()
  }

  function applyPendingStep() {
    countdown = pendingCountdown
  }

  function commitReboot() {
    if (busy || committed || departingId === "") return
    countdownTimer.stop()
    busy = true
    actionProc.running = false
    actionProc.command = [cli, "reboot-into", departingId]
    actionProc.running = true
  }

  function finishAction(code, stdout) {
    var parsed = Model.parsePayload(stdout)
    if (code !== 0 || !parsed.ok) {
      busy = false
      committed = false
      departing = false
      errorText = parsed.error || "Could not set next boot"
      if (!opened) open()
      refresh()
      return
    }
    committed = true
  }

  function clearNext() {
    if (busy || committed) return
    busy = true
    clearProc.running = false
    clearProc.command = [cli, "clear-next"]
    clearProc.running = true
  }

  function applyList(code, stdout) {
    var parsed = Model.parsePayload(stdout)
    if (code !== 0 || !parsed.ok || !Array.isArray(parsed.bootOrder)) {
      errorText = parsed.error || "Could not read the EFI boot entries"
      return
    }
    if (errorText !== "" && !departing) errorText = ""
    firmware = parsed
    payloadText = stdout
    syncCursor()
  }

  onStatusLineChanged: if (departing) shownLine = ""
  onDepartingChanged: if (departing) playArrive()
  onSettingsChanged: syncCursor()
  onOpenedChanged: {
    if (opened) {
      refresh()
      return
    }
    if (!committed) cancelDeparture()
  }
  Component.onCompleted: refresh()

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function list(): string { return root.payloadText }
    function rebootInto(id: string): string {
      root.beginDeparture(id)
      return root.errorText === "" ? "ok" : root.errorText
    }
  }

  Timer {
    id: countdownTimer
    interval: Model.holdMs()
    repeat: true
    running: root.departing && !root.busy && !root.committed
    onTriggered: root.advanceDeparture()
  }

  Timer {
    id: typeTimer
    interval: Model.typeMs()
    repeat: true
    running: root.departing && root.shownLine.length < root.statusLine.length
    onTriggered: root.shownLine = root.statusLine.slice(0, root.shownLine.length + 1)
  }

  ParallelAnimation {
    id: arrive
    NumberAnimation { target: countLabel; property: "opacity"; from: 0; to: 1; duration: 280; easing.type: Easing.OutCubic }
    NumberAnimation { target: countLabel; property: "scale"; from: 0.9; to: 1; duration: 280; easing.type: Easing.OutCubic }
    NumberAnimation { target: countLabel; property: "y"; from: Style.space(6); to: 0; duration: 280; easing.type: Easing.OutCubic }
    NumberAnimation { target: lineLabel; property: "opacity"; from: 0; to: 1; duration: 320; easing.type: Easing.OutQuad }
    NumberAnimation { target: nameLabel; property: "opacity"; from: 0; to: 1; duration: 320; easing.type: Easing.OutQuad }
  }

  SequentialAnimation {
    id: countSwap
    ParallelAnimation {
      NumberAnimation { target: countLabel; property: "opacity"; to: 0; duration: 140; easing.type: Easing.InQuad }
      NumberAnimation { target: countLabel; property: "scale"; to: 0.88; duration: 140; easing.type: Easing.InQuad }
      NumberAnimation { target: lineLabel; property: "opacity"; to: 0; duration: 140; easing.type: Easing.InQuad }
    }
    ScriptAction { script: root.applyPendingStep() }
    ParallelAnimation {
      NumberAnimation { target: countLabel; property: "opacity"; to: 1; duration: 240; easing.type: Easing.OutCubic }
      NumberAnimation { target: countLabel; property: "scale"; to: 1; duration: 240; easing.type: Easing.OutCubic }
      NumberAnimation { target: lineLabel; property: "opacity"; to: 1; duration: 280; easing.type: Easing.OutQuad }
    }
  }

  Process {
    id: listProc
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    onExited: function(code) {
      Qt.callLater(function() { root.applyList(code, listOut.text) })
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    onExited: function(code) {
      Qt.callLater(function() { root.finishAction(code, actionOut.text) })
    }
  }

  Process {
    id: clearProc
    stdout: StdioCollector { id: clearOut; waitForEnd: true }
    onExited: function(code) {
      Qt.callLater(function() {
        root.busy = false
        var parsed = Model.parsePayload(clearOut.text)
        if (code !== 0 || !parsed.ok) {
          root.errorText = parsed.error || "Could not clear next boot"
          return
        }
        root.errorText = ""
        root.refresh()
      })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: root.barSlot
    text: root.rebootGlyph
    tooltipText: Model.plain(root.bootNextLabel !== "" ? "Next boot · " + root.bootNextLabel : "Reboot into…")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: {
        if (root.departing && !root.busy && !root.committed) root.cancelDeparture()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" && !root.departing) root.refresh()
      }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: scroller.width
          spacing: Style.spacing.panelGap

          Column {
            width: parent.width
            spacing: Style.spacing.xs
            visible: !root.departing

            Text {
              width: parent.width
              text: "Reboot into"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: root.caption
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          PanelSeparator {
            visible: !root.departing
            foreground: root.foreground
          }

          Item {
            id: stage
            width: parent.width
            clip: true
            implicitHeight: root.departing ? departBlock.implicitHeight : listBlock.implicitHeight

            Behavior on implicitHeight {
              NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            Column {
              id: listBlock
              width: parent.width
              spacing: Style.spacing.xs
              opacity: root.departing ? 0 : 1
              visible: opacity > 0

              Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }

              PanelSectionHeader {
                text: "OPERATING SYSTEMS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                width: parent.width
                visible: root.visibleEntries.length === 0
                text: root.firmware && root.firmware.ok ? "No EFI operating systems" : "Reading firmware…"
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Repeater {
                model: root.visibleEntries

                OsRow {
                  required property var modelData
                  required property int index
                  width: listBlock.width
                  entry: modelData
                  rowIndex: index
                }
              }
            }

            Column {
              id: departBlock
              width: parent.width
              spacing: Style.spacing.lg
              opacity: root.departing ? 1 : 0
              visible: opacity > 0

              Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

              PanelSectionHeader {
                text: "NEXT BOOT"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Item {
                width: parent.width
                implicitHeight: Math.max(countLabel.implicitHeight, rebootMark.implicitHeight) + Style.space(4)

                Text {
                  id: countLabel
                  visible: !root.busy && !root.committed
                  text: String(root.countdown)
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.displayLarge
                  font.bold: true
                  transformOrigin: Item.Left
                  y: 0
                }

                Text {
                  id: rebootMark
                  visible: root.busy || root.committed
                  text: root.rebootGlyph
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                  anchors.verticalCenter: parent.verticalCenter

                  SequentialAnimation on opacity {
                    running: rebootMark.visible
                    loops: Animation.Infinite
                    alwaysRunToEnd: false
                    NumberAnimation { from: 1.0; to: 0.4; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.4; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                  }
                }
              }

              Text {
                id: nameLabel
                width: parent.width
                text: Model.plain(root.departingLabel)
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
              }

              Text {
                id: lineLabel
                width: parent.width
                height: Style.font.body * 3
                text: root.shownLine
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Button {
                width: parent.width
                visible: root.departing && !root.busy && !root.committed
                text: "Stay here"
                tooltipText: "Or press Esc"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.body
                onClicked: root.cancelDeparture()
              }
            }
          }

          Text {
            width: parent.width
            visible: root.errorText !== "" && !root.departing
            text: root.errorText
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Button {
            width: parent.width
            visible: root.bootNextId !== "" && !root.departing && !root.busy
            text: "Clear next boot"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.body
            onClicked: root.clearNext()
          }
        }
      }
    }
  }

  component OsRow: CursorSurface {
    id: row

    property var entry: null
    property int rowIndex: 0

    readonly property bool rowSelected: root.cursorActive && root.selectedIndex === rowIndex && !root.departing

    hasCursor: rowSelected
    current: !!(entry && entry.current)
    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: rowBody.implicitHeight + Style.spacing.xl

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse && !root.departing) {
        root.cursorActive = true
        root.selectedIndex = row.rowIndex
      }
      onClicked: if (!root.departing) root.beginDeparture(row.entry ? row.entry.id : "")
    }

    PanelToolTip {
      visible: rowMouse.containsMouse && !root.departing
      text: "Reboot into " + Model.plain(row.entry ? row.entry.label : "")
      fontFamily: root.fontFamily
    }

    Item {
      id: rowBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      implicitHeight: Math.max(osIcon.implicitHeight, info.implicitHeight)

      Text {
        id: osIcon
        text: Model.iconFor(row.entry)
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        id: info
        anchors.left: osIcon.right
        anchors.leftMargin: Style.spacing.lg
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: Model.plain(row.entry && row.entry.label ? row.entry.label : "Operating system")
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: detail !== ""
          text: detail
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight

          readonly property string detail: Model.rowDetail(row.entry)
        }
      }
    }
  }
}
