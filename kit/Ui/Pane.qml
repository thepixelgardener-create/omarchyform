import QtQuick
import QtQuick.Layouts
import "../Theme"
import "../Theme" as Commons

// A flat surface inside an app window: an inspector, a side panel, a settings group. Not a Card
// (the raised [popups] surface with the accent border): a pane sits on the window, so by default
// it draws nothing but its padding, plus a hairline track rule on one side against its
// neighbour (`divider`). `bordered` gives it the controls' normal glass instead, with the
// theme's corners, for a group set off inside a page. Never a shadow.
//
//   Pane {
//     title: "Layers"; subtitle: "3 items"; divider: "left"
//     actions: [ IconButton { iconText: "" } ]
//     MenuRow { text: "Background" }
//   }
//
// The header is a Heading (title level) with `actions` as its trailing slot. Children stack in a
// column under it, panelGap apart, panelPadding inside the edges.
BorderSurface {
  id: root

  property string title: ""
  property string subtitle: ""
  property alias actions: heading.trailing
  property bool bordered: false
  // "", "top", "right", "bottom" or "left": the side the rule is drawn on.
  property string divider: ""
  property color foreground: Commons.Color.foreground
  property real contentPadding: Style.spacing.panelPadding
  property real spacing: Style.spacing.panelGap
  default property alias content: body.data

  readonly property real _rule: Style.spacing.hairline

  color: bordered ? Style.normalFillFor(root.foreground, Commons.Color.accent) : "transparent"
  radius: bordered ? Style.cornerRadius : 0
  borderSpec: bordered ? Border.controlSpec("normal", root.foreground, Commons.Color.accent) : Border.none()
  topPadding: contentPadding + (divider === "top" ? _rule : 0)
  rightPadding: contentPadding + (divider === "right" ? _rule : 0)
  bottomPadding: contentPadding + (divider === "bottom" ? _rule : 0)
  leftPadding: contentPadding + (divider === "left" ? _rule : 0)

  implicitWidth: column.implicitWidth + contentLeftInset + contentRightInset
  implicitHeight: column.implicitHeight + contentTopInset + contentBottomInset

  Rectangle {
    visible: root.divider !== ""
    x: root.divider === "right" ? root.width - width : 0
    y: root.divider === "bottom" ? root.height - height : 0
    width: root.divider === "left" || root.divider === "right" ? root._rule : root.width
    height: root.divider === "top" || root.divider === "bottom" ? root._rule : root.height
    color: Commons.Color.track
  }

  ColumnLayout {
    id: column
    x: root.contentLeftInset
    y: root.contentTopInset
    width: root.width - root.contentLeftInset - root.contentRightInset
    spacing: root.spacing

    Heading {
      id: heading
      visible: root.title !== ""
      text: root.title
      subtitle: root.subtitle
      foreground: root.foreground
      Layout.fillWidth: true
    }

    ColumnLayout {
      id: body
      spacing: root.spacing
      Layout.fillWidth: true
    }
  }
}
