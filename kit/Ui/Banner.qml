import QtQuick
import QtQuick.Layouts
import "../Theme"
import "../Theme" as Commons

// An inline message in the page: a tone glyph, the text, an optional action and an optional
// dismiss. Flat, as everything in Omarchy is: a foreground-glass fill with a border in the tone,
// never a filled saturated background.
//
//   Banner { tone: "warning"; text: "Battery is low (12%)" }
//   Banner { text: "Omarchy 3.2 is available"; actionText: "Update"; dismissible: true }
//
// `tone` is "info" (accent, the default), "success", "warning" or "error" (urgent); each brings
// its own glyph unless `glyph` is set.
BorderSurface {
  id: root

  property string text: ""
  property string tone: "info"
  property string glyph: ""
  property string actionText: ""
  property bool dismissible: false
  // Forces the action's hover-cursor look, for keyboard-driven panels.
  property bool hasCursor: false

  signal actionClicked()
  signal dismissed()

  readonly property color toneColor: tone === "success" ? Commons.Color.success
    : tone === "warning" ? Commons.Color.warning
    : tone === "error" ? Commons.Color.urgent
    : Commons.Color.accent
  readonly property string toneGlyph: glyph !== "" ? glyph
    : tone === "success" ? "\u{f012c}"
    : tone === "warning" ? "\u{f002a}"
    : tone === "error" ? "\u{f015a}"
    : "\u{f02fd}"
  readonly property bool _trailing: actionText !== "" || dismissible

  color: Style.normalFillFor(Commons.Color.foreground, Commons.Color.accent)
  borderSpec: Border.flat(root.toneColor, Math.max(1, Style.normalBorderWidth))
  radius: Style.cornerRadius
  leftPadding: Style.spacing.controlPaddingX
  rightPadding: _trailing ? Style.spacing.sm : Style.spacing.controlPaddingX
  topPadding: Style.spacing.sm
  bottomPadding: Style.spacing.sm

  implicitWidth: row.implicitWidth + contentLeftInset + contentRightInset
  implicitHeight: Math.max(Style.spacing.controlHeight, row.implicitHeight) + contentTopInset + contentBottomInset

  Accessible.role: Accessible.AlertMessage
  Accessible.name: text

  RowLayout {
    id: row
    x: root.contentLeftInset
    y: root.contentTopInset + Math.round((root.height - root.contentTopInset - root.contentBottomInset - height) / 2)
    width: root.width - root.contentLeftInset - root.contentRightInset
    spacing: Style.spacing.controlGap

    Text {
      textFormat: Text.PlainText
      text: root.toneGlyph
      color: root.toneColor
      font.family: Style.font.family
      font.pixelSize: Style.font.icon
      Layout.alignment: Qt.AlignVCenter
    }

    Text {
      textFormat: Text.PlainText
      text: root.text
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
    }

    Button {
      visible: root.actionText !== ""
      text: root.actionText
      bordered: true
      focusable: true
      hasCursor: root.hasCursor
      Layout.alignment: Qt.AlignVCenter
      onClicked: root.actionClicked()
    }

    PanelActionButton {
      visible: root.dismissible
      iconText: "\u{f0156}"
      focusable: true
      Accessible.name: "Dismiss"
      Layout.alignment: Qt.AlignVCenter
      onClicked: root.dismissed()
    }
  }
}
