import QtQuick
import "../Theme"
import "../Theme" as Commons

// One key, drawn as a small cap: normal control glass (fill and border), the caption size, the
// label centered by its ink so arrows and ⇧ sit in the middle like letters do.
//
//   Keycap { key: "ctrl" }      // "Ctrl"
//   Keycap { key: "shift" }     // "⇧"
//
// Key names are normalized the same way in every binding (see `label()`): modifiers read
// "Super", "Ctrl", "Alt", "⇧"; Enter, Backspace and the arrows are glyphs; single letters are
// upper case; anything else is shown as given.
BorderSurface {
  id: root

  property string key: ""
  readonly property string label: root.normalize(key)
  property color foreground: Commons.Color.foreground

  function normalize(k) {
    var s = String(k).trim()
    var names = {
      "super": "Super", "meta": "Super", "win": "Super", "cmd": "Super", "logo": "Super",
      "ctrl": "Ctrl", "control": "Ctrl",
      "alt": "Alt", "option": "Alt",
      "shift": "⇧",
      "enter": "⏎", "return": "⏎",
      "backspace": "⌫",
      "esc": "Esc", "escape": "Esc",
      "tab": "Tab", "space": "Space",
      "up": "↑", "down": "↓", "left": "←", "right": "→",
      "pageup": "PgUp", "pagedown": "PgDn",
      "delete": "Del", "del": "Del",
      "home": "Home", "end": "End"
    }
    var n = names[s.toLowerCase()]
    if (n !== undefined) return n
    return s.length === 1 ? s.toUpperCase() : s
  }

  readonly property real _advance: Math.ceil(metrics.advanceWidth)
  implicitHeight: Style.space(18)
  implicitWidth: Math.max(implicitHeight, _advance + Style.spacing.sm * 2 + borderLeft + borderRight)
  radius: Math.min(4, Style.cornerRadius)
  color: Style.normalFill
  borderSpec: Border.controlSpec("normal", root.foreground, Commons.Color.accent)

  TextMetrics { id: metrics; font.family: Style.font.family; font.pixelSize: Style.font.caption; text: root.label }

  OpticalGlyph {
    anchors.fill: parent
    text: root.label
    fontSize: Style.font.caption
    color: root.foreground
  }
}
