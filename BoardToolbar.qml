import QtQuick
import "BoardStore.js" as Store
import "kit/Ui" as O
import "kit/Theme" as Kit

// The board name stays left; viewport controls stay in one predictable place.
// Between them, the line of keys or whatever the board is saying: Board lays
// it over the bar, and the bar says where it goes.
//
// Drawn with the Omarchy UI kit: the bar's colours as the kit resolves them,
// its icon buttons with their tooltips for fit and the menu, and its plain
// buttons for the menu's entries, the keyboard cursor on one as on any kit
// control. The layout stays here, because the line has to fit around it.
Rectangle {
  id: toolbar
  required property var ctl
  function sp(n) { return Kit.Style.space(n) }
  // The bar's icons, a step over the title beside them so a glyph reads as
  // clearly as the word it stands for.
  readonly property int iconSize: Kit.Style.font.icon
  readonly property color barText: Kit.Color.bar.text
  // Solid, as the shell's bar is. It was the bar colour at 0.92, and the text of
  // a note passing under the header read through it, text over text.
  color: Qt.rgba(Kit.Color.bar.background.r, Kit.Color.bar.background.g, Kit.Color.bar.background.b, 1)
  border.width: Math.max(1, Kit.Style.normalBorderWidth)
  border.color: Kit.Color.track
  radius: Kit.Style.cornerRadius
  // Inset as the kit's Toolbar is: sm inside each edge.
  readonly property real pad: Kit.Style.spacing.sm
  implicitHeight: content.height + toolbar.pad * 2
  MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

  // The line, as Board has it: how wide it is on one line, 0 when there is
  // none, and how tall it is where it has been put.
  property real lineWidth: 0
  property real lineHeight: 0
  readonly property real lineGap: toolbar.sp(16)
  // Beside the name when it fits between the name and the buttons, and on a
  // row of its own under them, wrapping, when it does not.
  readonly property real lineRoom: actions.x - (identity.x + identity.width) - 2 * lineGap
  readonly property bool lineBeside: lineWidth <= Math.max(0, lineRoom)
  // Where it goes, in the bar's own coordinates. Beside the name it is centred
  // on the bar, as it was centred under it, unless that would run it into
  // either end.
  readonly property real lineX: lineBeside
    ? content.x + Math.max(identity.x + identity.width + lineGap,
                           Math.min((content.width - lineWidth) / 2, actions.x - lineGap - lineWidth))
    : content.x
  readonly property real lineY: lineBeside
    ? content.y + (topRow.height - lineHeight) / 2
    : content.y + topRow.height + toolbar.sp(8)
  readonly property real lineSpan: lineBeside ? lineWidth : content.width

  Item {
    id: content
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: toolbar.pad }
    height: topRow.height + (toolbar.lineBeside ? 0 : toolbar.lineHeight + toolbar.sp(8))
      + (menu.visible ? menu.height + toolbar.sp(12) : 0)

    Item {
      id: topRow
      width: parent.width
      // Tall enough for the line too when it sits beside the name: its keys
      // are buttons, with a little room round each to light on hover.
      height: Math.max(identity.height, actions.height, toolbar.lineBeside ? toolbar.lineHeight : 0)

      Row {
        id: identity
        anchors.left: parent.left
        anchors.leftMargin: toolbar.sp(6)
        anchors.verticalCenter: parent.verticalCenter
        spacing: toolbar.sp(10)
        Text {
          textFormat: Text.PlainText
          id: title
          objectName: "board-title"
          width: Math.min(implicitWidth, Math.max(0, topRow.width - actions.width
            - toolbar.sp(36) - saveMark.width - identity.spacing))
          text: toolbar.ctl.boardTitle
          elide: Text.ElideRight
          color: toolbar.barText
          font.family: Kit.Style.font.family
          font.pixelSize: Kit.Style.font.title
          font.bold: true
          font.underline: titleMouse.containsMouse
          Accessible.role: Accessible.Button
          Accessible.name: toolbar.ctl.t("Rename %1", toolbar.ctl.boardTitle)
          Accessible.onPressAction: toolbar.ctl.renameBoard()
          MouseArea {
            id: titleMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: toolbar.ctl.renameBoard()
          }
        }
        // A disk when the board is in its file. The words it stands for are
        // still there for whatever reads the bar aloud.
        Text {
          id: saveMark
          objectName: "save-mark"
          readonly property string mark: toolbar.ctl.saveMark
          textFormat: Text.PlainText
          text: saveMark.mark === "opening" ? toolbar.ctl.boardState : Store.SAVE_GLYPHS[saveMark.mark]
          // Secondary, as the words were: the bar's own text held back, not the
          // theme's muted token, which a theme may set almost to its
          // background. Not yet written takes the accent, and cannot be
          // written the urgent colour, both at full strength.
          opacity: saveMark.mark === "saved" || saveMark.mark === "opening" ? 0.85 : 1
          color: saveMark.mark === "failed" || saveMark.mark === "readonly" ? Kit.Color.urgent
            : saveMark.mark === "unsaved" ? Kit.Color.accent : toolbar.barText
          font.family: Kit.Style.font.family
          font.pixelSize: saveMark.mark === "opening" ? Kit.Style.font.body : toolbar.iconSize
          anchors.verticalCenter: title.verticalCenter
          Accessible.role: Accessible.StaticText
          Accessible.name: toolbar.ctl.boardState
          readonly property alias tooltip: saveMarkTip
          MouseArea {
            id: saveMarkMouse
            anchors.fill: parent
            hoverEnabled: true
          }
          O.Tooltip {
            id: saveMarkTip
            objectName: "save-mark-tooltip"
            visible: saveMarkMouse.containsMouse && toolbar.ctl.boardState !== ""
            text: toolbar.ctl.boardState
            y: saveMark.height + Kit.Style.spacing.sm
          }
        }
      }

      Row {
        id: actions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Kit.Style.spacing.xxs
        O.PanelActionButton {
          objectName: "fit-button"
          iconText: Store.FIT_GLYPH
          tooltipText: toolbar.ctl.t("Fit board to window, zoom %1 percent", Math.round(toolbar.ctl.zoom * 100))
          foreground: toolbar.barText
          fontSize: toolbar.iconSize
          Accessible.role: Accessible.Button
          Accessible.name: tooltipText
          Accessible.onPressAction: toolbar.ctl.fitToItems()
          onClicked: toolbar.ctl.fitToItems()
        }
        O.PanelActionButton {
          objectName: "menu-button"
          iconText: Store.MENU_GLYPH
          tooltipText: toolbar.ctl.menuVisible ? toolbar.ctl.t("Close board menu") : toolbar.ctl.t("Open board menu")
          // Open, it is what is chosen: edged and lit, as a kit control is
          // under the cursor.
          hasCursor: toolbar.ctl.menuVisible
          bordered: toolbar.ctl.menuVisible
          foreground: toolbar.ctl.menuVisible ? Kit.Color.accent : toolbar.barText
          fontSize: toolbar.iconSize
          Accessible.role: Accessible.Button
          Accessible.name: tooltipText
          Accessible.onPressAction: toolbar.ctl.toggleMenu()
          onClicked: toolbar.ctl.toggleMenu()
        }
      }
    }

    Flow {
      id: menu
      visible: toolbar.ctl.menuVisible
      anchors { left: parent.left; right: parent.right; top: topRow.bottom
                leftMargin: identity.anchors.leftMargin; rightMargin: identity.anchors.leftMargin
                topMargin: (toolbar.lineBeside ? 0 : toolbar.lineHeight + toolbar.sp(8)) + toolbar.sp(12) }
      spacing: Kit.Style.spacing.md
      Repeater {
        model: Store.menuEntries(toolbar.ctl.zoomMenuVisible)
        delegate: O.Button {
          id: entry
          required property var modelData
          required property int index
          // Unboxed, as the bar's other controls are: lit under the pointer
          // and the keyboard cursor alike, as on every kit control.
          hasCursor: toolbar.ctl.menuIndex === index
          foreground: toolbar.barText
          text: entry.modelData.id === "zoom" ? toolbar.ctl.tv(entry.modelData.label) + " " + Math.round(toolbar.ctl.zoom * 100) + "%"
            : toolbar.ctl.tv(entry.modelData.label)
          Accessible.role: Accessible.Button
          Accessible.name: text
          Accessible.focused: toolbar.ctl.menuIndex === index
          Accessible.onPressAction: toolbar.ctl.runMenu(index)
          onClicked: toolbar.ctl.runMenu(index)
        }
      }
    }
  }
}
