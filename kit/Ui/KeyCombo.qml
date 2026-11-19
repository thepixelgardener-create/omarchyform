import QtQuick
import "../Theme"

// A key combination as Keycaps, xxs apart: "Ctrl+Shift+S" draws Ctrl, ⇧, S. A lone "+" is the
// plus key ("Ctrl++").
Row {
  id: root

  property string keys: ""

  function split(combo) {
    var parts = String(combo).split("+")
    var out = []
    for (var i = 0; i < parts.length; ++i) {
      if (parts[i] !== "") out.push(parts[i].trim())
      else if (i + 1 < parts.length && parts[i + 1] === "") { out.push("+"); ++i }
    }
    return out
  }

  spacing: Style.spacing.xxs

  Repeater {
    model: root.split(root.keys)
    delegate: Keycap {
      required property string modelData
      key: modelData
    }
  }
}
