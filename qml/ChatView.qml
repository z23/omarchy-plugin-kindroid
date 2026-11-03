import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Everything inside the chat panel: header, message list, composer, and the
// pages for switching chats, adding one, the scene, undo and chat breaks.
// ChatPanel.qml hosts it in the bar's popup; it holds no state of its own
// beyond which page is showing, so it can also be drawn on its own.
FocusScope {
  id: root

  property var service: null
  signal closeRequested()

  // chat · pick (conversations) · more · add · scene · undo · break
  property string page: "chat"

  readonly property bool hasService: !!service
  // What the panel can show right now, before the page matters.
  readonly property string mode: {
    if (!service) return "starting"
    var st = service.helperStatus
    if (st === "missing" || st === "failed" || st === "incompatible") return "helper"
    if (!service.configLoaded) return "starting"
    if (!service.hasKey) return "nokey"
    if (service.conversations.length === 0 && page !== "add") return "empty"
    return "ok"
  }
  readonly property string activeName: service && service.activeEntry ? service.activeEntry.name : ""
  readonly property bool isGroup: !!service && service.activeIsGroup
  readonly property bool busy: !!service && service.busy

  function go(name) {
    root.page = name
    Qt.callLater(focusPage)
  }

  // Esc steps back: a page returns to the chat, the chat closes the panel.
  function back() {
    if (root.page !== "chat") go("chat")
    else root.closeRequested()
  }

  function focusPage() {
    var target = focusFor(root.page, root.mode)
    if (target && root.visible) target.forceActiveFocus()
  }

  onModeChanged: Qt.callLater(focusPage)

  // Ctrl shortcuts shared by every page. Returns true when handled.
  function shortcut(event) {
    if (!(event.modifiers & Qt.ControlModifier) || root.mode !== "ok") return false
    switch (event.key) {
    case Qt.Key_K: go(root.page === "pick" ? "chat" : "pick"); return true
    case Qt.Key_S: go("scene"); return true
    case Qt.Key_B: go("break"); return true
    case Qt.Key_R: if (!root.isGroup && !root.busy) root.service.regenerate(); return true
    case Qt.Key_N: if (root.isGroup && !root.busy) root.service.continueGroup(); return true
    case Qt.Key_L: root.service.sync(); return true
    case Qt.Key_X: root.service.dismiss(); return true
    }
    return false
  }

  QtObject {
    id: theme
    readonly property color fg: Commons.Color.popups.text
    readonly property color bg: Commons.Color.popups.background
    readonly property color accent: Commons.Color.accent
    readonly property color urgent: Commons.Color.urgent
    readonly property color muted: Qt.tint(bg, Qt.rgba(fg.r, fg.g, fg.b, 0.72))
    readonly property color faint: Qt.tint(bg, Qt.rgba(fg.r, fg.g, fg.b, 0.5))
    readonly property color selection: Style.selectionFillFor(fg, accent, urgent)
    readonly property string actionCss: Model.cssColor(muted)
    readonly property string quoteCss: Model.cssColor(accent)

    function timeText(ms) {
      if (!ms) return ""
      var d = new Date(ms)
      var t = d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
      var bucket = Model.dayBucket(ms, Date.now())
      if (bucket === "today") return t
      if (bucket === "yesterday") return "Yesterday " + t
      return d.toLocaleDateString(Qt.locale(), "d MMM") + " " + t
    }
  }

  function sendNow() {
    if (!root.service) return
    var text = input.text.trim()
    if (text === "") return
    if (root.service.send(text)) {
      input.text = ""
      list.stick = true
      Qt.callLater(list.toEnd)
    }
  }

  function focusFor(page, mode) {
    if (mode !== "ok") return setupPage
    switch (page) {
    case "pick": return pickList
    case "more": return moreList
    case "add": return addId
    case "scene": return sceneInput
    case "undo": return undoPage
    case "break": return breakInput
    default: return input
    }
  }

  // Keys that reach here weren't taken by a field.
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) { root.back(); event.accepted = true; return }
    if (root.shortcut(event)) event.accepted = true
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(8)

    // Header: which chat, and quick actions.
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(4)

      Button {
        id: chatButton
        Layout.fillWidth: true
        Layout.maximumWidth: implicitWidth
        visible: root.mode === "ok"
        leftAlign: true
        text: (root.activeName || "Choose a chat") + (root.isGroup ? "  ·  group" : "")
        iconText: root.page === "pick" ? "󰅃" : "󰅀"
        foreground: theme.fg
        accent: theme.accent
        fontSize: Style.font.title
        selected: root.page === "pick"
        tooltipText: "Switch chat (Ctrl+K)"
        onClicked: root.go(root.page === "pick" ? "chat" : "pick")
      }
      Text {
        visible: root.mode !== "ok"
        textFormat: Text.PlainText
        text: "Kindroid"
        color: theme.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Rectangle {
        // Unread replies elsewhere.
        visible: root.mode === "ok" && root.hasService && Object.keys(root.service.unreadKeys).some(function(k) { return k !== root.service.activeKey })
        Layout.preferredWidth: Style.space(6)
        Layout.preferredHeight: Style.space(6)
        radius: width / 2
        color: theme.accent
      }
      Item { Layout.fillWidth: true }
      Button {
        visible: root.mode === "ok" && root.page === "chat" && !root.isGroup
        enabled: !root.busy
        opacity: enabled ? 1 : 0.4
        iconText: "󰑐"
        foreground: theme.fg
        tooltipText: "Regenerate the last reply (Ctrl+R)"
        onClicked: root.service.regenerate()
      }
      Button {
        visible: root.mode === "ok" && root.page === "chat" && root.isGroup
        enabled: !root.busy
        opacity: enabled ? 1 : 0.4
        iconText: "󰒭"
        foreground: theme.fg
        tooltipText: "Let them keep talking (Ctrl+N)"
        onClicked: root.service.continueGroup()
      }
      Button {
        visible: root.mode === "ok" && root.page === "chat"
        enabled: !root.busy
        opacity: enabled ? 1 : 0.4
        iconText: "󰕌"
        foreground: theme.fg
        tooltipText: "Undo… (Ctrl+Z in an empty message box)"
        onClicked: root.go("undo")
      }
      Button {
        visible: root.mode === "ok"
        iconText: "󰇙"
        foreground: theme.fg
        selected: root.page === "more"
        tooltipText: "More"
        onClicked: root.go(root.page === "more" ? "chat" : "more")
      }
    }

    PanelSeparator { Layout.fillWidth: true; foreground: theme.fg }

    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      // ---------------------------------------------------------------- setup
      FocusScope {
        id: setupPage
        anchors.fill: parent
        visible: root.mode !== "ok"
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { root.closeRequested(); event.accepted = true }
        }

        ColumnLayout {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(10)

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: theme.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
            text: {
              switch (root.mode) {
              case "helper":
                return root.service.helperStatus === "missing" ? "kindroid-tui isn't installed"
                  : root.service.helperStatus === "incompatible" ? "kindroid-tui needs updating" : "kindroid-tui stopped"
              case "nokey": return "Add your Kindroid API key"
              case "empty": return "Add your first Kindroid"
              default: return "Starting…"
              }
            }
          }
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            visible: text !== ""
            text: {
              if (!root.service) return ""
              switch (root.mode) {
              case "helper": return root.service.helperDetail
              case "nokey":
                return "Get it in the Kindroid app under Profile → Preferences → API & Integrations. Put it in "
                  + root.service.configPath + " as api_key = \"kn_…\", then reload. The file is readable only by you. "
                  + "Treat the key like a password."
              case "empty":
                return "Kindroid's API can't list your Kindroids, so each one is added once by its ID: the ai_id at the "
                  + "bottom of the Kin's settings menu, or a group's ID from its web address."
              default: return ""
              }
            }
          }
          Text {
            Layout.fillWidth: true
            visible: root.hasService && root.service.warnings.length > 0
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: theme.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            text: root.hasService ? root.service.warnings.join("\n") : ""
          }
          RowLayout {
            spacing: Style.space(6)
            Button {
              visible: root.mode === "helper"
              text: "Try again"
              bordered: true
              focusable: true
              foreground: theme.fg
              onClicked: root.service.restartHelper()
            }
            Button {
              visible: root.mode === "nokey"
              text: "Edit config.toml"
              bordered: true
              focusable: true
              foreground: theme.fg
              onClicked: root.service.editConfig()
            }
            Button {
              visible: root.mode === "nokey"
              text: "Reload"
              bordered: true
              focusable: true
              foreground: theme.fg
              onClicked: root.service.reload()
            }
            Button {
              visible: root.mode === "empty"
              text: "Add a Kindroid or group…"
              bordered: true
              focusable: true
              foreground: theme.fg
              onClicked: root.go("add")
            }
          }
        }
      }

      // ----------------------------------------------------------------- chat
      ColumnLayout {
        id: chatPage
        anchors.fill: parent
        visible: root.mode === "ok" && root.page === "chat"
        spacing: Style.space(6)

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

        Text {
          anchors.centerIn: parent
          width: parent.width - Style.space(40)
          z: 1
          visible: list.count === 0 && root.hasService && !root.service.busy
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: "No messages with " + root.activeName + " yet. Say hello!"
          color: theme.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        ListView {
          id: list
          anchors.fill: parent
          clip: true
          model: root.hasService ? root.service.messageModel : null
          spacing: Style.space(8)
          boundsBehavior: Flickable.StopAtBounds
          reuseItems: false
          ScrollBar.vertical: ScrollBar { id: listBar; policy: ScrollBar.AsNeeded }

          // Follow new text while you're at the bottom; stay put once you scroll up.
          property bool stick: true
          property bool positioning: false
          function toEnd() {
            positioning = true
            positionViewAtEnd()
            positioning = false
          }
          onContentYChanged: if (!positioning) stick = contentY + height >= contentHeight + originY - Style.space(24)
          onContentHeightChanged: if (stick) Qt.callLater(toEnd)
          onCountChanged: if (stick) Qt.callLater(toEnd)
          onVisibleChanged: if (visible) { stick = true; Qt.callLater(toEnd) }

          header: Item {
            width: ListView.view.width
            height: root.hasService && root.service.canLoadOlder ? olderButton.implicitHeight + Style.space(8) : 0
            visible: height > 0
            Button {
              id: olderButton
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Show older messages"
              foreground: theme.muted
              fontSize: Style.font.caption
              onClicked: { list.stick = false; root.service.loadOlder() }
            }
          }

          delegate: MessageItem {
            width: ListView.view.width - (listBar.visible ? listBar.width + Style.space(2) : 0)
            look: theme
            onOpenImage: function(url) { root.service.openImage(url) }
          }

          footer: Item {
            id: draftFooter
            width: ListView.view.width - (listBar.visible ? listBar.width + Style.space(2) : 0)
            readonly property var d: root.hasService ? root.service.draft : null
            height: d ? draftColumn.implicitHeight + Style.space(8) : 0
            visible: !!d
            Column {
              id: draftColumn
              width: parent.width
              y: Style.space(8)
              spacing: Style.space(3)
              Text {
                textFormat: Text.PlainText
                text: draftFooter.d ? draftFooter.d.name : ""
                color: theme.accent
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
              TextEdit {
                width: parent.width
                readOnly: true
                selectByMouse: true
                textFormat: TextEdit.RichText
                wrapMode: TextEdit.Wrap
                color: theme.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                text: {
                  var dr = draftFooter.d
                  var html = dr && dr.segments ? Model.richText(dr.segments, { action: theme.actionCss, quote: theme.quoteCss }) : ""
                  return html + '<span style="color:' + theme.quoteCss + '"> ▍</span>'
                }
              }
            }
          }
        }
        }

        // Status: what's happening, then the latest notice or error.
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)
          readonly property string activityText: root.hasService ? Model.activityLabel(root.service.activity) : ""
          readonly property int wait: root.hasService ? root.service.rateWait : 0
          readonly property string message: !root.hasService ? "" : (root.service.error || root.service.notice || "")
          visible: activityText !== "" || wait > 0 || message !== ""

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: root.hasService && root.service.error ? theme.urgent : theme.muted
            text: {
              var parts = []
              if (parent.activityText) parts.push(parent.activityText)
              if (parent.wait > 0) parts.push("waiting " + parent.wait + "s for Kindroid's rate limit")
              if (parent.message) parts.push(parent.message)
              return parts.join(" · ")
            }
          }
          Button {
            visible: parent.message !== ""
            iconText: "󰅖"
            foreground: theme.faint
            tooltipText: "Dismiss (Ctrl+X)"
            onClicked: root.service.dismiss()
          }
        }

        // Composer.
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          BorderSurface {
            id: inputBox
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(input.implicitHeight, Style.space(140)) + Style.space(4)
            color: Style.controlFill(input.activeFocus, false, theme.fg, theme.accent)
            borderSpec: Border.controlSpec(input.activeFocus ? "focus" : "normal", theme.fg, theme.accent)
            radius: Style.cornerRadius

            Flickable {
              id: inputFlick
              anchors.fill: parent
              anchors.margins: Style.space(2)
              clip: true
              contentWidth: width
              contentHeight: input.implicitHeight
              boundsBehavior: Flickable.StopAtBounds

              TextArea.flickable: TextArea {
                id: input
                wrapMode: TextArea.Wrap
                placeholderText: root.activeName ? "Message " + root.activeName + "…" : "Message…"
                placeholderTextColor: theme.faint
                color: theme.fg
                selectionColor: theme.selection
                selectedTextColor: theme.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                selectByMouse: true
                background: null
                leftPadding: Style.spacing.controlPaddingX
                rightPadding: Style.spacing.controlPaddingX
                topPadding: Style.spacing.inputPaddingY
                bottomPadding: Style.spacing.inputPaddingY

                // Each chat keeps its own unsent text.
                property string boundKey: ""
                function bindTo(key) {
                  if (boundKey !== "" && root.hasService) root.service.setDraftFor(boundKey, text)
                  boundKey = key
                  text = root.hasService ? root.service.draftFor(key) : ""
                  cursorPosition = length
                }
                Connections {
                  target: root.service
                  function onActiveKeyChanged() { input.bindTo(root.service.activeKey) }
                }
                Component.onCompleted: if (root.hasService) bindTo(root.service.activeKey)
                onTextChanged: if (boundKey !== "" && root.hasService) root.service.setDraftFor(boundKey, text)

                Keys.onPressed: function(event) {
                  var shift = event.modifiers & Qt.ShiftModifier
                  var ctrl = event.modifiers & Qt.ControlModifier
                  if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !shift) {
                    root.sendNow()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Escape) {
                    root.back()
                    event.accepted = true
                  } else if (ctrl && event.key === Qt.Key_Z && input.text === "") {
                    root.go("undo")
                    event.accepted = true
                  } else if (ctrl && event.key === Qt.Key_C && input.selectedText === "" && root.busy) {
                    root.service.stop()
                    event.accepted = true
                  } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
                    var step = (event.key === Qt.Key_PageUp ? -1 : 1) * list.height * 0.85
                    list.contentY = Math.max(list.originY, Math.min(list.contentY + step, list.originY + list.contentHeight - list.height))
                    event.accepted = true
                  } else if (root.shortcut(event)) {
                    event.accepted = true
                  }
                }
              }
            }
          }

          Button {
            Layout.alignment: Qt.AlignBottom
            iconText: root.busy && root.hasService && root.service.activity.kind !== "syncing" ? "󰓛" : "󰒊"
            iconSize: Style.font.iconLarge
            foreground: theme.fg
            accent: theme.accent
            bordered: true
            tooltipText: iconText === "󰓛" ? "Stop (Ctrl+C)" : "Send (Enter)"
            onClicked: iconText === "󰓛" ? root.service.stop() : root.sendNow()
          }
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: theme.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          text: "Enter send · Shift+Enter new line · Ctrl+K chats · Esc close"
        }
      }

      // ---------------------------------------------------------- pick a chat
      ListView {
        id: pickList
        anchors.fill: parent
        visible: root.mode === "ok" && root.page === "pick"
        clip: true
        spacing: Style.space(2)
        readonly property var entries: root.hasService ? root.service.conversations.concat([{ key: "", name: "Add a Kindroid or group…", kind: "add" }]) : []
        model: entries
        keyNavigationEnabled: true
        highlightMoveDuration: 0
        onVisibleChanged: if (visible) currentIndex = Math.max(0, entries.findIndex(function(e) { return e.key === root.service.activeKey }))

        function choose(entry) {
          if (entry.kind === "add") { root.go("add"); return }
          root.service.selectConversation(entry.key)
          root.go("chat")
        }

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (currentIndex >= 0 && currentIndex < entries.length) choose(entries[currentIndex])
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            root.back()
            event.accepted = true
          } else if (root.shortcut(event)) {
            event.accepted = true
          }
        }

        delegate: BorderSurface {
          id: pickRow
          required property var modelData
          required property int index
          readonly property bool current: ListView.isCurrentItem
          readonly property bool active: root.hasService && modelData.key === root.service.activeKey
          width: ListView.view.width
          height: pickInner.implicitHeight + Style.space(12)
          radius: Style.cornerRadius
          color: current ? Style.selectedFillFor(theme.fg, theme.accent, theme.urgent) : (pickMouse.containsMouse ? Style.hoverFillFor(theme.fg, theme.accent, theme.urgent) : "transparent")
          borderSpec: current ? Border.controlSpec("normal", theme.fg, theme.accent) : Border.none()

          RowLayout {
            id: pickInner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: pickRow.modelData.kind === "add" ? "󰐕" : (pickRow.modelData.kind === "group" ? "󰡉" : "󰋕")
              color: pickRow.active ? theme.accent : theme.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: pickRow.modelData.name
              color: pickRow.modelData.kind === "add" ? theme.muted : theme.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: pickRow.active
            }
            Text {
              visible: root.hasService && !!root.service.busyKeys[pickRow.modelData.key]
              textFormat: Text.PlainText
              text: "…"
              color: theme.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
            Rectangle {
              visible: root.hasService && !!root.service.unreadKeys[pickRow.modelData.key]
              Layout.preferredWidth: Style.space(6)
              Layout.preferredHeight: Style.space(6)
              radius: width / 2
              color: theme.accent
            }
          }

          MouseArea {
            id: pickMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pickList.choose(pickRow.modelData)
          }
        }
      }

      // ----------------------------------------------------------------- more
      ListView {
        id: moreList
        anchors.fill: parent
        visible: root.mode === "ok" && root.page === "more"
        clip: true
        spacing: Style.space(2)
        keyNavigationEnabled: true
        highlightMoveDuration: 0
        onVisibleChanged: if (visible) currentIndex = 0
        model: items
        readonly property var items: {
          if (!root.hasService) return []
          var s = root.service
          var items = [
            { id: "scene", label: "Set the scene…", hint: "Ctrl+S" },
            { id: "undo", label: "Undo several messages…", hint: "Ctrl+Z" },
          ]
          if (root.isGroup) items.push({ id: "continue", label: "Let them keep talking", hint: "Ctrl+N" })
          else items.push({ id: "regenerate", label: "Regenerate the last reply", hint: "Ctrl+R" })
          items.push({ id: "break", label: "Chat break…", hint: "Ctrl+B" })
          items.push({ id: "sync", label: "Sync now", hint: "Ctrl+L" })
          if (s.canLoadOlder) items.push({ id: "older", label: "Show older messages", hint: "" })
          items.push({ id: "add", label: "Add a Kindroid or group…", hint: "" })
          items.push({ id: "edit", label: "Edit config.toml", hint: "" })
          items.push({ id: "reload", label: "Reload config", hint: "" })
          return items
        }

        function run(id) {
          var s = root.service
          switch (id) {
          case "scene": case "undo": case "break": case "add": root.go(id); return
          case "continue": s.continueGroup(); break
          case "regenerate": s.regenerate(); break
          case "sync": s.sync(); break
          case "older": s.loadOlder(); break
          case "edit": s.editConfig(); root.closeRequested(); return
          case "reload": s.reload(); break
          }
          root.go("chat")
        }

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (currentIndex >= 0 && currentIndex < items.length) run(items[currentIndex].id)
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            root.back()
            event.accepted = true
          } else if (root.shortcut(event)) {
            event.accepted = true
          }
        }

        footer: Text {
          width: ListView.view.width
          topPadding: Style.space(12)
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: theme.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          text: {
            if (!root.hasService) return ""
            var s = root.service
            var lines = []
            if (s.limits) lines.push("History calls left today: " + s.limits.budgetRemaining + " of " + s.limits.budgetLimit)
            if (s.helperVersion) lines.push("kindroid-tui " + s.helperVersion + " · unofficial client; Kindroid's terms apply")
            return lines.join("\n")
          }
        }

        delegate: BorderSurface {
          id: moreRow
          required property var modelData
          readonly property bool current: ListView.isCurrentItem
          width: ListView.view.width
          height: moreInner.implicitHeight + Style.space(12)
          radius: Style.cornerRadius
          color: current ? Style.selectedFillFor(theme.fg, theme.accent, theme.urgent) : (moreMouse.containsMouse ? Style.hoverFillFor(theme.fg, theme.accent, theme.urgent) : "transparent")
          borderSpec: current ? Border.controlSpec("normal", theme.fg, theme.accent) : Border.none()

          RowLayout {
            id: moreInner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: moreRow.modelData.label
              color: theme.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
            Text {
              textFormat: Text.PlainText
              text: moreRow.modelData.hint
              color: theme.faint
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
          MouseArea {
            id: moreMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: moreList.run(moreRow.modelData.id)
          }
        }
      }

      // ------------------------------------------------------------------ add
      FocusScope {
        id: addPage
        anchors.fill: parent
        visible: root.page === "add" && (root.mode === "ok" || root.mode === "empty")
        property string kind: "kin"
        property bool checking: false
        property bool checked: false
        property string resolvedId: ""
        property string problem: ""
        onVisibleChanged: if (visible) { addId.text = ""; addName.text = ""; checked = false; problem = ""; resolvedId = "" }

        function check() {
          var id = Model.normalizeId(addId.text)
          if (id === "") { problem = "Paste an ID first."; return }
          checking = true
          problem = ""
          root.service.lookup(kind, id, function(res) {
            addPage.checking = false
            if (!res.ok) { addPage.problem = res.error || "That ID didn't work."; return }
            addPage.resolvedId = res.result.id
            addPage.checked = true
            if (res.result.name) addName.text = res.result.name
            else if (addName.text === "") addPage.problem = "No history to read a name from; type one."
            addName.forceActiveFocus()
            addName.selectAll()
          })
        }

        function save() {
          if (!checked) { check(); return }
          var name = addName.text.trim()
          if (name === "") { problem = "Give it a name."; return }
          checking = true
          root.service.addConversation(kind, resolvedId, name, function(res) {
            addPage.checking = false
            if (!res.ok) { addPage.problem = res.error || "Couldn't save it."; return }
            root.go("chat")
          })
        }

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { root.back(); event.accepted = true }
        }

        ColumnLayout {
          anchors.fill: parent
          spacing: Style.space(10)

          Text {
            textFormat: Text.PlainText
            text: "Add a Kindroid or a group"
            color: theme.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
          }
          RowLayout {
            spacing: Style.space(4)
            Button {
              text: "Kindroid"
              bordered: true
              selected: addPage.kind === "kin"
              foreground: theme.fg
              onClicked: { addPage.kind = "kin"; addPage.checked = false }
            }
            Button {
              text: "Group"
              bordered: true
              selected: addPage.kind === "group"
              foreground: theme.fg
              onClicked: { addPage.kind = "group"; addPage.checked = false }
            }
          }
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            text: addPage.kind === "kin"
              ? "Paste the ai_id from the bottom of the Kin's settings menu. Checking it reads a little history (one of your 600 daily history calls) to fill in the name."
              : "Paste the group_id, the last part of the group's web address (…/v2/chat/group/<id>); the whole address works too. Group chats need a Kindroid subscription."
          }
          TextField {
            id: addId
            Layout.fillWidth: true
            placeholderText: addPage.kind === "kin" ? "ai_id" : "group_id or web address"
            foreground: theme.fg
            accent: theme.accent
            onTextChanged: addPage.checked = false
            onAccepted: addPage.check()
            Keys.onEscapePressed: root.back()
          }
          TextField {
            id: addName
            Layout.fillWidth: true
            visible: addPage.checked
            placeholderText: "Name"
            foreground: theme.fg
            accent: theme.accent
            onAccepted: addPage.save()
            Keys.onEscapePressed: root.back()
          }
          Text {
            Layout.fillWidth: true
            visible: addPage.problem !== ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: theme.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            text: addPage.problem
          }
          RowLayout {
            spacing: Style.space(6)
            Button { text: "Cancel"; bordered: true; foreground: theme.fg; onClicked: root.back() }
            Button {
              text: addPage.checking ? "Checking…" : (addPage.checked ? "Add" : "Check")
              enabled: !addPage.checking
              bordered: true
              foreground: theme.fg
              accent: theme.accent
              selected: true
              onClicked: addPage.save()
            }
          }
          Item { Layout.fillHeight: true }
        }
      }

      // ---------------------------------------------------------------- scene
      FocusScope {
        id: scenePage
        anchors.fill: parent
        visible: root.mode === "ok" && root.page === "scene"
        property bool saving: false
        property string problem: ""
        onVisibleChanged: if (visible) {
          problem = ""
          sceneInput.text = root.hasService && root.service.scene ? root.service.scene.text : ""
          sceneInput.cursorPosition = sceneInput.length
        }

        function save() {
          var text = sceneInput.text.trim()
          if (text === "") { problem = "The scene can't be empty."; return }
          saving = true
          root.service.setScene(text, function(res) {
            scenePage.saving = false
            if (res.ok && res.result && res.result.ok) root.go("chat")
            else scenePage.problem = res.error || root.service.error || "Couldn't set the scene."
          })
        }

        ColumnLayout {
          anchors.fill: parent
          spacing: Style.space(10)
          Text {
            textFormat: Text.PlainText
            text: "Set the scene" + (root.activeName ? " for " + root.activeName : "")
            color: theme.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
          }
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            text: "This replaces the current scene in Kindroid. Kindroid can't report the scene back, so this starts from the last one set from kindroid-tui or this panel"
              + (root.hasService && root.service.scene ? " (" + theme.timeText(root.service.scene.at) + ")." : ".")
          }
          BorderSurface {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Style.controlFill(sceneInput.activeFocus, false, theme.fg, theme.accent)
            borderSpec: Border.controlSpec(sceneInput.activeFocus ? "focus" : "normal", theme.fg, theme.accent)
            radius: Style.cornerRadius
            Flickable {
              anchors.fill: parent
              anchors.margins: Style.space(2)
              clip: true
              contentWidth: width
              contentHeight: sceneInput.implicitHeight
              TextArea.flickable: TextArea {
                id: sceneInput
                wrapMode: TextArea.Wrap
                placeholderText: "Where are you, and what's happening?"
                placeholderTextColor: theme.faint
                color: theme.fg
                selectionColor: theme.selection
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                selectByMouse: true
                background: null
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) { root.back(); event.accepted = true }
                  else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) { scenePage.save(); event.accepted = true }
                }
              }
            }
          }
          Text {
            Layout.fillWidth: true
            visible: scenePage.problem !== ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: theme.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            text: scenePage.problem
          }
          RowLayout {
            spacing: Style.space(6)
            Button { text: "Cancel"; bordered: true; foreground: theme.fg; onClicked: root.back() }
            Button {
              text: scenePage.saving ? "Saving…" : "Set scene (Ctrl+Enter)"
              enabled: !scenePage.saving
              bordered: true
              selected: true
              foreground: theme.fg
              accent: theme.accent
              onClicked: scenePage.save()
            }
          }
        }
      }

      // ----------------------------------------------------------------- undo
      FocusScope {
        id: undoPage
        anchors.fill: parent
        visible: root.mode === "ok" && root.page === "undo"
        property int steps: 1
        property var preview: null
        property bool working: false
        property string problem: ""

        onVisibleChanged: if (visible) { steps = 1; preview = null; problem = ""; refresh() }
        onStepsChanged: if (visible) refresh()

        function refresh() {
          root.service.undoPreview(steps, function(res) {
            if (res.ok) {
              undoPage.preview = res.result
              if (res.result.steps !== undoPage.steps) undoPage.steps = res.result.steps
            } else undoPage.problem = res.error || ""
          })
        }

        function confirm() {
          if (!preview || preview.problem || working) return
          working = true
          root.service.undo(steps, function(res) {
            undoPage.working = false
            if (!res.ok) { undoPage.problem = res.error || "Couldn't undo."; return }
            var restored = res.result ? res.result.restored : null
            root.go("chat")
            if (restored && input.text.trim() === "") {
              input.text = restored
              input.cursorPosition = input.length
            }
          })
        }

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { root.back(); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { confirm(); event.accepted = true }
          else if (event.key === Qt.Key_Up || event.key === Qt.Key_Plus || event.key === Qt.Key_Right) {
            if (preview && steps < preview.maxSteps) steps++
            event.accepted = true
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Minus || event.key === Qt.Key_Left) {
            if (steps > 1) steps--
            event.accepted = true
          }
        }

        ColumnLayout {
          anchors.fill: parent
          spacing: Style.space(10)
          Text {
            textFormat: Text.PlainText
            text: "Undo"
            color: theme.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
          }
          RowLayout {
            spacing: Style.space(6)
            Button { iconText: "󰍴"; bordered: true; foreground: theme.fg; enabled: undoPage.steps > 1; onClicked: undoPage.steps-- }
            Text {
              textFormat: Text.PlainText
              color: theme.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              text: {
                var unit = undoPage.preview && undoPage.preview.unit === "message" ? "message" : "exchange"
                return "The last " + (undoPage.steps === 1 ? unit : undoPage.steps + " " + unit + "s")
              }
            }
            Button {
              iconText: "󰐕"
              bordered: true
              foreground: theme.fg
              enabled: !!undoPage.preview && undoPage.steps < undoPage.preview.maxSteps
              onClicked: undoPage.steps++
            }
          }
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            text: root.isGroup
              ? "Removes these messages from the group chat in Kindroid."
              : "Removes these messages from the chat in Kindroid. Your first one goes back in the message box so you can edit it."
          }
          ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Style.space(4)
            model: undoPage.preview ? undoPage.preview.messages : []
            delegate: Text {
              required property var modelData
              width: ListView.view.width
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
              color: theme.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.strikeout: true
              text: modelData.name + ": " + modelData.text.replace(/\s+/g, " ")
            }
          }
          Text {
            Layout.fillWidth: true
            visible: text !== ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: theme.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            text: undoPage.problem || (undoPage.preview && undoPage.preview.problem ? "Can't undo: " + undoPage.preview.problem : "")
          }
          RowLayout {
            spacing: Style.space(6)
            Button { text: "Cancel"; bordered: true; foreground: theme.fg; onClicked: root.back() }
            Button {
              text: undoPage.working ? "Undoing…" : "Undo"
              enabled: !!undoPage.preview && !undoPage.preview.problem && !undoPage.working
              bordered: true
              selected: true
              foreground: theme.fg
              accent: theme.urgent
              onClicked: undoPage.confirm()
            }
          }
        }
      }

      // ---------------------------------------------------------------- break
      FocusScope {
        id: breakPage
        anchors.fill: parent
        visible: root.mode === "ok" && root.page === "break"
        property bool wipe: false
        property bool working: false
        property string problem: ""
        onVisibleChanged: if (visible) { wipe = false; problem = ""; breakInput.text = "" }

        function confirm() {
          var greeting = breakInput.text.trim()
          if (greeting === "") { problem = "Write the greeting the new chat starts from."; return }
          working = true
          root.service.chatBreak(greeting, wipe, function(res) {
            breakPage.working = false
            if (!res.ok) { breakPage.problem = res.error || "Couldn't start a chat break."; return }
            root.go("chat")
          })
        }

        ColumnLayout {
          anchors.fill: parent
          spacing: Style.space(10)
          Text {
            textFormat: Text.PlainText
            text: "Chat break" + (root.activeName ? " with " + root.activeName : "")
            color: theme.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
          }
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: theme.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            text: "Ends this conversation and clears short-term memory; the chat starts again from your greeting. The history disappears from this panel too."
          }
          BorderSurface {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(110)
            color: Style.controlFill(breakInput.activeFocus, false, theme.fg, theme.accent)
            borderSpec: Border.controlSpec(breakInput.activeFocus ? "focus" : "normal", theme.fg, theme.accent)
            radius: Style.cornerRadius
            Flickable {
              anchors.fill: parent
              anchors.margins: Style.space(2)
              clip: true
              contentWidth: width
              contentHeight: breakInput.implicitHeight
              TextArea.flickable: TextArea {
                id: breakInput
                wrapMode: TextArea.Wrap
                placeholderText: "Greeting, e.g. *walks in* Hey, it's been a while!"
                placeholderTextColor: theme.faint
                color: theme.fg
                selectionColor: theme.selection
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                selectByMouse: true
                background: null
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) { root.back(); event.accepted = true }
                }
              }
            }
          }
          Toggle {
            Layout.fillWidth: true
            label: "Also wipe long-term memory"
            description: "Clears what " + (root.activeName || "they") + " remember across chats. This can't be undone."
            checked: breakPage.wipe
            foreground: theme.fg
            accent: theme.urgent
            onClicked: breakPage.wipe = !breakPage.wipe
          }
          Text {
            Layout.fillWidth: true
            visible: breakPage.problem !== ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: theme.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            text: breakPage.problem
          }
          Item { Layout.fillHeight: true }
          RowLayout {
            spacing: Style.space(6)
            Button { text: "Cancel"; bordered: true; foreground: theme.fg; onClicked: root.back() }
            Button {
              text: breakPage.working ? "Working…" : (breakPage.wipe ? "Break and wipe memory" : "Start chat break")
              enabled: !breakPage.working
              bordered: true
              selected: true
              foreground: theme.fg
              accent: breakPage.wipe ? theme.urgent : theme.accent
              onClicked: breakPage.confirm()
            }
          }
        }
      }
    }
  }
}
