import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "BoardStore.js" as Store

// What the board looks like, which is whatever Omarchy looks like.
//
// Every read of the shell's internal singletons goes through a guard: they are
// not a versioned API, and a rename upstream should cost a wrong colour, not a
// board that refuses to open. (An import that disappears entirely is still
// fatal — QML has no optional imports.)
//
// It is a component rather than twenty properties on the controller so that a
// test can hold the real thing. The layout suite used to hand-write a palette
// for its stub, and a panel that read one more colour than the stub declared
// failed on a desktop rather than in the suite.
Item {
  id: theme

  function token(read, fallback) {
    try {
      var v = read()
      return v === undefined || v === null ? fallback : v
    } catch (e) {
      return fallback
    }
  }
  function sp(n) { return theme.token(function () { return Commons.Style.space(n) }, n) }

  property color canvasBackground: theme.token(function () { return Commons.Color.background }, "#101315")
  property color foreground: theme.token(function () { return Commons.Color.foreground }, "#CACCCC")
  // The board's own header is a bar, so it is painted in the colours the theme
  // paints the desktop's bar with rather than in the canvas colour. A theme
  // that gives its bar its own background and its own text gets both here; one
  // that does not is back where it started, since those keys derive from the
  // background and foreground above.
  property color barBackground: theme.token(function () { return Commons.Color.bar.background }, theme.canvasBackground)
  property color barForeground: theme.token(function () { return Commons.Color.bar.text }, theme.foreground)
  property color accent: theme.token(function () { return Commons.Color.accent }, "#CACCCC")
  property color urgent: theme.token(function () { return Commons.Color.urgent }, "#A55555")
  property color muted: theme.token(function () { return Commons.Color.muted }, "#707880")

  // The theme's own font, at the theme's own sizes, so the board follows
  // `omarchy display text size` like everything else on the desktop.
  property string fontFamily: theme.token(function () { return Commons.Style.font.family },
                                          theme.token(function () { return Commons.Style.font.menuFamily }, "monospace"))
  readonly property int fontBody: theme.token(function () { return Commons.Style.font.body }, 12)
  readonly property int fontSubtitle: theme.token(function () { return Commons.Style.font.subtitle }, 13)
  readonly property int fontHeading: theme.token(function () { return Commons.Style.font.heading }, 16)
  // The small bold label over a section of a panel, and a row's glyph.
  readonly property int fontCaption: theme.token(function () { return Commons.Style.font.caption }, 10)
  readonly property int fontIcon: theme.token(function () { return Commons.Style.font.iconLarge }, 18)

  // The board's panels — the command list, the browser, help, the question
  // asked when a board has two versions — are summoned surfaces, and the shell
  // draws its own summoned surfaces one way: a solid card in the menu's
  // colours, the theme's border for them (a gradient, where the theme has one),
  // the desktop dimmed behind, and a soft fill under the keyboard cursor with
  // the row's label in the accent. These are those tokens, read the way the
  // menu reads them, so a panel here and the menu beside it are the same kind
  // of thing. The fallbacks are the shell's own defaults.
  property color panelBackground: theme.token(function () { return Commons.Color.menu.background }, theme.canvasBackground)
  property color panelText: theme.token(function () { return Commons.Color.menu.text }, theme.foreground)
  property color panelScrim: theme.token(function () { return Commons.Color.menu.scrim },
                                         Qt.rgba(theme.canvasBackground.r, theme.canvasBackground.g, theme.canvasBackground.b, 0.5))
  property color cursorFill: theme.token(function () { return Commons.Color.menu.selectedBackground },
                                         Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.08))
  property color cursorText: theme.token(function () { return Commons.Color.menu.selectedText }, theme.accent)
  // Plain data — a colour, four side widths and a gradient — so the panels can
  // paint it with nothing but QtQuick (Surface.qml), and a test can hand them one.
  property var panelBorder: theme.token(function () {
    return Commons.Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Commons.Style.space(2)))
  }, theme.flatSpec(theme.panelText, theme.sp(2)))
  property var cursorBorder: theme.token(function () {
    return Commons.Border.surfaceSpec("menu", "selected-border", Commons.Color.menu.selectedBorder, 0)
  }, theme.flatSpec("transparent", 0))
  // A control at rest and under the pointer, as the shell's own buttons fill
  // them: a faint wash, and a stronger one when hovered.
  property color controlFill: theme.token(function () { return Commons.Style.normalFill },
                                          Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.04))
  property color hoverFill: theme.token(function () { return Commons.Style.hoverFill },
                                        Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.08))
  // The family the shell's summoned lists use. The same as the rest unless
  // someone has set OMARCHY_MENU_FONT, which the menu honours and so do these.
  property string menuFontFamily: theme.token(function () { return Commons.Style.font.menuFamily }, theme.fontFamily)
  function flatSpec(color, width) {
    return { color: color, widths: { top: width, right: width, bottom: width, left: width },
             gradient: { colors: [], angle: 0, enabled: false } }
  }

  // Omarchy is square-cornered with hairline borders by default; both come
  // from the theme rather than being invented here.
  readonly property int cornerRadius: theme.token(function () { return Commons.Style.cornerRadius }, 0)
  readonly property int borderWidth: Math.max(1, theme.token(function () { return Commons.Style.normalBorderWidth }, 1))

  // Day or night is a property of the theme, not a setting of ours: Omarchy
  // themes declare `mode` in colors.toml. Luminance is only the fallback for a
  // third-party theme that leaves it out.
  readonly property string themePath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
  property string themeMode: ""
  readonly property bool isLight: theme.themeMode !== ""
    ? theme.themeMode === "light"
    : Store.isLightColor(theme.canvasBackground.r, theme.canvasBackground.g, theme.canvasBackground.b)

  // A wash reads differently on paper than on ink, so the weights differ.
  readonly property color dotColor: Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b,
                                            theme.isLight ? 0.13 : 0.08)

  // An item is a translucent wash of a theme role plus a hairline of the same
  // role, which is how the rest of the shell draws a surface.
  function tintColor(tint) {
    if (tint === "accent") return theme.accent
    if (tint === "urgent") return theme.urgent
    if (tint === "muted") return theme.muted
    return theme.foreground
  }
  // The four roles as markup wants them. A QML colour prints its alpha first,
  // which StyledText reads as red, so they go through hexColor on the way. One
  // object for the whole board rather than one per item: a note asks for this
  // on every repaint, and a board can hold thousands of them.
  readonly property var markupColors: ({
    foreground: Store.hexColor(theme.foreground),
    accent: Store.hexColor(theme.accent),
    urgent: Store.hexColor(theme.urgent),
    muted: Store.hexColor(theme.muted)
  })

  // The shell's surface weights, read once per theme change rather than once
  // for every item's fill.
  readonly property real normalFillAlpha: theme.token(function () { return Commons.Style.normalFillAlpha }, 0.04)
  readonly property real selectedFillAlpha: theme.token(function () { return Commons.Style.selectedFillAlpha }, 0.18)
  readonly property real normalBorderAlpha: theme.token(function () { return Commons.Style.normalBorderAlpha }, 0.4)

  // Blended against the canvas it sits on, which is the theme's background
  // unless the canvas has been shaded: `under` is that shade.
  function tintFill(tint, strong, under) {
    var c = theme.tintColor(tint)
    var bg = under === undefined ? theme.canvasBackground : under
    // Use the shell's surface weights. Coloured notes get a little more ink;
    // ordinary notes stay quiet enough that the text carries the hierarchy.
    var normal = theme.normalFillAlpha
    var selected = theme.selectedFillAlpha
    var a = strong ? selected : Math.min(1, normal + (tint === "accent" || tint === "urgent" ? 0.04 : 0.02))
    return Qt.rgba(c.r * a + bg.r * (1-a), c.g * a + bg.g * (1-a), c.b * a + bg.b * (1-a), 1)
  }
  function tintBorder(tint, strong) {
    var c = theme.tintColor(tint)
    var a = strong ? 1.0 : theme.normalBorderAlpha
    return Qt.rgba(c.r, c.g, c.b, a)
  }

  // The current theme is a symlink, so a switch retargets it rather than
  // editing the file a watcher is holding. The shell updates its own colours
  // on every theme change, so follow that instead.
  onCanvasBackgroundChanged: themeFile.reload()

  // The mode is read from the theme's own file rather than guessed from the
  // background, and followed while the board is open: switching theme
  // retargets the symlink this watches.
  FileView {
    id: themeFile
    path: theme.themePath
    watchChanges: true
    printErrors: false
    onLoaded: theme.themeMode = Store.parseThemeMode(text())
    onLoadFailed: theme.themeMode = ""
    onFileChanged: reload()
  }
}
