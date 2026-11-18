import QtQuick
import QtQuick.Layouts
import "../Theme"
import "../Theme" as Commons

// A raised surface: what the shell's panels, popups and flyouts are drawn on. Background, text
// and border come from [popups] in shell.toml (the border follows Hyprland's active border by
// default), corners from Hyprland's rounding, padding and gaps from the spacing scale.
//
//   Card {
//     title: "Network"
//     Toggle { label: "Wi-Fi"; checked: true }
//   }
//
// Children stack in a column, panelGap apart. `title` adds a section header above them.
BorderSurface {
  id: root

  property string title: ""
  property color foreground: Commons.Color.popups.text
  property real contentPadding: Style.spacing.panelPadding
  property real spacing: Style.spacing.panelGap
  default property alias content: body.data

  color: Commons.Color.popups.background
  radius: Style.cornerRadius
  borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
  padding: contentPadding

  implicitWidth: column.implicitWidth + contentLeftInset + contentRightInset
  implicitHeight: column.implicitHeight + contentTopInset + contentBottomInset

  ColumnLayout {
    id: column
    x: root.contentLeftInset
    y: root.contentTopInset
    width: root.width - root.contentLeftInset - root.contentRightInset
    spacing: root.spacing

    PanelSectionHeader {
      visible: root.title !== ""
      text: root.title
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
