import QtQuick
import "BoardStore.js" as Store

// The colours a board is drawn in: the theme's own on the canvas colour chosen
// for it, or one of the PNG export's palettes, whose fills and borders are
// named outright rather than blended. The live board and a picture of it both
// draw through one of these, and a Board or a Node cannot tell it from the
// theme: everything they read is here, and tests/contract.js holds the two
// shapes together.
QtObject {
  id: colours
  required property var base
  // An entry of Store.EXPORT_PALETTES, or null for the theme's colours.
  property var chosen: null
  // Without a palette, how the theme's background is shaded: one of
  // Store.CANVAS_COLOURS.
  property string shade: "Theme"
  // A picture has nothing selected in it, so a tint that would be drawn
  // strongly on screen is drawn plainly.
  property bool plain: false

  readonly property color canvasBackground: colours.chosen ? colours.chosen.background
    : colours.shaded(colours.base.canvasBackground, colours.shade, colours.base.isLight)
  readonly property color foreground: colours.chosen ? colours.chosen.foreground : colours.base.foreground
  readonly property color accent: colours.chosen ? colours.chosen.borders.accent : colours.base.accent
  readonly property color urgent: colours.chosen ? colours.chosen.borders.urgent : colours.base.urgent
  readonly property color muted: colours.chosen ? colours.chosen.borders.muted : colours.base.muted
  // A palette's connector colour is already the weight it wants against its
  // own background; the theme's text is held back to be one.
  readonly property color connector: colours.chosen ? colours.chosen.connector : colours.base.foreground
  readonly property real connectorAlpha: colours.chosen ? 1 : Store.CONNECTOR_ALPHA
  readonly property bool isLight: colours.chosen
    ? Store.isLightColor(colours.canvasBackground.r, colours.canvasBackground.g, colours.canvasBackground.b)
    : colours.base.isLight
  readonly property color dotColor: colours.chosen
    ? Qt.rgba(colours.foreground.r, colours.foreground.g, colours.foreground.b, colours.isLight ? 0.13 : 0.08)
    : colours.base.dotColor
  // A note's coloured spans follow whatever it is drawn in, as its fill does.
  readonly property var markupColors: colours.chosen ? ({
    foreground: colours.chosen.foreground,
    accent: colours.chosen.borders.accent,
    urgent: colours.chosen.borders.urgent,
    muted: colours.chosen.borders.muted
  }) : colours.base.markupColors

  readonly property string fontFamily: colours.base.fontFamily
  readonly property int fontBody: colours.base.fontBody
  readonly property int fontSubtitle: colours.base.fontSubtitle
  readonly property int fontHeading: colours.base.fontHeading
  readonly property int borderWidth: colours.base.borderWidth
  readonly property int cornerRadius: colours.base.cornerRadius
  readonly property color panelScrim: colours.base.panelScrim
  function sp(n) { return colours.base.sp(n) }

  function shaded(c, shade, light) {
    var s = Store.canvasShade(c.r, c.g, c.b, shade, light)
    return Qt.rgba(s.r, s.g, s.b, 1)
  }
  function tintFill(tint, strong) {
    return colours.chosen ? Store.paletteTint(colours.chosen, "fills", tint)
      : colours.base.tintFill(tint, strong && !colours.plain, colours.canvasBackground)
  }
  function tintBorder(tint, strong) {
    return colours.chosen ? Store.paletteTint(colours.chosen, "borders", tint)
      : colours.base.tintBorder(tint, strong && !colours.plain)
  }
}
