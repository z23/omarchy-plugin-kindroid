import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

// One chat message: speaker and time, the text with roleplay styling, any
// selfies, the notes Kindroid attaches (searches, links), and a failure line.
// Text is selectable so it can be copied.
Item {
  id: item

  // ListModel roles.
  required property string role
  required property string name
  required property string segs
  required property real ts
  required property string images
  required property string notes
  required property string failed
  required property bool notSent

  required property var look
  signal openImage(string url)

  readonly property bool mine: role === "user"
  readonly property var imageList: images === "" ? [] : images.split("\n")

  implicitHeight: column.implicitHeight + Style.space(10)

  Rectangle {
    // A thin rule marks your own messages.
    visible: item.mine
    width: Math.max(1, Style.space(2))
    radius: width / 2
    color: Commons.Util.alpha(item.look.accent, 0.55)
    anchors.top: column.top
    anchors.bottom: column.bottom
    anchors.left: parent.left
  }

  Column {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: item.mine ? Style.space(8) : 0
    spacing: Style.space(3)

    Row {
      spacing: Style.space(6)
      Text {
        id: nameLabel
        textFormat: Text.PlainText
        text: item.name
        color: item.mine ? item.look.muted : item.look.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        text: item.look.timeText(item.ts)
        color: item.look.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        anchors.baseline: nameLabel.baseline
      }
    }

    TextEdit {
      width: parent.width
      visible: text !== ""
      readOnly: true
      selectByMouse: true
      textFormat: TextEdit.RichText
      wrapMode: TextEdit.Wrap
      color: item.notSent ? item.look.muted : item.look.fg
      selectionColor: item.look.selection
      selectedTextColor: item.look.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      text: {
        var parsed = []
        try { parsed = JSON.parse(item.segs) } catch (e) {}
        return parsed.length ? Model.richText(parsed, { action: item.look.actionCss, quote: item.look.quoteCss }) : ""
      }
    }

    Repeater {
      model: item.imageList
      delegate: Image {
        required property string modelData
        source: modelData
        asynchronous: true
        cache: true
        fillMode: Image.PreserveAspectFit
        width: Math.min(column.width, Style.space(260))
        height: status === Image.Ready ? implicitHeight * (width / Math.max(1, implicitWidth)) : Style.space(120)
        sourceSize.width: Style.space(520)

        Rectangle {
          anchors.fill: parent
          visible: parent.status !== Image.Ready
          color: Commons.Util.alpha(item.look.fg, 0.06)
          radius: Style.cornerRadius
          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: parent.parent.status === Image.Error ? "Image unavailable" : "Loading image…"
            color: item.look.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: item.openImage(parent.modelData)
        }
      }
    }

    Text {
      width: parent.width
      visible: item.notes !== ""
      textFormat: Text.PlainText
      text: item.notes
      wrapMode: Text.Wrap
      color: item.look.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.italic: true
    }

    Text {
      width: parent.width
      visible: item.failed !== "" && item.failed !== "stopped"
      textFormat: Text.PlainText
      text: (item.notSent ? "Not sent: " : "") + item.failed
      wrapMode: Text.Wrap
      color: item.look.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      visible: item.failed === "stopped"
      textFormat: Text.PlainText
      text: "Stopped"
      color: item.look.faint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
}
