import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The bar icon. Left click opens the chat panel; middle click stops a reply in
// progress. A dot means a reply landed while you weren't looking at it.
BarWidget {
  id: root
  moduleName: "io.github.z23.kindroid"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("io.github.z23.kindroid") : null
  readonly property bool unread: !!service && service.anyUnread
  readonly property bool replying: !!service && service.anyReplying

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = root.service
  }

  // Shape contract for shell.summon/hide/toggle routing: the bar finds a panel
  // through open/close/opened on the widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.openFromHotkey() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onServiceChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("ChatPanel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.unread || root.replying ? "󰋑" : "󰋕"
    tooltipText: root.opened ? "" : root.tooltip()
    opacity: root.replying ? pulse.value : 1

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.MiddleButton) {
        if (root.service) root.service.stop()
      } else {
        root.toggle()
      }
    }
  }

  // Unread dot, in the theme's accent.
  Rectangle {
    visible: root.unread && !root.opened
    width: Math.max(4, Style.space(5))
    height: width
    radius: width / 2
    color: Commons.Color.accent
    x: button.width / 2 + Style.space(5)
    y: button.height / 2 - Style.space(9)
  }

  QtObject {
    id: pulse
    property real value: 1
  }
  SequentialAnimation {
    running: root.replying && !Style.reduceMotion
    loops: Animation.Infinite
    onRunningChanged: if (!running) pulse.value = 1
    NumberAnimation { target: pulse; property: "value"; to: 0.45; duration: Style.duration(700); easing.type: Easing.InOutSine }
    NumberAnimation { target: pulse; property: "value"; to: 1; duration: Style.duration(700); easing.type: Easing.InOutSine }
  }

  function tooltip() {
    if (!service) return "Kindroid"
    var name = service.activeEntry ? service.activeEntry.name : ""
    if (service.anyReplying) return (name ? name + " is replying…" : "Replying…")
    if (service.anyUnread) return "New reply" + (name ? " · " + name : "")
    return name ? "Kindroid · " + name : "Kindroid"
  }
}
