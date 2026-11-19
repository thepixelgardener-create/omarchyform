import QtQuick
import QtQuick.Layouts
import "../Theme"
import "../Theme" as Commons

// The title of a pane, toolbar, section or page: one bold line at a font token's size, an
// optional dim subtitle under it, and an optional trailing slot of actions. Not SectionHeader
// (the caption-sized dim label over a group of rows) and not Hero (a shell panel's glyph, title
// and uppercased status).
//
//   Heading { text: "Appearance"; subtitle: "Theme, font and rounding"; level: "heading" }
//   Heading { text: "Layers"; IconButton { iconText: "" } }     // children go to `trailing`
//   Heading { text: "notes.md"; centered: true }                // a toolbar's title
//
// Levels: "title" (panes, toolbars), "heading" (sections, dialogs), "display" (pages). Both lines
// elide; trailing items sit xxs apart, controlGap after the lines, centered against them.
Item {
  id: root

  property string text: ""
  property string subtitle: ""
  property string level: "title"
  property bool centered: false
  property color foreground: Commons.Color.foreground
  default property alias trailing: trailingRow.data

  readonly property int titleSize: level === "display" ? Style.font.display
    : level === "heading" ? Style.font.heading : Style.font.title
  readonly property int subtitleSize: level === "display" ? Style.font.subtitle
    : level === "heading" ? Style.font.body : Style.font.bodySmall
  readonly property real _trailingInset: trailingRow.implicitWidth > 0 ? trailingRow.implicitWidth + Style.spacing.controlGap : 0

  implicitWidth: Math.ceil(Math.max(titleText.implicitWidth, subtitleText.visible ? subtitleText.implicitWidth : 0)) + _trailingInset
  implicitHeight: Math.max(labels.implicitHeight, trailingRow.implicitHeight)

  Accessible.role: Accessible.Heading
  Accessible.name: text

  Column {
    id: labels
    width: Math.max(0, root.width - root._trailingInset)
    y: Math.round((root.height - implicitHeight) / 2)
    spacing: Style.spacing.xxs

    Text {
      id: titleText
      textFormat: Text.PlainText
      width: parent.width
      text: root.text
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: root.titleSize
      font.bold: true
      elide: Text.ElideRight
      horizontalAlignment: root.centered ? Text.AlignHCenter : Text.AlignLeft
    }

    Text {
      id: subtitleText
      textFormat: Text.PlainText
      visible: root.subtitle !== ""
      width: parent.width
      text: root.subtitle
      color: Commons.Color.textDim
      font.family: Style.font.family
      font.pixelSize: root.subtitleSize
      elide: Text.ElideRight
      horizontalAlignment: root.centered ? Text.AlignHCenter : Text.AlignLeft
    }
  }

  RowLayout {
    id: trailingRow
    x: root.width - implicitWidth
    y: Math.round((root.height - implicitHeight) / 2)
    spacing: Style.spacing.xxs
  }
}
