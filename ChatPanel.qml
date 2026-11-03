import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "qml" as Parts

// The popup under the bar icon. It only hosts ChatView and handles opening,
// closing and focus; all chat state lives in Service.qml, so every monitor's
// panel shows the same conversation and a reply keeps streaming with the
// panel closed.
Panel {
  id: root
  moduleName: "io.github.z23.kindroid"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  // The bar identifies a panel by the widget in its slot, not by this nested item.
  readonly property var barIdentity: hostWidget || root

  function open() {
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
  }

  function openFromHotkey() {
    root.controller.show()
    Qt.callLater(function() { if (root.opened) setCenterHoverRevealSuppressed(true) })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (panel.loadedContent) panel.loadedContent.page = "chat"
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
  }

  // Tell the service when this panel is showing, so it can open the active
  // chat and knows whether a reply was seen.
  property var reportedTo: null
  function report() {
    var target = root.opened ? root.service : null
    if (target === root.reportedTo) return
    if (root.reportedTo) root.reportedTo.panelClosed()
    root.reportedTo = target
    if (target) target.panelOpened()
  }
  onOpenedChanged: {
    report()
    if (opened) Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.focusPage() })
  }
  onServiceChanged: report()
  Component.onDestruction: if (root.reportedTo) root.reportedTo.panelClosed()

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: panel.loadedContent ? panel.loadedContent.focusFor(panel.loadedContent.page, panel.loadedContent.mode) : null
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.cappedContentHeight(Style.space(640))

    content: Parts.ChatView {
      anchors.fill: parent
      service: root.service
      onCloseRequested: root.close()
    }
  }
}
