pragma Singleton
import QtQuick

// The plugin's stand-in for the kit's C++ ThemeSource (qt/src/themesource.cpp in
// omarchy-ui), which a shell plugin cannot load. Same properties, same signals;
// the kit's Color, Style, I18n and Tokens read it unchanged.
//
// It reads nothing itself. Theme.qml fills it from the files the shell reads
// (the current theme's colors.toml and shell.toml, ~/.config/omarchy/shell.toml,
// the language file) and from the shell's own Hyprland and font values, then
// calls apply(). A test fills it from a fixture the same way, so the kit draws
// in the suite exactly as it does on a desktop, with no shell present.
//
// Written here, not copied: tools/vendor-kit.js leaves this file alone.
QtObject {
  id: root

  property string colorsText: ""
  property string shellText: ""
  property string userShellText: ""
  property string themeName: ""
  property string iconTheme: ""
  property string languageText: ""
  property string themeDir: ""
  property bool pinned: false
  property int rounding: 0
  property real gapsOut: 0
  property bool animations: true
  property int borderSize: 1
  property string fontFamily: "monospace"
  property string resolvedFontFamily: "monospace"

  signal themeChanged()
  signal hyprlandChanged()
  signal fontChanged()
  signal languageChanged()
  signal settled()

  // One change of everything at once: the kit re-reads the theme, announces
  // the new tokens and fades to them, once, as it does after the C++ source's
  // coalesced reload. Unchanged values are skipped so nothing fades for nothing.
  function apply(values) {
    var theme = false, hypr = false, font = false, language = false
    function set(key) {
      if (values[key] === undefined || values[key] === root[key]) return false
      root[key] = values[key]
      return true
    }
    if (set("colorsText")) theme = true
    if (set("shellText")) theme = true
    if (set("userShellText")) theme = true
    if (set("themeName")) theme = true
    if (set("iconTheme")) theme = true
    if (set("rounding")) hypr = true
    if (set("gapsOut")) hypr = true
    if (set("animations")) hypr = true
    if (set("borderSize")) hypr = true
    if (set("fontFamily")) font = true
    if (set("resolvedFontFamily")) font = true
    if (set("languageText")) language = true
    if (theme) root.themeChanged()
    if (hypr) root.hyprlandChanged()
    if (font) root.fontChanged()
    if (language) root.languageChanged()
    if (theme || hypr || font || language) root.settled()
  }

  function reload() {}
  // The C++ source hands the tokens to C++ listeners. There are none here;
  // Tokens.changed is the hook QML listens to.
  function publishTokens(tokens, revision, change) {}
}
