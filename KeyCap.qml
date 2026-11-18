import QtQuick
import "kit/Ui" as O

// The kit's key cap, keeping a letter's case. The kit draws keys as they are
// printed on a keyboard, so h shows as H and shift+h as ⇧H; here h and H are
// different commands (move and push), and the list reads the way they are
// typed. Every other name is the kit's: ctrl is Ctrl, enter is ⏎.
O.Keycap {
  function normalize(k) {
    var s = String(k).trim()
    if (s.length === 1) return s
    var names = {
      "super": "Super", "ctrl": "Ctrl", "strg": "Strg", "alt": "Alt", "shift": "⇧", "umschalt": "⇧",
      "enter": "⏎", "eingabe": "⏎", "backspace": "⌫", "rücktaste": "⌫", "esc": "Esc",
      "tab": "Tab", "space": "Space", "leertaste": "Leertaste", "del": "Del", "entf": "Entf"
    }
    var n = names[s.toLowerCase()]
    return n !== undefined ? n : s
  }
}
