import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "rustam.resources"

  // CRITICAL: Expose implicitWidth/Height to bar container so the widget renders on the bar
  implicitWidth: barContent.implicitWidth
  implicitHeight: barContent.implicitHeight

  // System statistics
  property real cpuPercent: 0.0
  property real ramUsedGb: 0.0
  property real ramTotalGb: 0.0
  property real ramPercent: 0.0
  property real swapUsedGb: 0.0
  property real swapTotalGb: 0.0
  property real swapPercent: 0.0
  property string ramBarStr: "0G / 0G"

  property real diskUsedGb: 0.0
  property real diskTotalGb: 0.0
  property real diskPercent: 0.0

  property string ioRate: "0 B/s"
  property string ioShort: "0B"

  property string netUpRate: "0 B/s"
  property string netDownRate: "0 B/s"
  property string netUpShort: "0B"
  property string netDownShort: "0B"
  property string netTodayStr: "0 B"
  property string netMonthStr: "0 B"

  property real tempC: 0.0
  property string loadAvg: "0.00 0.00 0.00"

  // Process lists
  property var procsCpu: []
  property var procsMem: []
  property var procsIo: []
  property var procsNet: []
  property var procsAll: []

  // Dynamic bar open panel indicator width: spans the entire widget ONLY when overview is open
  readonly property real openPanelIndicatorWidth: overviewOpen ? root.width : 0

  // Dedicated Popup States
  property bool cpuOpen: false
  property bool ramOpen: false
  property bool ioOpen: false
  property bool netOpen: false
  property bool overviewOpen: false

  // Selected item index for keyboard navigation
  property int selectedIndex: 0

  // Kill confirmation state
  property int killConfirmPid: -1
  property string killConfirmName: ""

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color bg: bar ? bar.background : Color.background
  readonly property color panelFg: Color.popups.text
  readonly property string fontFam: bar ? bar.fontFamily : Style.font.family
  readonly property string monoFam: "monospace"
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/+$/, "")

  function close() {
    closeAll()
  }

  function closeAll() {
    cpuOpen = false
    ramOpen = false
    ioOpen = false
    netOpen = false
    overviewOpen = false
    killConfirmPid = -1
    selectedIndex = 0
  }

  function toggleCpu() {
    var next = !cpuOpen
    closeAll()
    cpuOpen = next
  }

  function toggleRam() {
    var next = !ramOpen
    closeAll()
    ramOpen = next
  }

  function toggleIo() {
    var next = !ioOpen
    closeAll()
    ioOpen = next
  }

  function toggleNet() {
    var next = !netOpen
    closeAll()
    netOpen = next
  }

  function toggleOverview() {
    var next = !overviewOpen
    closeAll()
    overviewOpen = next
  }

  function promptKill(pid, name) {
    if (pid <= 1) return
    killConfirmPid = pid
    killConfirmName = name
  }

  function killProcess(pid, name) {
    if (pid <= 1) return
    killProcessCmd.command = [root.pluginDir + "/res_stats", "kill", String(pid), "9"]
    killProcessCmd.running = true
    killConfirmPid = -1
    statsTimer.restart()
  }

  Process {
    id: killProcessCmd
    running: false
  }

  // Periodic polling process
  Process {
    id: statsProc
    command: [root.pluginDir + "/res_stats"]
    running: false

    stdout: SplitParser {
      onRead: function(data) {
        if (!data || data.length === 0) return
        try {
          var parsed = JSON.parse(data)
          if (parsed.cpu !== undefined) root.cpuPercent = parsed.cpu
          if (parsed.mem) {
            root.ramUsedGb = parsed.mem.used_gb || 0
            root.ramTotalGb = parsed.mem.total_gb || 0
            root.ramPercent = parsed.mem.pct || 0
            root.swapUsedGb = parsed.mem.swap_used_gb || 0
            root.swapTotalGb = parsed.mem.swap_total_gb || 0
            root.swapPercent = parsed.mem.swap_pct || 0
            root.ramBarStr = parsed.mem.bar_str || (root.ramUsedGb.toFixed(1) + "G / " + root.ramTotalGb.toFixed(1) + "G")
          }
          if (parsed.disk) {
            root.diskUsedGb = parsed.disk.used_gb || 0
            root.diskTotalGb = parsed.disk.total_gb || 0
            root.diskPercent = parsed.disk.pct || 0
          }
          if (parsed.io) {
            root.ioRate = parsed.io.rate || "0 B/s"
            root.ioShort = parsed.io.short || "0B"
          }
          if (parsed.net) {
            root.netUpRate = parsed.net.up_rate || "0 B/s"
            root.netDownRate = parsed.net.down_rate || "0 B/s"
            root.netUpShort = parsed.net.up_short || "0B"
            root.netDownShort = parsed.net.down_short || "0B"
            root.netTodayStr = parsed.net.today_str || "0 B"
            root.netMonthStr = parsed.net.month_str || "0 B"
          }
          if (parsed.temp !== undefined) root.tempC = parsed.temp
          if (parsed.load !== undefined) root.loadAvg = parsed.load

          if (parsed.procs_cpu) root.procsCpu = parsed.procs_cpu
          if (parsed.procs_mem) root.procsMem = parsed.procs_mem
          if (parsed.procs_io) root.procsIo = parsed.procs_io
          if (parsed.procs_net) root.procsNet = parsed.procs_net
          if (parsed.procs_all) root.procsAll = parsed.procs_all
        } catch (e) {}
      }
    }
  }

  Timer {
    id: statsTimer
    interval: 1800
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!statsProc.running) statsProc.running = true
    }
  }

  // ==================== TOP BAR METRICS ROW ====================
  Row {
    id: barContent
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    // 1. CPU Pill
    Rectangle {
      id: cpuBtn
      function close() { root.cpuOpen = false }
      height: Style.space(26)
      implicitWidth: cpuInner.implicitWidth + Style.space(8)
      width: implicitWidth
      radius: Style.space(6)
      color: root.cpuOpen
        ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
        : (cpuMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12) : "transparent")
      border.color: root.cpuOpen ? Color.accent : "transparent"
      border.width: 1

      Row {
        id: cpuInner
        anchors.centerIn: parent
        spacing: Style.space(3)
        Text {
          text: ""
          color: root.cpuPercent > 80 ? Color.urgent : (root.cpuOpen ? Color.accent : root.fg)
          font.family: root.fontFam
          font.pixelSize: Style.font.bodySmall
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          textFormat: Text.PlainText
          text: Math.round(root.cpuPercent) + "%"
          color: root.fg
          font.family: root.fontFam
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Rectangle {
        visible: root.cpuOpen
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(Style.space(14), parent.width - Style.space(6))
        height: Style.space(2)
        radius: Style.space(1)
        color: Color.accent
      }

      MouseArea {
        id: cpuMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.toggleOverview()
          else root.toggleCpu()
        }
      }
    }

    // 2. RAM Pill (IN GB)
    Rectangle {
      id: ramBtn
      function close() { root.ramOpen = false }
      height: Style.space(26)
      implicitWidth: ramInner.implicitWidth + Style.space(8)
      width: implicitWidth
      radius: Style.space(6)
      color: root.ramOpen
        ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
        : (ramMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12) : "transparent")
      border.color: root.ramOpen ? Color.accent : "transparent"
      border.width: 1

      Row {
        id: ramInner
        anchors.centerIn: parent
        spacing: Style.space(3)
        Text {
          text: ""
          color: root.ramPercent > 85 ? Color.urgent : (root.ramOpen ? Color.accent : root.fg)
          font.family: root.fontFam
          font.pixelSize: Style.font.bodySmall
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          textFormat: Text.PlainText
          text: root.ramUsedGb.toFixed(1) + "G"
          color: root.fg
          font.family: root.fontFam
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Rectangle {
        visible: root.ramOpen
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(Style.space(14), parent.width - Style.space(6))
        height: Style.space(2)
        radius: Style.space(1)
        color: Color.accent
      }

      MouseArea {
        id: ramMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.toggleOverview()
          else root.toggleRam()
        }
      }
    }

    // 3. Disk I/O Pill
    Rectangle {
      id: ioBtn
      function close() { root.ioOpen = false }
      height: Style.space(26)
      implicitWidth: ioInner.implicitWidth + Style.space(8)
      width: implicitWidth
      radius: Style.space(6)
      color: root.ioOpen
        ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
        : (ioMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12) : "transparent")
      border.color: root.ioOpen ? Color.accent : "transparent"
      border.width: 1

      Row {
        id: ioInner
        anchors.centerIn: parent
        spacing: Style.space(3)
        Text {
          text: "󰛄"
          color: root.ioOpen ? Color.accent : root.fg
          font.family: root.fontFam
          font.pixelSize: Style.font.bodySmall
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          textFormat: Text.PlainText
          text: root.ioRate
          color: root.fg
          font.family: root.fontFam
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Rectangle {
        visible: root.ioOpen
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(Style.space(14), parent.width - Style.space(6))
        height: Style.space(2)
        radius: Style.space(1)
        color: Color.accent
      }

      MouseArea {
        id: ioMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.toggleOverview()
          else root.toggleIo()
        }
      }
    }

    // 4. Storage Capacity Pill (Shows % only, click does NOT open panel)
    Rectangle {
      id: diskBtn
      height: Style.space(26)
      implicitWidth: diskInner.implicitWidth + Style.space(8)
      width: implicitWidth
      radius: Style.space(6)
      color: diskMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08) : "transparent"

      Row {
        id: diskInner
        anchors.centerIn: parent
        spacing: Style.space(3)
        Text {
          text: "󰋊"
          color: root.diskPercent > 90 ? Color.urgent : root.fg
          font.family: root.fontFam
          font.pixelSize: Style.font.bodySmall
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          textFormat: Text.PlainText
          text: Math.round(root.diskPercent) + "%"
          color: root.fg
          font.family: root.fontFam
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      MouseArea {
        id: diskMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.ArrowCursor
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.toggleOverview()
        }
      }
    }

    // 5. Network Pill (UP ARROW + DOWN ARROW)
    Rectangle {
      id: netBtn
      function close() { root.netOpen = false }
      height: Style.space(26)
      implicitWidth: netInner.implicitWidth + Style.space(8)
      width: implicitWidth
      radius: Style.space(6)
      color: root.netOpen
        ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
        : (netMouse.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12) : "transparent")
      border.color: root.netOpen ? Color.accent : "transparent"
      border.width: 1

      Row {
        id: netInner
        anchors.centerIn: parent
        spacing: Style.space(4)
        Text {
          text: ""
          color: Color.accent
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          textFormat: Text.PlainText
          text: root.netDownShort
          color: root.fg
          font.family: root.fontFam
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          text: ""
          color: Color.accent
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          textFormat: Text.PlainText
          text: root.netUpShort
          color: root.fg
          font.family: root.fontFam
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Rectangle {
        visible: root.netOpen
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(Style.space(16), parent.width - Style.space(8))
        height: Style.space(2)
        radius: Style.space(1)
        color: Color.accent
      }

      MouseArea {
        id: netMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.toggleOverview()
          else root.toggleNet()
        }
      }
    }
  }

  // =========================================================================
  // POPUP 1: DEDICATED CPU PANEL (100% RELATIVE LAYOUT, BTOP STYLE)
  // =========================================================================
  KeyboardPanel {
    id: cpuPanel
    anchorItem: cpuBtn
    owner: cpuBtn
    bar: root.bar
    open: root.cpuOpen
    onOpenChanged: if (!open && root.cpuOpen) root.cpuOpen = false
    focusTarget: cpuKeyCatcher
    contentWidth: {
      var desired = Style.space(520)
      if (cpuCol && cpuCol.implicitWidth > 0) {
        desired = Math.max(desired, cpuCol.implicitWidth + Style.space(24))
      }
      return cpuPanel.fittedContentWidth(desired)
    }
    contentHeight: {
      var maxAvailable = cpuPanel.availableCardHeight > 0
        ? Math.min(Style.space(520), cpuPanel.availableCardHeight)
        : Style.space(520)
      return cpuPanel.fittedContentHeight(cpuCol.implicitHeight, maxAvailable)
    }

    PanelKeyCatcher {
      id: cpuKeyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy > 0 && root.selectedIndex < root.procsCpu.length - 1) root.selectedIndex++
        else if (dy < 0 && root.selectedIndex > 0) root.selectedIndex--
      }
      onDeleteRequested: {
        if (root.selectedIndex >= 0 && root.selectedIndex < root.procsCpu.length) {
          root.promptKill(root.procsCpu[root.selectedIndex].pid, root.procsCpu[root.selectedIndex].name)
        }
      }
      onTextKey: function(t) {
        if (t === "x" || t === "k" || t === "X" || t === "K") {
          if (root.selectedIndex >= 0 && root.selectedIndex < root.procsCpu.length) {
            root.promptKill(root.procsCpu[root.selectedIndex].pid, root.procsCpu[root.selectedIndex].name)
          }
        }
      }
      onReturnRequested: {
        if (root.killConfirmPid !== -1) root.killProcess(root.killConfirmPid, root.killConfirmName)
      }
      onCloseRequested: root.closeAll()

      Flickable {
        id: cpuFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: cpuCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: cpuCol
          width: cpuFlick.width
          spacing: Style.space(12)

        // Btop Box Header
        RowLayout {
          width: parent.width
          Text {
            text: " CPU Processor"
            color: root.panelFg
            font.family: root.fontFam
            font.pixelSize: Style.font.body
            font.bold: true
            Layout.fillWidth: true
          }
          Text {
            text: root.cpuPercent.toFixed(1) + "%"
            color: root.cpuPercent > 80 ? Color.urgent : Color.accent
            font.family: root.fontFam
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }

        // Horizontal Btop Meter Bar
        Rectangle {
          width: parent.width
          height: Style.space(8)
          radius: Style.space(4)
          color: Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, 0.12)
          Rectangle {
            height: parent.height
            width: Math.min(parent.width, Math.max(0, parent.width * (root.cpuPercent / 100.0)))
            radius: Style.space(4)
            color: root.cpuPercent > 80 ? Color.urgent : Color.accent
          }
        }

        // Sub-stat metadata
        Row {
          width: parent.width
          spacing: Style.space(12)
          Text { text: "Temp: " + root.tempC.toFixed(0) + "°C"; color: Qt.darker(root.panelFg, 1.4); font.family: root.fontFam; font.pixelSize: Style.font.caption }
          Text { text: "•"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption }
          Text { text: "Load: " + root.loadAvg; color: Qt.darker(root.panelFg, 1.4); font.family: root.fontFam; font.pixelSize: Style.font.caption }
        }

        // Kill Banner
        Rectangle {
          visible: root.killConfirmPid !== -1
          width: parent.width
          height: Style.space(38)
          radius: Style.space(6)
          color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.18)
          border.color: Color.urgent
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            Text {
              text: "Kill " + root.killConfirmName + " (" + root.killConfirmPid + ")?"
              color: Color.urgent
              font.family: root.fontFam
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              Layout.fillWidth: true
              elide: Text.ElideRight
            }
            Button {
              text: "Kill (Enter)"
              foreground: Color.urgent
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: root.killProcess(root.killConfirmPid, root.killConfirmName)
            }
            Button {
              text: "Cancel"
              foreground: root.panelFg
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: root.killConfirmPid = -1
            }
          }
        }

        PanelSeparator { foreground: root.panelFg }

        // Table Header (Relative RowLayout)
        RowLayout {
          width: parent.width
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text { text: "PID"; color: Qt.darker(root.panelFg, 1.6); font.family: root.monoFam; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(52) }
          Text { text: "PROGRAM"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption; font.bold: true; Layout.fillWidth: true }
          Text { text: "CPU %"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption; font.bold: true; Layout.preferredWidth: Style.space(65); horizontalAlignment: Text.AlignRight }
          Text { text: "ACT"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(44); horizontalAlignment: Text.AlignRight }
        }

        // Process List (Relative RowLayout)
        Column {
          width: parent.width
          spacing: Style.space(3)

          Repeater {
            model: root.procsCpu

            Rectangle {
              id: cpuRowItem
              required property var modelData
              required property int index
              width: parent.width
              height: Style.space(28)
              radius: Style.space(6)
              color: root.selectedIndex === cpuRowItem.index
                ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
                : (cpuRowMouse.containsMouse ? Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, 0.08) : "transparent")

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Text { text: String(cpuRowItem.modelData.pid); color: Qt.darker(root.panelFg, 1.6); font.family: root.monoFam; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(52); Layout.alignment: Qt.AlignVCenter }
                Text { textFormat: Text.PlainText; text: cpuRowItem.modelData.name || ""; color: root.panelFg; font.family: root.fontFam; font.pixelSize: Style.font.bodySmall; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
                Text { text: (Number(cpuRowItem.modelData.cpu) || 0).toFixed(1) + "%"; color: Color.accent; font.family: root.monoFam; font.pixelSize: Style.font.bodySmall; font.bold: true; Layout.preferredWidth: Style.space(65); horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter }

                Button {
                  text: "Kill"
                  foreground: Color.urgent
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(2)
                  Layout.preferredWidth: Style.space(44)
                  Layout.alignment: Qt.AlignVCenter
                  onClicked: root.promptKill(cpuRowItem.modelData.pid, cpuRowItem.modelData.name)
                }
              }

              MouseArea {
                id: cpuRowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectedIndex = cpuRowItem.index
                onDoubleClicked: root.promptKill(cpuRowItem.modelData.pid, cpuRowItem.modelData.name)
              }
            }
          }
        }

        // Footer hint
        Text {
          text: "↑↓: Select  •  x / k: Kill  •  Esc: Close"
          color: Qt.darker(root.panelFg, 1.8)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }
    }
  }
}

  // =========================================================================
  // POPUP 2: DEDICATED RAM PANEL (100% RELATIVE LAYOUT, IN GB)
  // =========================================================================
  KeyboardPanel {
    id: ramPanel
    anchorItem: ramBtn
    owner: ramBtn
    bar: root.bar
    open: root.ramOpen
    onOpenChanged: if (!open && root.ramOpen) root.ramOpen = false
    focusTarget: ramKeyCatcher
    contentWidth: {
      var desired = Style.space(520)
      if (ramCol && ramCol.implicitWidth > 0) {
        desired = Math.max(desired, ramCol.implicitWidth + Style.space(24))
      }
      return ramPanel.fittedContentWidth(desired)
    }
    contentHeight: {
      var maxAvailable = ramPanel.availableCardHeight > 0
        ? Math.min(Style.space(520), ramPanel.availableCardHeight)
        : Style.space(520)
      return ramPanel.fittedContentHeight(ramCol.implicitHeight, maxAvailable)
    }

    PanelKeyCatcher {
      id: ramKeyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy > 0 && root.selectedIndex < root.procsMem.length - 1) root.selectedIndex++
        else if (dy < 0 && root.selectedIndex > 0) root.selectedIndex--
      }
      onDeleteRequested: {
        if (root.selectedIndex >= 0 && root.selectedIndex < root.procsMem.length) {
          root.promptKill(root.procsMem[root.selectedIndex].pid, root.procsMem[root.selectedIndex].name)
        }
      }
      onTextKey: function(t) {
        if (t === "x" || t === "k" || t === "X" || t === "K") {
          if (root.selectedIndex >= 0 && root.selectedIndex < root.procsMem.length) {
            root.promptKill(root.procsMem[root.selectedIndex].pid, root.procsMem[root.selectedIndex].name)
          }
        }
      }
      onReturnRequested: {
        if (root.killConfirmPid !== -1) root.killProcess(root.killConfirmPid, root.killConfirmName)
      }
      onCloseRequested: root.closeAll()

      Flickable {
        id: ramFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: ramCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: ramCol
          width: ramFlick.width
          spacing: Style.space(12)

        // Btop Box Header
        RowLayout {
          width: parent.width
          Text {
            text: " Memory (RAM)"
            color: root.panelFg
            font.family: root.fontFam
            font.pixelSize: Style.font.body
            font.bold: true
            Layout.fillWidth: true
          }
          Text {
            text: root.ramUsedGb.toFixed(2) + " GB / " + root.ramTotalGb.toFixed(2) + " GB (" + Math.round(root.ramPercent) + "%)"
            color: root.ramPercent > 85 ? Color.urgent : Color.accent
            font.family: root.fontFam
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
        }

        // Horizontal Btop Meter Bar (RAM)
        Rectangle {
          width: parent.width
          height: Style.space(8)
          radius: Style.space(4)
          color: Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, 0.12)
          Rectangle {
            height: parent.height
            width: Math.min(parent.width, Math.max(0, parent.width * (root.ramPercent / 100.0)))
            radius: Style.space(4)
            color: root.ramPercent > 85 ? Color.urgent : Color.accent
          }
        }

        // Swap Meter
        Row {
          width: parent.width
          spacing: Style.space(8)
          Text { text: "Swap: " + root.swapUsedGb.toFixed(2) + " GB / " + root.swapTotalGb.toFixed(2) + " GB (" + Math.round(root.swapPercent) + "%)"; color: Qt.darker(root.panelFg, 1.4); font.family: root.fontFam; font.pixelSize: Style.font.caption }
        }

        // Kill Banner
        Rectangle {
          visible: root.killConfirmPid !== -1
          width: parent.width
          height: Style.space(38)
          radius: Style.space(6)
          color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.18)
          border.color: Color.urgent
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            Text {
              text: "Kill " + root.killConfirmName + " (" + root.killConfirmPid + ")?"
              color: Color.urgent
              font.family: root.fontFam
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              Layout.fillWidth: true
              elide: Text.ElideRight
            }
            Button {
              text: "Kill (Enter)"
              foreground: Color.urgent
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: root.killProcess(root.killConfirmPid, root.killConfirmName)
            }
            Button {
              text: "Cancel"
              foreground: root.panelFg
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: root.killConfirmPid = -1
            }
          }
        }

        PanelSeparator { foreground: root.panelFg }

        // Table Header
        RowLayout {
          width: parent.width
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text { text: "PID"; color: Qt.darker(root.panelFg, 1.6); font.family: root.monoFam; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(52) }
          Text { text: "PROGRAM"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption; font.bold: true; Layout.fillWidth: true }
          Text { text: "USAGE"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption; font.bold: true; Layout.preferredWidth: Style.space(85); horizontalAlignment: Text.AlignRight }
          Text { text: "ACT"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(44); horizontalAlignment: Text.AlignRight }
        }

        // Process List
        Column {
          width: parent.width
          spacing: Style.space(3)

          Repeater {
            model: root.procsMem

            Rectangle {
              id: memRowItem
              required property var modelData
              required property int index
              width: parent.width
              height: Style.space(28)
              radius: Style.space(6)
              color: root.selectedIndex === memRowItem.index
                ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
                : (memRowMouse.containsMouse ? Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, 0.08) : "transparent")

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Text { text: String(memRowItem.modelData.pid); color: Qt.darker(root.panelFg, 1.6); font.family: root.monoFam; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(52); Layout.alignment: Qt.AlignVCenter }
                Text { textFormat: Text.PlainText; text: memRowItem.modelData.name || ""; color: root.panelFg; font.family: root.fontFam; font.pixelSize: Style.font.bodySmall; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
                Text { text: memRowItem.modelData.mem_str || ((Number(memRowItem.modelData.mem) || 0).toFixed(1) + "%"); color: Color.accent; font.family: root.monoFam; font.pixelSize: Style.font.bodySmall; font.bold: true; Layout.preferredWidth: Style.space(85); horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter }

                Button {
                  text: "Kill"
                  foreground: Color.urgent
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(2)
                  Layout.preferredWidth: Style.space(44)
                  Layout.alignment: Qt.AlignVCenter
                  onClicked: root.promptKill(memRowItem.modelData.pid, memRowItem.modelData.name)
                }
              }

              MouseArea {
                id: memRowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectedIndex = memRowItem.index
                onDoubleClicked: root.promptKill(memRowItem.modelData.pid, memRowItem.modelData.name)
              }
            }
          }
        }

        // Footer hint
        Text {
          text: "↑↓: Select  •  x / k: Kill  •  Esc: Close"
          color: Qt.darker(root.panelFg, 1.8)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }
    }
  }
}

  // =========================================================================
  // POPUP 3: DEDICATED DISK I/O PANEL (100% RELATIVE LAYOUT, BTOP STYLE)
  // =========================================================================
  KeyboardPanel {
    id: ioPanel
    anchorItem: ioBtn
    owner: ioBtn
    bar: root.bar
    open: root.ioOpen
    onOpenChanged: if (!open && root.ioOpen) root.ioOpen = false
    focusTarget: ioKeyCatcher
    contentWidth: {
      var desired = Style.space(520)
      if (ioCol && ioCol.implicitWidth > 0) {
        desired = Math.max(desired, ioCol.implicitWidth + Style.space(24))
      }
      return ioPanel.fittedContentWidth(desired)
    }
    contentHeight: {
      var maxAvailable = ioPanel.availableCardHeight > 0
        ? Math.min(Style.space(520), ioPanel.availableCardHeight)
        : Style.space(520)
      return ioPanel.fittedContentHeight(ioCol.implicitHeight, maxAvailable)
    }

    PanelKeyCatcher {
      id: ioKeyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy > 0 && root.selectedIndex < root.procsIo.length - 1) root.selectedIndex++
        else if (dy < 0 && root.selectedIndex > 0) root.selectedIndex--
      }
      onDeleteRequested: {
        if (root.selectedIndex >= 0 && root.selectedIndex < root.procsIo.length) {
          root.promptKill(root.procsIo[root.selectedIndex].pid, root.procsIo[root.selectedIndex].name)
        }
      }
      onTextKey: function(t) {
        if (t === "x" || t === "k" || t === "X" || t === "K") {
          if (root.selectedIndex >= 0 && root.selectedIndex < root.procsIo.length) {
            root.promptKill(root.procsIo[root.selectedIndex].pid, root.procsIo[root.selectedIndex].name)
          }
        }
      }
      onReturnRequested: {
        if (root.killConfirmPid !== -1) root.killProcess(root.killConfirmPid, root.killConfirmName)
      }
      onCloseRequested: root.closeAll()

      Flickable {
        id: ioFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: ioCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: ioCol
          width: ioFlick.width
          spacing: Style.space(12)

        // Btop Box Header
        RowLayout {
          width: parent.width
          Text {
            text: "󰛄 Disk I/O Activity"
            color: root.panelFg
            font.family: root.fontFam
            font.pixelSize: Style.font.body
            font.bold: true
            Layout.fillWidth: true
          }
          Text {
            text: root.ioRate
            color: Color.accent
            font.family: root.fontFam
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)
          Text {
            text: "Root Partition: " + root.diskUsedGb.toFixed(1) + " GB / " + root.diskTotalGb.toFixed(1) + " GB (" + Math.round(root.diskPercent) + "%)"
            color: Qt.darker(root.panelFg, 1.4)
            font.family: root.fontFam
            font.pixelSize: Style.font.caption
          }
        }

        // Kill Banner
        Rectangle {
          visible: root.killConfirmPid !== -1
          width: parent.width
          height: Style.space(38)
          radius: Style.space(6)
          color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.18)
          border.color: Color.urgent
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            Text {
              text: "Kill " + root.killConfirmName + " (" + root.killConfirmPid + ")?"
              color: Color.urgent
              font.family: root.fontFam
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              Layout.fillWidth: true
              elide: Text.ElideRight
            }
            Button {
              text: "Kill (Enter)"
              foreground: Color.urgent
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: root.killProcess(root.killConfirmPid, root.killConfirmName)
            }
            Button {
              text: "Cancel"
              foreground: root.panelFg
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: root.killConfirmPid = -1
            }
          }
        }

        PanelSeparator { foreground: root.panelFg }

        // Table Header
        RowLayout {
          width: parent.width
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text { text: "PID"; color: Qt.darker(root.panelFg, 1.6); font.family: root.monoFam; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(52) }
          Text { text: "PROGRAM"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption; font.bold: true; Layout.fillWidth: true }
          Text { text: "I/O USAGE"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption; font.bold: true; Layout.preferredWidth: Style.space(85); horizontalAlignment: Text.AlignRight }
          Text { text: "ACT"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(44); horizontalAlignment: Text.AlignRight }
        }

        // Process List
        Column {
          width: parent.width
          spacing: Style.space(3)

          Repeater {
            model: root.procsIo.length > 0 ? root.procsIo : [{ pid: 0, name: "System Idle", extra: "0 B" }]

            Rectangle {
              id: ioRowItem
              required property var modelData
              required property int index
              width: parent.width
              height: Style.space(28)
              radius: Style.space(6)
              color: root.selectedIndex === ioRowItem.index
                ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
                : (ioRowMouse.containsMouse ? Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, 0.08) : "transparent")

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Text { text: String(ioRowItem.modelData.pid); color: Qt.darker(root.panelFg, 1.6); font.family: root.monoFam; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(52); Layout.alignment: Qt.AlignVCenter }
                Text { textFormat: Text.PlainText; text: ioRowItem.modelData.name || ""; color: root.panelFg; font.family: root.fontFam; font.pixelSize: Style.font.bodySmall; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
                Text { text: ioRowItem.modelData.extra || "active"; color: Color.accent; font.family: root.monoFam; font.pixelSize: Style.font.bodySmall; font.bold: true; Layout.preferredWidth: Style.space(85); horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter }

                Button {
                  visible: ioRowItem.modelData.pid > 0
                  text: "Kill"
                  foreground: Color.urgent
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(2)
                  Layout.preferredWidth: Style.space(44)
                  Layout.alignment: Qt.AlignVCenter
                  onClicked: root.promptKill(ioRowItem.modelData.pid, ioRowItem.modelData.name)
                }
              }

              MouseArea {
                id: ioRowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectedIndex = ioRowItem.index
                onDoubleClicked: root.promptKill(ioRowItem.modelData.pid, ioRowItem.modelData.name)
              }
            }
          }
        }

        // Footer hint
        Text {
          text: "↑↓: Select  •  x / k: Kill  •  Esc: Close"
          color: Qt.darker(root.panelFg, 1.8)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }
    }
  }
}

  // =========================================================================
  // POPUP 4: DEDICATED NETWORK PANEL (100% RELATIVE LAYOUT, BTOP STYLE)
  // =========================================================================
  KeyboardPanel {
    id: netPanel
    anchorItem: netBtn
    owner: netBtn
    bar: root.bar
    open: root.netOpen
    onOpenChanged: if (!open && root.netOpen) root.netOpen = false
    focusTarget: netKeyCatcher
    contentWidth: {
      var desired = Style.space(560)
      if (netCol && netCol.implicitWidth > 0) {
        desired = Math.max(desired, netCol.implicitWidth + Style.space(24))
      }
      return netPanel.fittedContentWidth(desired)
    }
    contentHeight: {
      var maxAvailable = netPanel.availableCardHeight > 0
        ? Math.min(Style.space(520), netPanel.availableCardHeight)
        : Style.space(520)
      return netPanel.fittedContentHeight(netCol.implicitHeight, maxAvailable)
    }

    PanelKeyCatcher {
      id: netKeyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy > 0 && root.selectedIndex < root.procsNet.length - 1) root.selectedIndex++
        else if (dy < 0 && root.selectedIndex > 0) root.selectedIndex--
      }
      onDeleteRequested: {
        if (root.selectedIndex >= 0 && root.selectedIndex < root.procsNet.length) {
          root.promptKill(root.procsNet[root.selectedIndex].pid, root.procsNet[root.selectedIndex].name)
        }
      }
      onTextKey: function(t) {
        if (t === "x" || t === "k" || t === "X" || t === "K") {
          if (root.selectedIndex >= 0 && root.selectedIndex < root.procsNet.length) {
            root.promptKill(root.procsNet[root.selectedIndex].pid, root.procsNet[root.selectedIndex].name)
          }
        }
      }
      onReturnRequested: {
        if (root.killConfirmPid !== -1) root.killProcess(root.killConfirmPid, root.killConfirmName)
      }
      onCloseRequested: root.closeAll()

      Flickable {
        id: netFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: netCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: netCol
          width: netFlick.width
          spacing: Style.space(12)

        // Btop Header
        RowLayout {
          width: parent.width
          Text {
            text: "󰈀 Network Bandwidth"
            color: root.panelFg
            font.family: root.fontFam
            font.pixelSize: Style.font.body
            font.bold: true
            Layout.fillWidth: true
          }
          Text {
            text: " " + root.netDownRate + "    " + root.netUpRate
            color: Color.accent
            font.family: root.fontFam
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
        }

        // Btop-Style Usage Stat Cards (Today & Month)
        RowLayout {
          width: parent.width
          spacing: Style.space(10)

          // Today Card
          Rectangle {
            Layout.fillWidth: true
            height: Style.space(52)
            radius: Style.space(8)
            color: Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, 0.08)
            border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.3)
            border.width: 1

            Column {
              anchors.centerIn: parent
              spacing: Style.space(2)
              Text { text: "Data Used Today"; color: Qt.darker(root.panelFg, 1.4); font.family: root.fontFam; font.pixelSize: Style.font.caption; anchors.horizontalCenter: parent.horizontalCenter }
              Text { text: root.netTodayStr; color: Color.accent; font.family: root.fontFam; font.pixelSize: Style.font.body; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
            }
          }

          // Month Card
          Rectangle {
            Layout.fillWidth: true
            height: Style.space(52)
            radius: Style.space(8)
            color: Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, 0.08)
            border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.3)
            border.width: 1

            Column {
              anchors.centerIn: parent
              spacing: Style.space(2)
              Text { text: "Data Used This Month"; color: Qt.darker(root.panelFg, 1.4); font.family: root.fontFam; font.pixelSize: Style.font.caption; anchors.horizontalCenter: parent.horizontalCenter }
              Text { text: root.netMonthStr; color: root.panelFg; font.family: root.fontFam; font.pixelSize: Style.font.body; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
            }
          }
        }

        // Kill Banner
        Rectangle {
          visible: root.killConfirmPid !== -1
          width: parent.width
          height: Style.space(38)
          radius: Style.space(6)
          color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.18)
          border.color: Color.urgent
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            Text {
              text: "Kill " + root.killConfirmName + " (" + root.killConfirmPid + ")?"
              color: Color.urgent
              font.family: root.fontFam
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              Layout.fillWidth: true
              elide: Text.ElideRight
            }
            Button {
              text: "Kill (Enter)"
              foreground: Color.urgent
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: root.killProcess(root.killConfirmPid, root.killConfirmName)
            }
            Button {
              text: "Cancel"
              foreground: root.panelFg
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: root.killConfirmPid = -1
            }
          }
        }

        PanelSeparator { foreground: root.panelFg }

        // Table Header (100% Relative Layout)
        RowLayout {
          width: parent.width
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text { text: "PID"; color: Qt.darker(root.panelFg, 1.6); font.family: root.monoFam; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(50) }
          Text { text: "APPLICATION"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption; font.bold: true; Layout.fillWidth: true }
          Text { text: "DOWN (▼)"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption; font.bold: true; Layout.preferredWidth: Style.space(80); horizontalAlignment: Text.AlignRight }
          Text { text: "UP (▲)"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption; font.bold: true; Layout.preferredWidth: Style.space(75); horizontalAlignment: Text.AlignRight }
          Text { text: "TOTAL"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption; font.bold: true; Layout.preferredWidth: Style.space(65); horizontalAlignment: Text.AlignRight }
          Text { text: "ACT"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(42); horizontalAlignment: Text.AlignRight }
        }

        // Process List (100% Relative Layout)
        Column {
          width: parent.width
          spacing: Style.space(3)

          Repeater {
            model: root.procsNet.length > 0 ? root.procsNet : [{ pid: 0, name: "No network data", upload: "0 B", download: "0 B", total: "0 B" }]

            Rectangle {
              id: netRowItem
              required property var modelData
              required property int index
              width: parent.width
              height: Style.space(28)
              radius: Style.space(6)
              color: root.selectedIndex === netRowItem.index
                ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
                : (netRowMouse.containsMouse ? Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, 0.08) : "transparent")

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Text { text: String(netRowItem.modelData.pid); color: Qt.darker(root.panelFg, 1.6); font.family: root.monoFam; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(50); Layout.alignment: Qt.AlignVCenter }
                Text { textFormat: Text.PlainText; text: netRowItem.modelData.name || ""; color: root.panelFg; font.family: root.fontFam; font.pixelSize: Style.font.bodySmall; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
                Text { text: netRowItem.modelData.download || "0 B"; color: Color.accent; font.family: root.monoFam; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(80); horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter }
                Text { text: netRowItem.modelData.upload || "0 B"; color: Color.accent; font.family: root.monoFam; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(75); horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter }
                Text { text: netRowItem.modelData.total || "0 B"; color: root.panelFg; font.family: root.monoFam; font.pixelSize: Style.font.caption; font.bold: true; Layout.preferredWidth: Style.space(65); horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter }

                Button {
                  visible: netRowItem.modelData.pid > 0
                  text: "Kill"
                  foreground: Color.urgent
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(2)
                  Layout.preferredWidth: Style.space(42)
                  Layout.alignment: Qt.AlignVCenter
                  onClicked: root.promptKill(netRowItem.modelData.pid, netRowItem.modelData.name)
                }
              }

              MouseArea {
                id: netRowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectedIndex = netRowItem.index
                onDoubleClicked: root.promptKill(netRowItem.modelData.pid, netRowItem.modelData.name)
              }
            }
          }
        }

        // Footer hint
        Text {
          text: "↑↓: Select  •  x / k: Kill  •  Esc: Close"
          color: Qt.darker(root.panelFg, 1.8)
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }
    }
  }
}

  // =========================================================================
  // POPUP 5: OVERVIEW PANEL (RIGHT-CLICK COLLECTIVE SUMMARY)
  // =========================================================================
  KeyboardPanel {
    id: overviewPanel
    anchorItem: barContent
    owner: root
    bar: root.bar
    open: root.overviewOpen
    onOpenChanged: if (!open && root.overviewOpen) root.overviewOpen = false
    focusTarget: overviewKeyCatcher
    contentWidth: {
      var desired = Style.space(580)
      if (overCol && overCol.implicitWidth > 0) {
        desired = Math.max(desired, overCol.implicitWidth + Style.space(24))
      }
      return overviewPanel.fittedContentWidth(desired)
    }
    contentHeight: {
      var maxAvailable = overviewPanel.availableCardHeight > 0
        ? Math.min(Style.space(540), overviewPanel.availableCardHeight)
        : Style.space(540)
      return overviewPanel.fittedContentHeight(overCol.implicitHeight, maxAvailable)
    }

    PanelKeyCatcher {
      id: overviewKeyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy > 0 && root.selectedIndex < root.procsAll.length - 1) root.selectedIndex++
        else if (dy < 0 && root.selectedIndex > 0) root.selectedIndex--
      }
      onDeleteRequested: {
        if (root.selectedIndex >= 0 && root.selectedIndex < root.procsAll.length) {
          root.promptKill(root.procsAll[root.selectedIndex].pid, root.procsAll[root.selectedIndex].name)
        }
      }
      onTextKey: function(t) {
        if (t === "x" || t === "k" || t === "X" || t === "K") {
          if (root.selectedIndex >= 0 && root.selectedIndex < root.procsAll.length) {
            root.promptKill(root.procsAll[root.selectedIndex].pid, root.procsAll[root.selectedIndex].name)
          }
        }
      }
      onReturnRequested: {
        if (root.killConfirmPid !== -1) root.killProcess(root.killConfirmPid, root.killConfirmName)
      }
      onCloseRequested: root.closeAll()

      Flickable {
        id: overFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: overCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: overCol
          width: overFlick.width
          spacing: Style.space(12)

        RowLayout {
          width: parent.width
          Text {
            text: "󰄛 System Resources Overview"
            color: root.panelFg
            font.family: root.fontFam
            font.pixelSize: Style.font.body
            font.bold: true
            Layout.fillWidth: true
          }
          Text {
            text: "Sorted: CPU ➜ RAM ➜ I/O"
            color: Color.accent
            font.family: root.fontFam
            font.pixelSize: Style.font.caption
          }
        }

        // Summary Metric Cards
        RowLayout {
          width: parent.width
          spacing: Style.space(8)
          Rectangle {
            Layout.fillWidth: true
            height: Style.space(42)
            radius: Style.space(6)
            color: Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, 0.08)
            Column {
              anchors.centerIn: parent
              Text { text: "CPU Load"; color: Qt.darker(root.panelFg, 1.4); font.family: root.fontFam; font.pixelSize: Style.font.caption; anchors.horizontalCenter: parent.horizontalCenter }
              Text { text: root.cpuPercent.toFixed(1) + "%"; color: Color.accent; font.family: root.fontFam; font.pixelSize: Style.font.bodySmall; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
            }
          }
          Rectangle {
            Layout.fillWidth: true
            height: Style.space(42)
            radius: Style.space(6)
            color: Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, 0.08)
            Column {
              anchors.centerIn: parent
              Text { text: "RAM"; color: Qt.darker(root.panelFg, 1.4); font.family: root.fontFam; font.pixelSize: Style.font.caption; anchors.horizontalCenter: parent.horizontalCenter }
              Text { text: root.ramBarStr; color: Color.accent; font.family: root.fontFam; font.pixelSize: Style.font.bodySmall; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
            }
          }
          Rectangle {
            Layout.fillWidth: true
            height: Style.space(42)
            radius: Style.space(6)
            color: Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, 0.08)
            Column {
              anchors.centerIn: parent
              Text { text: "Disk I/O"; color: Qt.darker(root.panelFg, 1.4); font.family: root.fontFam; font.pixelSize: Style.font.caption; anchors.horizontalCenter: parent.horizontalCenter }
              Text { text: root.ioRate; color: Color.accent; font.family: root.fontFam; font.pixelSize: Style.font.bodySmall; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
            }
          }
          Rectangle {
            Layout.fillWidth: true
            height: Style.space(42)
            radius: Style.space(6)
            color: Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, 0.08)
            Column {
              anchors.centerIn: parent
              Text { text: "Disk Used"; color: Qt.darker(root.panelFg, 1.4); font.family: root.fontFam; font.pixelSize: Style.font.caption; anchors.horizontalCenter: parent.horizontalCenter }
              Text { text: Math.round(root.diskPercent) + "%"; color: Color.accent; font.family: root.fontFam; font.pixelSize: Style.font.bodySmall; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
            }
          }
        }

        // Kill Banner
        Rectangle {
          visible: root.killConfirmPid !== -1
          width: parent.width
          height: Style.space(38)
          radius: Style.space(6)
          color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.18)
          border.color: Color.urgent
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            Text {
              text: "Kill " + root.killConfirmName + " (" + root.killConfirmPid + ")?"
              color: Color.urgent
              font.family: root.fontFam
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              Layout.fillWidth: true
              elide: Text.ElideRight
            }
            Button {
              text: "Kill (Enter)"
              foreground: Color.urgent
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: root.killProcess(root.killConfirmPid, root.killConfirmName)
            }
            Button {
              text: "Cancel"
              foreground: root.panelFg
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              onClicked: root.killConfirmPid = -1
            }
          }
        }

        PanelSeparator { foreground: root.panelFg }

        // Table Header (100% Relative Layout)
        RowLayout {
          width: parent.width
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Text { text: "PID"; color: Qt.darker(root.panelFg, 1.6); font.family: root.monoFam; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(50) }
          Text { text: "APPLICATION"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption; font.bold: true; Layout.fillWidth: true }
          Text { text: "CPU"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption; font.bold: true; Layout.preferredWidth: Style.space(60); horizontalAlignment: Text.AlignRight }
          Text { text: "RAM"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption; font.bold: true; Layout.preferredWidth: Style.space(75); horizontalAlignment: Text.AlignRight }
          Text { text: "TOTAL I/O"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption; font.bold: true; Layout.preferredWidth: Style.space(75); horizontalAlignment: Text.AlignRight }
          Text { text: "ACT"; color: Qt.darker(root.panelFg, 1.6); font.family: root.fontFam; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(42); horizontalAlignment: Text.AlignRight }
        }

        // Process List (Repeater on root.procsAll)
        Column {
          width: parent.width
          spacing: Style.space(3)

          Repeater {
            model: root.procsAll.length > 0 ? root.procsAll : [{ pid: 0, name: "Scanning system...", cpu: 0, mem_str: "0 B", extra: "0 B" }]

            Rectangle {
              id: overRowItem
              required property var modelData
              required property int index
              width: parent.width
              height: Style.space(28)
              radius: Style.space(6)
              color: root.selectedIndex === overRowItem.index
                ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
                : (overRowMouse.containsMouse ? Qt.rgba(root.panelFg.r, root.panelFg.g, root.panelFg.b, 0.08) : "transparent")

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Text { text: String(overRowItem.modelData.pid); color: Qt.darker(root.panelFg, 1.6); font.family: root.monoFam; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(50); Layout.alignment: Qt.AlignVCenter }
                Text { textFormat: Text.PlainText; text: overRowItem.modelData.name || ""; color: root.panelFg; font.family: root.fontFam; font.pixelSize: Style.font.bodySmall; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
                Text { text: overRowItem.modelData.cpu ? (overRowItem.modelData.cpu.toFixed(1) + "%") : "0.0%"; color: (overRowItem.modelData.cpu > 70) ? Color.urgent : Color.accent; font.family: root.monoFam; font.pixelSize: Style.font.caption; font.bold: true; Layout.preferredWidth: Style.space(60); horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter }
                Text { text: overRowItem.modelData.mem_str || (overRowItem.modelData.mem ? overRowItem.modelData.mem.toFixed(1) + "%" : "0 B"); color: root.panelFg; font.family: root.monoFam; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(75); horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter }
                Text { text: overRowItem.modelData.extra || "0 B"; color: Color.accent; font.family: root.monoFam; font.pixelSize: Style.font.caption; Layout.preferredWidth: Style.space(75); horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter }

                Button {
                  visible: overRowItem.modelData.pid > 0
                  text: "Kill"
                  foreground: Color.urgent
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(2)
                  Layout.preferredWidth: Style.space(42)
                  Layout.alignment: Qt.AlignVCenter
                  onClicked: root.promptKill(overRowItem.modelData.pid, overRowItem.modelData.name)
                }
              }

              MouseArea {
                id: overRowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectedIndex = overRowItem.index
                onDoubleClicked: root.promptKill(overRowItem.modelData.pid, overRowItem.modelData.name)
              }
            }
          }
        }

        RowLayout {
          width: parent.width
          Text {
            text: "↑↓: Select  •  x: Kill  •  Enter: Confirm  •  Esc: Close"
            color: Qt.darker(root.panelFg, 1.8)
            font.family: root.fontFam
            font.pixelSize: Style.font.caption
            Layout.fillWidth: true
          }
          Button {
            iconText: "󰄛"
            text: "Launch btop"
            foreground: Color.accent
            horizontalPadding: Style.space(10)
            verticalPadding: Style.space(4)
            onClicked: {
              if (root.bar) root.bar.run("hyprctl dispatch exec \"[float] alacritty -e btop || foot -e btop\"")
              root.closeAll()
            }
          }
        }
      }
    }
  }
}
}
