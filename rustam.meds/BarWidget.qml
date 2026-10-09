import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "rustam.meds"
  ipcTarget: "rustam.meds"

  // Implicit dimensions delegated to the bar button
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Never draw an active indicator bar under the med icon
  readonly property real openPanelIndicatorWidth: 0

  // Pill states
  property bool mag1: false
  property bool mag2: false
  property bool b12_1: false
  property bool b12_2: false

  // Schedule & alert state
  property bool alertDue: true
  property string activeWindow: "pill2"
  property string windowLabel: "Evening Dose (5:00 PM – 5:00 AM)"
  property string dueSummary: "Magnesium 2, B12 2"
  property int totalTaken: 0

  readonly property color panelFg: Color.popups.text
  readonly property string fontFam: bar ? bar.fontFamily : Style.font.family
  readonly property string monoFam: "monospace"
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/+$/, "")

  function refreshStatus() {
    statusProc.running = true
  }

  function setPill(key, val) {
    // Optimistic UI update for instant feedback
    if (key === "mag1") root.mag1 = val
    else if (key === "mag2") root.mag2 = val
    else if (key === "b12_1") root.b12_1 = val
    else if (key === "b12_2") root.b12_2 = val

    updateAlertLocally()

    // Persist via helper
    actionProc.command = [
      "python3",
      root.pluginDir + "/meds_helper.py",
      "set",
      key,
      val ? "true" : "false"
    ]
    actionProc.running = true
  }

  function updateAlertLocally() {
    var now = new Date()
    var h = now.getHours()
    var isPill2 = (h >= 17 || h < 5)
    if (isPill2) {
      root.alertDue = !(root.mag2 && root.b12_2)
    } else {
      root.alertDue = !(root.mag1 && root.b12_1)
    }
    root.totalTaken = (root.mag1 ? 1 : 0) + (root.mag2 ? 1 : 0) + (root.b12_1 ? 1 : 0) + (root.b12_2 ? 1 : 0)
  }

  // Periodic poll to ensure schedule transitions (e.g. 5 PM rollover) happen automatically
  Timer {
    id: pollTimer
    interval: 30000
    running: true
    repeat: true
    onTriggered: refreshStatus()
  }

  Process {
    id: statusProc
    command: ["python3", root.pluginDir + "/meds_helper.py", "get"]
    running: false

    stdout: SplitParser {
      onRead: function(data) {
        if (!data || data.length === 0) return
        try {
          var s = JSON.parse(data)
          root.mag1 = !!s.mag1
          root.mag2 = !!s.mag2
          root.b12_1 = !!s.b12_1
          root.b12_2 = !!s.b12_2
          root.alertDue = !!s.alert
          root.activeWindow = s.active_window || "pill1"
          root.windowLabel = s.window_label || ""
          root.dueSummary = s.due_summary || ""
          root.totalTaken = s.total_taken || 0
        } catch (e) {}
      }
    }
  }

  Process {
    id: actionProc
    running: false

    stdout: SplitParser {
      onRead: function(data) {
        if (!data || data.length === 0) return
        try {
          var s = JSON.parse(data)
          root.mag1 = !!s.mag1
          root.mag2 = !!s.mag2
          root.b12_1 = !!s.b12_1
          root.b12_2 = !!s.b12_2
          root.alertDue = !!s.alert
          root.activeWindow = s.active_window || "pill1"
          root.windowLabel = s.window_label || ""
          root.dueSummary = s.due_summary || ""
          root.totalTaken = s.total_taken || 0
        } catch (e) {}
      }
    }
  }

  Component.onCompleted: refreshStatus()

  // ==================== TOP BAR BUTTON (STANDARD OMARCHY WIDGET BUTTON) ====================
  // Color changes ONLY based on whether medication is due (RED) or taken (NORMAL).
  // Clicking does NOT change its color to blue or accent.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "med💊"
    active: root.alertDue
    activeColor: Color.urgent
    foreground: root.barForeground
    useActiveColor: true
    tooltipText: root.windowLabel + (root.alertDue ? (" · Due: " + root.dueSummary) : " · All Taken!")

    onPressed: function(b) {
      root.toggle()
    }
  }

  // ==================== DROPDOWN BOX (KEYBOARD PANEL) ====================
  KeyboardPanel {
    id: medsPanel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher

    // React-like dynamic horizontal auto-expansion
    contentWidth: {
      var desired = Style.space(440)
      if (mainCol && mainCol.implicitWidth > 0) {
        desired = Math.max(desired, mainCol.implicitWidth + Style.space(32))
      }
      return medsPanel.fittedContentWidth(desired)
    }

    // Screen-constrained vertical height cap
    contentHeight: {
      var maxAvailable = medsPanel.availableCardHeight > 0
        ? Math.min(Style.space(460), medsPanel.availableCardHeight)
        : Style.space(460)
      return medsPanel.fittedContentHeight(mainCol.implicitHeight, maxAvailable)
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: mainCol
          width: panelFlick.width
          spacing: Style.space(12)

          // 1. Header Box
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "💊"
              font.family: root.fontFam
              font.pixelSize: Style.space(22)
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(1)

              Text {
                text: "Medication Tracker"
                color: root.panelFg
                font.family: root.fontFam
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                text: root.windowLabel
                color: root.alertDue ? Color.urgent : Color.accent
                font.family: root.fontFam
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            // Summary Pill Badge
            Rectangle {
              height: Style.space(24)
              implicitWidth: countText.implicitWidth + Style.space(14)
              radius: Style.space(12)
              color: root.totalTaken === 4
                ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2)
                : (root.alertDue ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.18) : Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, 0.1))
              border.color: root.totalTaken === 4 ? Color.accent : (root.alertDue ? Color.urgent : Qt.darker(root.panelFg, 1.8))
              border.width: 1

              Text {
                id: countText
                anchors.centerIn: parent
                text: root.totalTaken + " / 4 Taken"
                color: root.totalTaken === 4 ? Color.accent : (root.alertDue ? Color.urgent : root.panelFg)
                font.family: root.monoFam
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }

          PanelSeparator { foreground: root.panelFg }

          // 2. Schedule Legend Header
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "Pill 1 (Before 5 PM)"
              color: root.activeWindow === "pill1" ? Color.urgent : Qt.darker(root.panelFg, 1.5)
              font.family: root.fontFam
              font.pixelSize: Style.font.caption
              font.bold: true
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              text: "Pill 2 (5 PM – 5 AM)"
              color: root.activeWindow === "pill2" ? Color.urgent : Qt.darker(root.panelFg, 1.5)
              font.family: root.fontFam
              font.pixelSize: Style.font.caption
              font.bold: true
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
            }
          }

          // 3. 2x2 PILL GRID (EXACT ORDER: Magnesium 1 next to Magnesium 2, below it B12 1 next to B12 2)
          Column {
            id: pillsGrid
            width: parent.width
            spacing: Style.space(10)

            // ROW 1: MAGNESIUM
            RowLayout {
              width: parent.width
              spacing: Style.space(10)

              // Cell 1: Magnesium 1
              Rectangle {
                id: cardMag1
                Layout.fillWidth: true
                height: Style.space(68)
                radius: Style.space(12)

                // Fill color from RED to BLUE per pill name
                color: root.mag1
                  ? "#2563eb"
                  : Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.16)
                border.color: root.mag1 ? "#60a5fa" : Color.urgent
                border.width: 1.5

                RowLayout {
                  anchors.fill: parent
                  anchors.margins: Style.space(10)
                  spacing: Style.space(10)

                  Text {
                    text: root.mag1 ? "✓" : "💊"
                    color: root.mag1 ? "#ffffff" : Color.urgent
                    font.family: root.fontFam
                    font.pixelSize: Style.space(24)
                    font.bold: true
                    Layout.alignment: Qt.AlignVCenter
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(2)
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                      text: "Magnesium 1"
                      color: root.mag1 ? "#ffffff" : root.panelFg
                      font.family: root.fontFam
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }

                    Text {
                      text: root.mag1 ? "Taken · 2x Click Undo" : "Due before 5 PM · Click"
                      color: root.mag1 ? "#dbeafe" : Color.urgent
                      font.family: root.fontFam
                      font.pixelSize: Style.font.caption
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (!root.mag1) {
                      root.setPill("mag1", true)
                    }
                  }
                  onDoubleClicked: {
                    if (root.mag1) {
                      root.setPill("mag1", false)
                    }
                  }
                }
              }

              // Cell 2: Magnesium 2
              Rectangle {
                id: cardMag2
                Layout.fillWidth: true
                height: Style.space(68)
                radius: Style.space(12)

                color: root.mag2
                  ? "#2563eb"
                  : Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.16)
                border.color: root.mag2 ? "#60a5fa" : Color.urgent
                border.width: 1.5

                RowLayout {
                  anchors.fill: parent
                  anchors.margins: Style.space(10)
                  spacing: Style.space(10)

                  Text {
                    text: root.mag2 ? "✓" : "💊"
                    color: root.mag2 ? "#ffffff" : Color.urgent
                    font.family: root.fontFam
                    font.pixelSize: Style.space(24)
                    font.bold: true
                    Layout.alignment: Qt.AlignVCenter
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(2)
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                      text: "Magnesium 2"
                      color: root.mag2 ? "#ffffff" : root.panelFg
                      font.family: root.fontFam
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }

                    Text {
                      text: root.mag2 ? "Taken · 2x Click Undo" : "Due 5 PM - 5 AM · Click"
                      color: root.mag2 ? "#dbeafe" : Color.urgent
                      font.family: root.fontFam
                      font.pixelSize: Style.font.caption
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (!root.mag2) {
                      root.setPill("mag2", true)
                    }
                  }
                  onDoubleClicked: {
                    if (root.mag2) {
                      root.setPill("mag2", false)
                    }
                  }
                }
              }
            }

            // ROW 2: B12
            RowLayout {
              width: parent.width
              spacing: Style.space(10)

              // Cell 3: B12 1
              Rectangle {
                id: cardB12_1
                Layout.fillWidth: true
                height: Style.space(68)
                radius: Style.space(12)

                color: root.b12_1
                  ? "#2563eb"
                  : Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.16)
                border.color: root.b12_1 ? "#60a5fa" : Color.urgent
                border.width: 1.5

                RowLayout {
                  anchors.fill: parent
                  anchors.margins: Style.space(10)
                  spacing: Style.space(10)

                  Text {
                    text: root.b12_1 ? "✓" : "💊"
                    color: root.b12_1 ? "#ffffff" : Color.urgent
                    font.family: root.fontFam
                    font.pixelSize: Style.space(24)
                    font.bold: true
                    Layout.alignment: Qt.AlignVCenter
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(2)
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                      text: "B12 1"
                      color: root.b12_1 ? "#ffffff" : root.panelFg
                      font.family: root.fontFam
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }

                    Text {
                      text: root.b12_1 ? "Taken · 2x Click Undo" : "Due before 5 PM · Click"
                      color: root.b12_1 ? "#dbeafe" : Color.urgent
                      font.family: root.fontFam
                      font.pixelSize: Style.font.caption
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (!root.b12_1) {
                      root.setPill("b12_1", true)
                    }
                  }
                  onDoubleClicked: {
                    if (root.b12_1) {
                      root.setPill("b12_1", false)
                    }
                  }
                }
              }

              // Cell 4: B12 2
              Rectangle {
                id: cardB12_2
                Layout.fillWidth: true
                height: Style.space(68)
                radius: Style.space(12)

                color: root.b12_2
                  ? "#2563eb"
                  : Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.16)
                border.color: root.b12_2 ? "#60a5fa" : Color.urgent
                border.width: 1.5

                RowLayout {
                  anchors.fill: parent
                  anchors.margins: Style.space(10)
                  spacing: Style.space(10)

                  Text {
                    text: root.b12_2 ? "✓" : "💊"
                    color: root.b12_2 ? "#ffffff" : Color.urgent
                    font.family: root.fontFam
                    font.pixelSize: Style.space(24)
                    font.bold: true
                    Layout.alignment: Qt.AlignVCenter
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(2)
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                      text: "B12 2"
                      color: root.b12_2 ? "#ffffff" : root.panelFg
                      font.family: root.fontFam
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }

                    Text {
                      text: root.b12_2 ? "Taken · 2x Click Undo" : "Due 5 PM - 5 AM · Click"
                      color: root.b12_2 ? "#dbeafe" : Color.urgent
                      font.family: root.fontFam
                      font.pixelSize: Style.font.caption
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (!root.b12_2) {
                      root.setPill("b12_2", true)
                    }
                  }
                  onDoubleClicked: {
                    if (root.b12_2) {
                      root.setPill("b12_2", false)
                    }
                  }
                }
              }
            }
          }

          // 4. Action / Instruction Footer
          Rectangle {
            width: parent.width
            height: Style.space(38)
            radius: Style.space(8)
            color: Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, 0.05)
            border.color: Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, 0.12)
            border.width: 1

            RowLayout {
              anchors.centerIn: parent
              spacing: Style.space(8)

              Text {
                text: "💡 Single click to fill BLUE (mark taken) · Double click to revert RED (undo)"
                color: Qt.darker(root.panelFg, 1.4)
                font.family: root.fontFam
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }
}
