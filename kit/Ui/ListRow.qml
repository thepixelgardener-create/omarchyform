import QtQuick
import "../Theme"
import "../Theme" as Commons

// One row of a keyboard-and-mouse list: what the shell's network, bluetooth, tailscale and audio
// panels each build by hand on CursorSurface.
//
//   ListRow {
//     glyph: "󰖩"; title: "Basecamp"; status: "Connected"; statusTone: "success"
//     current: true                                 // the connected one
//     hasCursor: cursor.isAt("wifi", index)         // a CursorModel drives the cursor
//     trailingGlyph: "󰌾"                            // the lock, at rest
//     actionGlyph: "󰅙"; actionUrgent: true          // forget, in its place under the cursor
//     onClicked: connect()
//     onActionClicked: forget()
//     onPointerMoved: function(mouse) { cursor.pointerMoved(this, mouse, "wifi", index) }
//   }
//
// Leading: a glyph, or any item through `leading` (an Avatar). Then a bold title, a dim subtitle
// and a status line tinted by `statusTone`. Trailing: `value` text, or any item through
// `trailing` (a Badge, a non-interactive ToggleSwitch), then the slot at the end, which holds
// `trailingGlyph` (a lock, signal bars, a drill-in chevron, a check) at rest and the action in
// its place while the action shows, as the network panel's lock turns into forget.
//
// Like CursorSurface, the row never reads hover for its look: the cursor (`hasCursor`) is the one
// highlight, and pointer movement reaches the app through `pointerMoved` so it can move the
// cursor there. The action glyph shows while the row has the cursor or the pointer, or when the
// action itself has the cursor (`actionCursor`), which tints it urgent if `actionUrgent`.
//
// `expansion` opens the row: any item (the network panel's password field and Connect button)
// across the row under its main line, inside the row's fill.
CursorSurface {
  id: root

  property string glyph: ""
  property real glyphSize: Style.font.title
  property color glyphColor: foreground
  property Component leading: null

  property string title: ""
  property string subtitle: ""
  property string status: ""
  // "", "accent", "success", "warning", "urgent". Empty is dim.
  property string statusTone: ""

  property string value: ""
  property Component trailing: null

  // A glyph that stays in the end slot, dim unless `trailingTone` tints it ("accent" for a check).
  property string trailingGlyph: ""
  property string trailingTone: ""

  property string actionGlyph: ""
  property bool actionUrgent: false
  property bool actionCursor: false
  property string actionTip: ""

  property bool disabled: false
  property Component expansion: null

  signal clicked()
  signal actionClicked()
  // The pointer moved over the row (not content scrolling under a still pointer): hand it to
  // CursorModel.pointerMoved, which filters synthetic hover the way PointerMoveGate does.
  signal pointerMoved(var mouse)
  signal hovered()

  readonly property bool pointerInside: rowMouse.containsMouse || actionMouse.containsMouse
  readonly property bool actionShown: actionGlyph !== "" && !disabled && (hasCursor || actionCursor || pointerInside)

  readonly property color titleColor: disabled ? Commons.Color.textFaint : foreground
  readonly property color dimColor: disabled ? Commons.Color.textFaint : Commons.Color.textDim
  function toneColor(tone) {
    if (disabled) return Commons.Color.textFaint
    switch (tone) {
    case "accent": return Commons.Color.accent
    case "success": return Commons.Color.success
    case "warning": return Commons.Color.warning
    case "urgent": return Commons.Color.urgent
    case "muted": return Commons.Color.muted
    }
    return Commons.Color.textDim
  }

  hasCursor: false
  width: parent ? parent.width : implicitWidth
  implicitWidth: body.implicitWidth + Style.spacing.controlPaddingX * 2
  implicitHeight: body.implicitHeight + Style.spacing.rowPaddingX
                  + (expansionLoader.item ? expansionLoader.height + Style.space(4) : 0)

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: !root.disabled
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: if (containsMouse) root.hovered()
    onPositionChanged: function(mouse) { root.pointerMoved(mouse) }
    onClicked: root.clicked()
  }

  Item {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.spacing.controlPaddingX
    anchors.rightMargin: Style.spacing.controlPaddingX
    // Centered, or at the top padding when an expansion hangs under it.
    y: expansionLoader.item ? Style.spacing.rowPaddingX / 2 : Math.round((root.height - height) / 2)
    implicitWidth: lead.width + info.implicitWidth + trailBox.width
    implicitHeight: Math.max(lead.implicitHeight, info.implicitHeight, trailBox.implicitHeight)

    // A fixed slot (iconLarge wide), so titles line up down a list whatever leads them: glyphs
    // center in it and a small Avatar fills it.
    Item {
      id: lead
      readonly property bool shown: root.leading !== null || root.glyph !== ""
      width: shown ? Style.font.iconLarge + Style.space(10) : 0
      implicitHeight: Math.max(leadGlyph.visible ? leadGlyph.implicitHeight : 0, leadLoader.item ? leadLoader.height : 0)
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter

      Text {
        id: leadGlyph
        visible: root.leading === null && root.glyph !== ""
        // Centered by its box (advance plus any overhang), as the Rune binding's glyphs are.
        x: Math.round((Style.font.iconLarge - implicitWidth) / 2)
        textFormat: Text.PlainText
        text: root.glyph
        color: root.disabled ? Commons.Color.textFaint : root.glyphColor
        font.family: Style.font.family
        font.pixelSize: root.glyphSize
        anchors.verticalCenter: parent.verticalCenter
      }

      Loader {
        id: leadLoader
        sourceComponent: root.leading
        x: Math.round((Style.font.iconLarge - width) / 2)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Column {
      id: info
      anchors.left: lead.right
      anchors.right: trailBox.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.title
        color: root.titleColor
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        textFormat: Text.PlainText
        visible: root.subtitle !== ""
        width: parent.width
        text: root.subtitle
        color: root.dimColor
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
      Text {
        textFormat: Text.PlainText
        visible: root.status !== ""
        width: parent.width
        text: root.status
        color: root.toneColor(root.statusTone)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    // Value or trailing item, then the end slot: the trailing glyph at rest, the action in its
    // place while it shows. The slot keeps its width while empty, so revealing the action never
    // reflows the row.
    Row {
      id: trailBox
      readonly property bool hasValue: root.value !== "" && root.trailing === null
      readonly property bool hasAny: hasValue || root.trailing !== null || actionSlot.visible
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: hasAny ? implicitWidth + Style.space(8) : 0
      layoutDirection: Qt.RightToLeft
      spacing: Style.space(8)

      Item {
        id: actionSlot
        visible: root.actionGlyph !== "" || root.trailingGlyph !== ""
        width: Style.space(22)
        height: width
        anchors.verticalCenter: parent.verticalCenter

        BorderSurface {
          anchors.fill: parent
          visible: root.actionCursor && !root.disabled
          readonly property color ink: root.actionUrgent ? Commons.Color.urgent : root.foreground
          // The cursor look in the action's own ink, whatever color the theme gives the cursor.
          color: Commons.Util.alpha(ink, Style.hoverFillAlpha)
          borderSpec: Border.flat(Commons.Util.alpha(ink, Style.hoverBorderAlpha), Style.hoverBorderWidth)
          radius: Style.cornerRadius
        }

        Text {
          visible: root.actionShown
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.actionGlyph
          color: root.actionUrgent ? Commons.Color.urgent : Commons.Color.textDim
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
        }

        Text {
          visible: root.trailingGlyph !== "" && !root.actionShown
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.trailingGlyph
          color: root.toneColor(root.trailingTone)
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
        }

        MouseArea {
          id: actionMouse
          anchors.fill: parent
          hoverEnabled: true
          enabled: !root.disabled && root.actionGlyph !== ""
          cursorShape: Qt.PointingHandCursor
          onPositionChanged: function(mouse) { root.pointerMoved(mouse) }
          onClicked: root.actionClicked()
        }

        PanelToolTip {
          visible: root.actionTip !== "" && (actionMouse.containsMouse || root.actionCursor)
          text: root.actionTip
        }
      }

      Loader {
        id: trailLoader
        sourceComponent: root.trailing
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        visible: trailBox.hasValue
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.value
        color: root.dimColor
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  Loader {
    id: expansionLoader
    active: root.expansion !== null
    sourceComponent: root.expansion
    x: Style.spacing.controlPaddingX
    y: body.y + body.height + Style.space(4)
    width: root.width - Style.spacing.controlPaddingX * 2
  }
}
