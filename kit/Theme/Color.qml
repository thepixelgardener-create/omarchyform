pragma Singleton
import QtQuick
import "BorderGeometry.js" as Geometry

// Ported from the Omarchy shell's shell/Commons/Color.qml (see qt/HARVEST.md): file loading moved
// to the C++ ThemeSource, and surface text roles resolve through flatColor so a role name such as
// `foreground` works there too. The theme-switch fade and the changed hook (spec/following.md,
// "Following" at the bottom) are the kit's own. Everything else is the shell's logic, unchanged.
//
// Color surfaces for the shell. Foundational palette (foreground, background,
// accent, urgent) comes from theme/colors.toml. Per-surface roles come from
// theme/shell.toml — generated per theme from default/themed/shell.toml.tpl,
// or shipped directly by a theme to replace the generated file. Surfaces that
// don't appear in shell.toml fall back to the foundational palette.
QtObject {
  id: root

  property color foreground: "#cacccc"
  property color background: "#101315"
  property color accent: "#cacccc"
  property color urgent: "#a55555"
  property color muted: "#707880"
  // colors.toml `mode`; light themes say "light". (Not in the shell, which has no use for it.)
  property bool dark: true

  // The kit's own additions (spec/tokens.md "Palette" and "Roles"); not in the shell.
  property color success: "#7f9f6f"
  property color warning: "#c0a060"
  // Secondary and faint text are the theme's own Base24 stops: `dark_foreground` (base04) and
  // `muted` (base03, or color8). A theme without them fades the foreground toward the
  // background: the shell's Qt.darker(foreground, 1.5 / 2.0) in a dark theme; in a light theme
  // darker would mean stronger, so a mix a third / a half of the way to the background instead.
  property string darkForeground: ""
  property bool mutedNamed: false
  readonly property color textDim: fading ? fadeAt("textDim", fadeProgress) : darkForeground !== "" ? darkForeground
    : dark ? Qt.darker(foreground, 1.5) : mixColor(foreground, background, 1 / 3)
  readonly property color textFaint: fading ? fadeAt("textFaint", fadeProgress) : mutedNamed ? muted
    : dark ? Qt.darker(foreground, 2.0) : mixColor(foreground, background, 1 / 2)
  readonly property color track: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
  readonly property color scrim: menu.scrim

  // Flat dictionary of "section.key" -> raw string from shell.toml.
  // Reassigning this whole property is what makes surface bindings below
  // re-evaluate when the theme swaps; mutating it in place would not.
  property var shellValues: ({})

  function pick(key, fallback) {
    var v = shellValues[key]
    return (typeof v === "string" && v.length > 0) ? v : fallback
  }

  function pickAlpha(key, fallback) {
    var v = shellValues[key]
    if (typeof v !== "string" || v.length === 0) return fallback
    var n = Number(v)
    if (!isFinite(n)) return fallback
    return Util.clampAlpha(n)
  }

  function firstColorToken(value) {
    var parts = String(value || "").replace(/^\s+|\s+$/g, "").split(/\s+/)
    for (var i = 0; i < parts.length; i++) {
      if (!parts[i].match(/^-?\d+(?:\.\d+)?deg$/)) return parts[i]
    }
    return value
  }

  function flatColor(value, fallback) {
    var seen = Object.create(null)
    var token = firstColorToken(value)
    var role = String(token || "").replace(/^\s+|\s+$/g, "").toLowerCase()
    while (root.shellValues[role] && root.shellValues[role] !== token) {
      if (seen[role]) return fallback
      seen[role] = true
      token = firstColorToken(root.shellValues[role])
      role = String(token || "").replace(/^\s+|\s+$/g, "").toLowerCase()
    }
    if (role === "foreground" || role === "text") return root.foreground
    if (role === "accent") return root.accent
    if (role === "urgent") return root.urgent
    if (role === "muted") return root.muted
    if (role === "background") return root.background
    if (role === "transparent") return Qt.rgba(0, 0, 0, 0)

    var color = Geometry.canonicalColor(token, 1)
    if (typeof color === "string" && color === token && token.charAt(0) !== "#") return fallback
    return tracked(color)
  }

  // Compose a color from a base-color key and its `-alpha` companion. If the
  // base token is a gradient, color-only consumers use the first stop.
  function composed(colorKey, alphaKey, colorFallback, alphaFallback) {
    return Util.alpha(flatColor(pick(colorKey, colorFallback), colorFallback), pickAlpha(alphaKey, alphaFallback))
  }

  readonly property QtObject bar: QtObject {
    property color background: root.composed("bar.background", "bar.background-alpha", root.background, 1.0)
    property color text: root.flatColor(root.pick("bar.text", ""), root.foreground)
    property color active: root.flatColor(root.pick("bar.active", ""), root.urgent)
  }
  readonly property QtObject popups: QtObject {
    property color background: root.composed("popups.background", "popups.background-alpha", root.background, 1.0)
    property color text: root.flatColor(root.pick("popups.text", ""), root.foreground)
    property color border: root.composed("popups.border", "popups.border-alpha", root.accent, 1.0)
  }
  readonly property QtObject tooltip: QtObject {
    property color background: root.composed("tooltip.background", "tooltip.background-alpha", root.background, 1.0)
    property color text: root.flatColor(root.pick("tooltip.text", ""), root.foreground)
    property color border: root.composed("tooltip.border", "tooltip.border-alpha", root.foreground, 1.0)
  }
  readonly property QtObject notifications: QtObject {
    property color background: root.composed("notifications.background", "notifications.background-alpha", root.background, 1.0)
    property color text: root.flatColor(root.pick("notifications.text", ""), root.foreground)
    property color border: root.composed("notifications.border", "notifications.border-alpha", root.accent, 1.0)
    property color countdown: root.flatColor(root.pick("notifications.countdown", ""), root.accent)
  }
  readonly property QtObject menu: QtObject {
    property color background: root.composed("menu.background", "menu.background-alpha", root.background, 1.0)
    property color text: root.flatColor(root.pick("menu.text", ""), root.foreground)
    property color border: root.composed("menu.border", "menu.border-alpha", root.foreground, 1.0)
    property color scrim: root.composed("menu.scrim", "menu.scrim-alpha", root.background, 0.5)
    property color selectedBackground: root.composed("menu.selected-background", "menu.selected-background-alpha", root.foreground, 0.08)
    property color selectedText: root.flatColor(root.pick("menu.selected-text", ""), root.accent)
    property color selectedBorder: root.composed("menu.selected-border", "menu.selected-border-alpha", root.foreground, 0.0)
  }
  // polkit + lock share a single border-alpha across border / border-active /
  // border-error: the three states are mutually exclusive in time, so one
  // companion is enough.
  readonly property QtObject polkit: QtObject {
    property color background: root.composed("polkit.background", "polkit.background-alpha", root.background, 1.0)
    property color text: root.flatColor(root.pick("polkit.text", ""), root.foreground)
    property color textError: root.flatColor(root.pick("polkit.text-error", ""), root.urgent)
    property color border: root.composed("polkit.border", "polkit.border-alpha", root.accent, 1.0)
    property color borderError: root.composed("polkit.border-error", "polkit.border-alpha", root.urgent, 1.0)
    property color accent: root.flatColor(root.pick("polkit.accent", ""), root.accent)
    property color scrim: root.composed("polkit.scrim", "polkit.scrim-alpha", root.background, 0.5)
  }
  readonly property QtObject lock: QtObject {
    property color background: root.composed("lock.background", "lock.background-alpha", root.background, 0.8)
    property color text: root.flatColor(root.pick("lock.text", ""), root.foreground)
    property color placeholder: root.shellValues["lock.placeholder"] ? root.flatColor(root.shellValues["lock.placeholder"], Util.alpha(root.foreground, 0.66)) : Util.alpha(root.foreground, 0.66)
    property color textError: root.flatColor(root.pick("lock.text-error", ""), root.urgent)
    property color border: root.composed("lock.border", "lock.border-alpha", root.foreground, 1.0)
    property color borderActive: root.composed("lock.border-active", "lock.border-alpha", root.accent, 1.0)
    property color borderError: root.composed("lock.border-error", "lock.border-alpha", root.urgent, 1.0)
    property color selection: root.composed("lock.selection", "lock.selection-alpha", root.accent, 0.45)
  }
  // The image picker has no card surface or backdrop; per-slice dim
  // overlays / text outlines use the foundational `background` color directly.
  readonly property QtObject imagePicker: QtObject {
    property color text: root.flatColor(root.pick("image-picker.text", ""), root.foreground)
    property color selectedBorder: root.composed("image-picker.selected-border", "image-picker.selected-border-alpha", root.accent, 1.0)
    property color unselectedBorder: root.composed("image-picker.unselected-border", "image-picker.unselected-border-alpha", root.foreground, 0.28)
  }

  // sRGB mix by `t` (0 is a, 1 is b), rounded per 8-bit channel as the Rust resolver does.
  function mixColor(a, b, t) {
    function m(x, y) { return Math.round(Math.round(x * 255) + (Math.round(y * 255) - Math.round(x * 255)) * t) / 255 }
    return Qt.rgba(m(a.r, b.r), m(a.g, b.g), m(a.b, b.b), m(a.a, b.a))
  }

  function loadColors(raw) {
    var lines = String(raw || "").split("\n")
    var foundAccent = false
    var foundMuted = false
    var loadedForeground = false
    var loadedBackground = false
    var color0Value = ""
    var color4Value = ""
    var color7Value = ""
    var color8Value = ""
    var nextDark = true
    var nextSuccess = "#7f9f6f"
    var nextWarning = "#c0a060"
    var darkFg = ""
    var darkFgLegacy = ""
    for (var i = 0; i < lines.length; i++) {
      var modeMatch = lines[i].match(/^\s*mode\s*=\s*["']?([A-Za-z]+)/)
      if (modeMatch) nextDark = modeMatch[1].toLowerCase() !== "light"
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!match) continue
      if (match[1] === "foreground") { foreground = match[2]; loadedForeground = true }
      else if (match[1] === "background") { background = match[2]; loadedBackground = true }
      // Prefer the explicit `accent` key; only fall back to color4 when the
      // theme doesn't define a separate accent. color4 appears later in the
      // file so the old single-property approach clobbered accent with it.
      else if (match[1] === "accent") { accent = match[2]; foundAccent = true }
      else if (match[1] === "muted") { muted = match[2]; foundMuted = true }
      else if (match[1] === "color0") color0Value = match[2]
      else if (match[1] === "color4") color4Value = match[2]
      else if (match[1] === "color7") color7Value = match[2]
      else if (match[1] === "color8") color8Value = match[2]
      else if (match[1] === "red" || match[1] === "color1") urgent = match[2]
      else if (match[1] === "green" || match[1] === "color2") nextSuccess = match[2]
      else if (match[1] === "yellow" || match[1] === "color3") nextWarning = match[2]
      else if (match[1] === "dark_foreground") darkFg = match[2]
      else if (match[1] === "dark_fg") darkFgLegacy = match[2]
    }
    if (!loadedBackground && color0Value.length > 0) background = color0Value
    if (!loadedForeground && color7Value.length > 0) foreground = color7Value
    if (!foundAccent && color4Value.length > 0) accent = color4Value
    if (!foundMuted) muted = color8Value.length > 0 ? color8Value : foreground
    mutedNamed = foundMuted || color8Value.length > 0
    // Canonical names win over the legacy short ones, wherever they sit in the file.
    darkForeground = darkFg !== "" ? darkFg : darkFgLegacy
    dark = nextDark
    success = nextSuccess
    warning = nextWarning
  }

  // Last theme-supplied and user-supplied shell.toml dicts, kept separate so
  // either can be reloaded without re-reading the other. `shellValues` is
  // always the merge of theme (base) and user (override) — see mergeShell.
  property var themeShellValues: ({})
  property var userShellValues: ({})

  // Single TOML walker for shell.toml. Both Color (surface roles) and Style
  // (typography, spacing, bar, control states) consume the resulting dict.
  // Accepts quoted strings, bare numeric values, bare width lists, and bare
  // role names; tolerates inline comments. Numbers are kept as strings here —
  // readers coerce when they pull a value.
  function parseShell(raw) {
    var parsed = {}
    var text = String(raw || "")
    if (text) {
      var lines = text.split("\n")
      var section = ""
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].replace(/^\s+|\s+$/g, "")
        if (!line || line.charAt(0) === "#") continue
        var sectionMatch = line.match(/^\[([A-Za-z0-9_-]+)\]\s*(#.*)?$/)
        if (sectionMatch) { section = sectionMatch[1]; continue }
        var stringKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*["']([^"']+)["']\s*(#.*)?$/)
        var numKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(-?\d+(?:\.\d+)?)\s*(#.*)?$/)
        var widthKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(-?\d+(?:\.\d+)?(?:\s+-?\d+(?:\.\d+)?){1,3})\s*(#.*)?$/)
        var bareKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*([A-Za-z][A-Za-z0-9_-]*)\s*(#.*)?$/)
        var kv = stringKv || numKv || widthKv || bareKv
        if (!kv || !section) continue
        parsed[section + "." + kv[1]] = kv[2]
      }
    }
    return parsed
  }

  // Re-derive `shellValues` from theme base + user override and push it to
  // Style. User keys win, so a machine-level `~/.config/omarchy/shell.toml`
  // survives theme switches (which replace only themeShellValues).
  function mergeShell() {
    var merged = {}
    for (var tk in themeShellValues) merged[tk] = themeShellValues[tk]
    for (var uk in userShellValues) merged[uk] = userShellValues[uk]
    shellValues = merged
    Style.applyShellValues(merged)
  }

  function loadShell(raw) {
    themeShellValues = parseShell(raw)
    mergeShell()
  }

  function loadUserShell(raw) {
    userShellValues = parseShell(raw)
    mergeShell()
  }

  // ThemeSource re-reads the files when a theme switch lands or the user's shell.toml changes.
  function reloadFromSource() {
    loadColors(ThemeSource.colorsText)
    themeShellValues = parseShell(ThemeSource.shellText)
    userShellValues = parseShell(ThemeSource.userShellText)
    mergeShell()
  }

  // ---------------------------------------------------------------- following
  //
  // The kit's own (spec/following.md); not in the shell. A theme switch re-resolves everything
  // at once, exactly, and Tokens announces the new tokens (the changed hook); only then do the
  // colors ease from the old theme to the new over Style.themeFade on Style.ease. Rounding,
  // sizes and fonts aren't touched by the fade, so they switch at once. No fade on the first
  // load or under reduced motion, so stills and token dumps are always exact.
  //
  // The fade drives one progress value. The palette properties take the mix of old and new at
  // each step, and a literal color in shell.toml that names a palette color (the generated
  // shell.toml writes `#a9b1d6`, not `foreground`) is tracked to it while fading (tracked(), used
  // by flatColor, Style.resolveStateColor and Border.cssColor), so surfaces, state fills and
  // borders fade with the palette instead of jumping. When the fade lands, the colors are
  // re-read and every binding is back on its exact path.
  readonly property var fadeKeys: ["foreground", "background", "accent", "urgent", "muted", "success", "warning"]
  property bool fading: false
  property real fadeProgress: 1
  property var fadeFrom: ({})
  property var fadeTo: ({})
  // The colors on screen before a switch, until ThemeSource.settled starts the fade from them.
  property var pendingFade: null
  property bool loaded: false

  function copyColor(c) { return Qt.rgba(c.r, c.g, c.b, c.a) }

  function fadeSnapshot() {
    var out = {}
    for (var i = 0; i < fadeKeys.length; i++) out[fadeKeys[i]] = copyColor(root[fadeKeys[i]])
    out.textDim = copyColor(textDim)
    out.textFaint = copyColor(textFaint)
    return out
  }

  function sameColor8(a, b) {
    return Math.round(a.r * 255) === Math.round(b.r * 255) && Math.round(a.g * 255) === Math.round(b.g * 255)
      && Math.round(a.b * 255) === Math.round(b.b * 255) && Math.round(a.a * 255) === Math.round(b.a * 255)
  }

  // Key `k` part way (`t`, already eased) from the old theme's color to the new one's.
  function fadeAt(k, t) {
    var a = fadeFrom[k], b = fadeTo[k]
    if (!a || !b) return b || a || "transparent"
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
  }

  // While fading, a color equal to one of the new theme's (by its RGB) follows that color's
  // fade, keeping its own alpha. Otherwise `c` itself.
  function tracked(c) {
    if (!fading) return c
    var q = typeof c === "string" ? Qt.color(c) : c
    if (!q || q.r === undefined) return c
    for (var k in fadeTo) {
      var t = fadeTo[k]
      if (Math.round(q.r * 255) === Math.round(t.r * 255) && Math.round(q.g * 255) === Math.round(t.g * 255)
          && Math.round(q.b * 255) === Math.round(t.b * 255)) {
        var live = fadeAt(k, fadeProgress)
        return Qt.rgba(live.r, live.g, live.b, q.a)
      }
    }
    return c
  }

  // The palette keys that differ between the two themes: only those move (each assignment
  // re-evaluates every binding that reads it).
  property var fadeMoving: []

  onFadeProgressChanged: {
    if (!fading) return
    for (var i = 0; i < fadeMoving.length; i++) root[fadeMoving[i]] = fadeAt(fadeMoving[i], fadeProgress)
  }

  property NumberAnimation fade: NumberAnimation {
    target: root
    property: "fadeProgress"
    from: 0
    to: 1
    duration: Style.themeFade
    easing.type: Easing.Bezier
    easing.bezierCurve: Style.ease
    onFinished: root.landFade()
  }

  function startFade(from) {
    var to = fadeSnapshot()
    var differs = false
    for (var k in to) if (!sameColor8(from[k], to[k])) differs = true
    if (!differs) return
    fadeMoving = fadeKeys.filter(function (key) { return !sameColor8(from[key], to[key]) })
    fadeFrom = from
    fadeTo = to
    fadeProgress = 0
    fading = true
    for (var i = 0; i < fadeKeys.length; i++) root[fadeKeys[i]] = from[fadeKeys[i]]
    fade.restart()
  }

  function landFade() {
    if (!fading) return
    fading = false
    fadeFrom = ({})
    fadeTo = ({})
    // Back to the exact colors, as colors.toml has them.
    loadColors(ThemeSource.colorsText)
  }

  function followSwitch() {
    // What is on screen now, mid-fade included, is where the next fade starts.
    var from = loaded ? fadeSnapshot() : null
    if (fading) {
      fade.stop()
      fading = false
    }
    reloadFromSource()
    if (from) pendingFade = from
  }

  function followSettled() {
    // Everything has re-resolved, exactly: announce it (the changed hook), then fade.
    Tokens.settle()
    var from = pendingFade
    pendingFade = null
    if (from && !Style.reduceMotion) startFade(from)
  }

  property Connections source: Connections {
    target: ThemeSource
    function onThemeChanged() { root.followSwitch() }
    function onSettled() { root.followSettled() }
  }

  Component.onCompleted: {
    reloadFromSource()
    loaded = true
    Tokens.begin()
  }
}
