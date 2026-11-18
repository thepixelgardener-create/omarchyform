import QtQuick
import QtQuick.Layouts
import "../Theme"
import "../Theme" as Commons

// A transient message inside the app, drawn on the [notifications] surface the shell's own
// toasts use: an optional glyph, a bold title, a line of text, an optional action, and a
// countdown line along the bottom in notifications.countdown.
//
//   Toast { glyph: "󰄬"; title: "Export finished"; text: "omarchy-demo.mp4"; actionText: "Open"; countdown: 0.6 }
//
// The toast draws one state; the app owns when it shows, where it stacks and the timer that drives
// `countdown` (1 → 0; below 0 hides the line). Messages meant for the desktop rather than the
// app go through `omarchy-notification-send`, not this.
BorderSurface {
  id: root

  property string glyph: ""
  property string title: ""
  property string text: ""
  property string actionText: ""
  property real countdown: -1
  // The keyboard's toast: tinted with the hover fill, as the shell tints its selected card.
  property bool hasCursor: false

  signal actionClicked()

  readonly property real _line: Math.max(1, Style.space(2))

  color: Commons.Color.notifications.background
  borderSpec: Border.surfaceSpec("notifications", "border", Commons.Color.notifications.border, Math.max(1, Style.space(2)))
  radius: Style.cornerRadius
  leftPadding: Style.space(12)
  rightPadding: Style.space(12)
  topPadding: Style.space(10)
  bottomPadding: Style.space(10)

  implicitWidth: Style.space(360)
  implicitHeight: row.implicitHeight + contentTopInset + contentBottomInset

  Accessible.role: Accessible.AlertMessage
  Accessible.name: title

  Rectangle {
    anchors.fill: parent
    anchors { leftMargin: root.borderLeft; rightMargin: root.borderRight; topMargin: root.borderTop; bottomMargin: root.borderBottom }
    visible: root.hasCursor
    color: Style.hoverFillFor(Commons.Color.notifications.text, Commons.Color.accent)
  }

  RowLayout {
    id: row
    x: root.contentLeftInset
    y: root.contentTopInset
    width: root.width - root.contentLeftInset - root.contentRightInset
    spacing: Style.space(12)

    Text {
      visible: root.glyph !== ""
      textFormat: Text.PlainText
      text: root.glyph
      color: Commons.Color.notifications.text
      font.family: Style.font.family
      font.pixelSize: Style.font.iconLarge
      Layout.alignment: Qt.AlignVCenter
    }

    ColumnLayout {
      spacing: Style.space(3)
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter

      Text {
        textFormat: Text.PlainText
        text: root.title
        color: Commons.Color.notifications.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
        Layout.fillWidth: true
      }

      Text {
        visible: root.text !== ""
        textFormat: Text.PlainText
        text: root.text
        color: Qt.darker(Commons.Color.notifications.text, 1.15)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
        Layout.fillWidth: true
      }
    }

    Button {
      visible: root.actionText !== ""
      text: root.actionText
      bordered: true
      focusable: true
      foreground: Commons.Color.notifications.text
      Layout.alignment: Qt.AlignVCenter
      onClicked: root.actionClicked()
    }
  }

  // Time left, shrinking toward the leading edge; kept clear of rounded corners.
  Rectangle {
    visible: root.countdown >= 0
    x: root.borderLeft + root.radius
    y: root.height - root.borderBottom - height
    width: (root.width - root.borderLeft - root.borderRight - root.radius * 2) * Math.max(0, Math.min(1, root.countdown))
    height: root._line
    color: Commons.Color.notifications.countdown
  }
}
