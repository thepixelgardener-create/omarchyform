import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "BoardStore.js" as Store
import "kit/Theme" as Kit

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
  // A value off the shell's Style by its path ("font.body"), through the
  // same guard: one closure for every read rather than one each.
  function style(path, fallback) {
    return theme.token(function () {
      var v = Commons.Style
      var parts = path.split(".")
      for (var i = 0; i < parts.length; i++) v = v[parts[i]]
      return v
    }, fallback)
  }
  function sp(n) { return theme.token(function () { return Commons.Style.space(n) }, n) }

  property color canvasBackground: theme.token(function () { return Commons.Color.background }, "#101315")
  property color foreground: theme.token(function () { return Commons.Color.foreground }, "#CACCCC")
  property color accent: theme.token(function () { return Commons.Color.accent }, "#CACCCC")
  property color urgent: theme.token(function () { return Commons.Color.urgent }, "#A55555")
  property color muted: theme.token(function () { return Commons.Color.muted }, "#707880")

  // The theme's own font, at the theme's own sizes, so the board follows
  // `omarchy display text size` like everything else on the desktop.
  property string fontFamily: theme.style("font.family",
                                          theme.style("font.menuFamily", "monospace"))
  readonly property int fontBody: theme.style("font.body", 12)
  readonly property int fontSubtitle: theme.style("font.subtitle", 13)
  readonly property int fontHeading: theme.style("font.heading", 16)
  // The board's panels and its header — the command list, the browser, help,
  // the two-versions question — are drawn with the Omarchy UI kit (kit/), which
  // resolves their colours and sizes itself from what feedKit() below hands
  // it. What is left here is the board: the canvas and what is drawn on it.

  // Omarchy is square-cornered with hairline borders by default; both come
  // from the theme rather than being invented here.
  readonly property int cornerRadius: theme.style("cornerRadius", 0)
  readonly property int borderWidth: Math.max(1, theme.style("normalBorderWidth", 1))

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
  readonly property real normalFillAlpha: theme.style("normalFillAlpha", 0.04)
  readonly property real selectedFillAlpha: theme.style("selectedFillAlpha", 0.18)
  readonly property real normalBorderAlpha: theme.style("normalBorderAlpha", 0.4)

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
  onCanvasBackgroundChanged: { themeFile.reload(); kitShellFile.reload(); kitNameFile.reload() }

  // The mode is read from the theme's own file rather than guessed from the
  // background, and followed while the board is open: switching theme
  // retargets the symlink this watches.
  FileView {
    id: themeFile
    path: theme.themePath
    watchChanges: true
    printErrors: false
    onLoaded: { theme.themeMode = Store.parseThemeMode(text()); theme.feedKit() }
    onLoadFailed: { theme.themeMode = ""; theme.feedKit() }
    onFileChanged: reload()
  }

  // The Omarchy UI kit's panels (kit/) resolve their own tokens from the same
  // files the shell resolves its from. A plugin cannot load the kit's C++
  // reader, so these hand the files and the shell's Hyprland and font values to
  // its stand-in (kit/Theme/ThemeSource.qml), all at once, whenever one moves.
  readonly property string kitThemeDir: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme"
  readonly property string kitConfigDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy"
  readonly property int kitRounding: theme.cornerRadius
  // The kit halves Hyprland's gaps itself; the shell has already halved them.
  readonly property real kitGaps: theme.style("gapsOut", 5) * 2
  readonly property bool kitAnimations: !theme.style("reduceMotion", false)
  readonly property string kitFont: theme.style("fontFamily", "monospace")
  readonly property string kitResolvedFont: theme.style("resolvedFontFamily", theme.kitFont)
  onKitRoundingChanged: theme.feedKit()
  onKitGapsChanged: theme.feedKit()
  onKitAnimationsChanged: theme.feedKit()
  onKitFontChanged: theme.feedKit()
  onKitResolvedFontChanged: theme.feedKit()

  function fileText(view) {
    try { return view.loaded ? view.text() : "" } catch (e) { return "" }
  }
  function feedKit() {
    Kit.ThemeSource.apply({
      colorsText: theme.fileText(themeFile),
      shellText: theme.fileText(kitShellFile),
      userShellText: theme.fileText(kitUserShellFile),
      themeName: theme.fileText(kitNameFile).trim(),
      languageText: theme.fileText(kitLanguageFile).trim(),
      themeDir: theme.kitThemeDir,
      rounding: theme.kitRounding,
      gapsOut: theme.kitGaps,
      animations: theme.kitAnimations,
      fontFamily: theme.kitFont,
      resolvedFontFamily: theme.kitResolvedFont
    })
  }
  Component.onCompleted: theme.feedKit()

  FileView {
    id: kitShellFile
    path: theme.kitThemeDir + "/shell.toml"
    watchChanges: true
    printErrors: false
    onLoaded: theme.feedKit()
    onLoadFailed: theme.feedKit()
    onFileChanged: reload()
  }
  FileView {
    id: kitUserShellFile
    path: theme.kitConfigDir + "/shell.toml"
    watchChanges: true
    printErrors: false
    onLoaded: theme.feedKit()
    onLoadFailed: theme.feedKit()
    onFileChanged: reload()
  }
  FileView {
    id: kitNameFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onLoaded: theme.feedKit()
    onFileChanged: reload()
  }
  FileView {
    id: kitLanguageFile
    path: theme.kitConfigDir + "/language"
    watchChanges: true
    printErrors: false
    onLoaded: theme.feedKit()
    onLoadFailed: theme.feedKit()
    onFileChanged: reload()
  }
}
