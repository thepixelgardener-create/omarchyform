pragma Singleton
import QtQuick
import "." as Commons

// The resolved tokens as the canonical JSON in spec/tokens.md, read back from the live Color,
// Style and Border singletons. bin/review compares this with the Rust resolver's output for
// every fixture theme, so the two bindings can't drift apart unnoticed.
//
// It is also the theme's changed hook (spec/following.md), for what bindings can't reach:
//
//   import Omarchy.Theme as Theme
//   Connections {
//     target: Theme.Tokens
//     function onChanged(tokens) { chart.recolor(tokens.palette.accent) }   // "#rrggbbaa"
//   }
//
// - changed(tokens): once per change that alters the tokens (a theme switch, `omarchy font set`,
//   a text size, a Hyprland reload, the language or icon theme), on the GUI thread, after Color
//   and Style have re-resolved (they already read the new values), before the color fade
//   starts; never for the initial load. `tokens` is canonical(): the new values, not a frame
//   of the fade.
// - revision: 0 for the initial load, plus one per change. A cache key.
// - current: the tokens in effect, as canonical() last returned them.
// C++ gets the same through OmarchyUi::Theme (qt/src/omarchyui.h).
QtObject {
  id: root

  signal changed(var tokens)
  property int revision: 0
  property var current: ({})
  // What a change is compared on: the canonical JSON, plus what's exposed beside it.
  property string lastKey: ""

  function keyOf(tokens) {
    return JSON.stringify(tokens) + "\n" + ThemeSource.iconTheme + "\n" + ThemeSource.languageText + "\n" + ThemeSource.themeName
  }

  // Color calls these: begin() once the theme first loads, settle() after each reload settles.
  function begin() {
    var t = canonical()
    lastKey = keyOf(t)
    current = t
    ThemeSource.publishTokens(t, 0, false)
  }

  function settle() {
    var t = canonical()
    var k = keyOf(t)
    if (k === lastKey) return
    lastKey = k
    current = t
    revision = revision + 1
    ThemeSource.publishTokens(t, revision, true)
    changed(t)
  }

  function hex(c) {
    var q = typeof c === "string" ? Qt.color(c) : c
    function h(v) {
      var n = Math.max(0, Math.min(255, Math.round(v * 255)))
      return (n < 16 ? "0" : "") + n.toString(16)
    }
    return "#" + h(q.r) + h(q.g) + h(q.b) + h(q.a)
  }

  function border(spec) {
    var g = spec.gradient && spec.gradient.enabled ? spec.gradient : null
    return {
      color: hex(spec.color),
      widths: [spec.widths.top, spec.widths.right, spec.widths.bottom, spec.widths.left],
      gradient: g ? { colors: g.colors.map(hex), angle: g.angle } : null,
    }
  }

  function canonical() {
    var C = Commons.Color, S = Commons.Style, B = Commons.Border
    var fg = C.foreground, ac = C.accent
    var card = Math.max(1, S.space(2))
    var sp = S.spacing, f = S.font
    function state(name, fill, text) {
      return { border: border(B.controlSpec(name, fg, ac)), fill: hex(fill), text: hex(text) }
    }
    function surface(s, name, width) {
      return { background: hex(s.background), text: hex(s.text), border: border(B.surfaceSpec(name, "border", s.border, width)) }
    }
    var menu = surface(C.menu, "menu", card)
    menu.scrim = hex(C.menu.scrim)
    menu.selectedBackground = hex(C.menu.selectedBackground)
    menu.selectedText = hex(C.menu.selectedText)
    menu.selectedBorder = border(B.surfaceSpec("menu", "selected-border", C.menu.selectedBorder, 0))
    var notifications = surface(C.notifications, "notifications", card)
    notifications.countdown = hex(C.notifications.countdown)
    var polkit = {
      background: hex(C.polkit.background),
      text: hex(C.polkit.text),
      border: border(B.surfaceSpec("polkit", "border", C.polkit.border, card, "border-alpha")),
      textError: hex(C.polkit.textError),
      borderError: border(B.surfaceSpec("polkit", "border-error", C.polkit.borderError, card, "border-alpha")),
      accent: hex(C.polkit.accent),
      scrim: hex(C.polkit.scrim),
    }
    return {
      schema: 1,
      mode: C.dark ? "dark" : "light",
      palette: {
        foreground: hex(fg), background: hex(C.background), accent: hex(ac), urgent: hex(C.urgent), muted: hex(C.muted),
        success: hex(C.success), warning: hex(C.warning),
      },
      roles: { textDim: hex(C.textDim), textFaint: hex(C.textFaint), track: hex(C.track), scrim: hex(C.scrim) },
      radius: S.cornerRadius,
      gapsOut: S.gapsOut,
      reduceMotion: S.reduceMotion,
      font: {
        family: f.family, resolvedFamily: f.resolvedFamily, baseSize: f.baseSize,
        caption: f.caption, bodySmall: f.bodySmall, body: f.body, subtitle: f.subtitle, title: f.title,
        heading: f.heading, display: f.display, displayLarge: f.displayLarge,
        iconSmall: f.iconSmall, icon: f.icon, iconLarge: f.iconLarge,
      },
      spacing: {
        scale: Math.round(sp.scale * 10000) / 10000, hairline: sp.hairline, xxs: sp.xxs, xs: sp.xs, sm: sp.sm, md: sp.md,
        lg: sp.lg, xl: sp.xl, xxl: sp.xxl, xxxl: sp.xxxl, huge: sp.huge,
        controlGap: sp.controlGap, controlPaddingX: sp.controlPaddingX, controlPaddingY: sp.controlPaddingY,
        inputPaddingY: sp.inputPaddingY, controlHeight: sp.controlHeight, popupRowHeight: sp.popupRowHeight,
        rowGap: sp.rowGap, rowPaddingX: sp.rowPaddingX, labelGap: sp.labelGap, panelGap: sp.panelGap,
        panelPadding: sp.panelPadding, popupPadding: sp.popupPadding,
        dropdownWidth: sp.dropdownWidth, searchableDropdownWidth: sp.searchableDropdownWidth,
        numberFieldWidth: sp.numberFieldWidth, searchablePopupMinHeight: sp.searchablePopupMinHeight,
        meterThickness: sp.meterThickness, scrollbarThickness: sp.scrollbarThickness,
      },
      controls: {
        normal: state("normal", S.normalFillFor(fg, ac), fg),
        hover: state("hover-cursor", S.hoverFillFor(fg, ac), fg),
        focus: state("focus", S.focusFillFor(fg, ac), fg),
        selected: state("selected", S.selectedFillFor(fg, ac), S.selectedStateColor(fg, ac)),
        pressed: { fill: hex(S.pressedFillFor(fg, ac)) },
        selection: { fill: hex(S.selectionFillFor(fg, ac)) },
      },
      surfaces: {
        popups: surface(C.popups, "popups", card),
        tooltip: surface(C.tooltip, "tooltip", Math.max(1, S.normalBorderWidth)),
        menu: menu,
        notifications: notifications,
        polkit: polkit,
      },
      motion: {
        fast: 120, press: 160, theme: S.themeFade,
        easeOut: [S.easeOut[0], S.easeOut[1], S.easeOut[2], S.easeOut[3]],
        ease: [S.ease[0], S.ease[1], S.ease[2], S.ease[3]],
      },
    }
  }
}
