import QtQuick

// The keyboard cursor every shell panel re-implements (focusSection, selectedIndex,
// cursorActive, moveCursor, ensureCursorVisible), as one non-visual object.
//
//   CursorModel {
//     id: cursor
//     sections: [{ name: "connected", count: 2 }, { name: "known", count: known.length }]
//     referenceItem: panel
//     onMoved: function(section, index, byKey) { if (byKey) scroll.ensureVisible(rowAt(section, index)) }
//     onActivated: function(section, index) { connect(section, index) }
//   }
//   PanelKeyCatcher { onMoveRequested: (dx, dy) => cursor.move(dx, dy) ... }   // or:
//   Keys.onPressed: (event) => cursor.handleKey(event)
//   ListRow { hasCursor: cursor.isAt("known", index); onPointerMoved: (m) => cursor.pointerMoved(this, m, "known", index) }
//
// - j/k and Down/Up move a row, crossing into the next or previous non-empty section at the ends;
//   h/l and Left/Right move a column when `columns > 1` (a TileGrid).
// - Page Up/Down move `pageSize` rows within the section; Home/End go to the first or last row.
// - The first key after the cursor was hidden only shows it, as the shell's panels do.
// - The pointer moves the cursor through pointerMoved(), which filters synthetic hover from rows
//   moving under a still pointer (PointerMoveGate). Set `referenceItem` to something that does
//   not scroll, like the panel.
QtObject {
  id: root

  // [{ name, count }]. Reassign the array to change counts, or call setCount().
  property var sections: [{ name: "", count: 0 }]
  property string focusSection: sections.length > 0 ? sections[0].name : ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property int columns: 1
  property int pageSize: 5
  property Item referenceItem: null

  // The cursor landed on a row; `byKey` when the keyboard moved it (reveal the row then).
  signal moved(string section, int index, bool byKey)
  signal activated(string section, int index)
  signal deleteRequested(string section, int index)
  signal closeRequested()
  // A printable key nothing else took: type-ahead filter text.
  signal textTyped(string text)

  property PointerMoveGate gate: PointerMoveGate { referenceItem: root.referenceItem }

  function sectionIndex(name) {
    for (var i = 0; i < sections.length; i++) if (sections[i].name === name) return i
    return -1
  }
  function countOf(name) {
    var i = sectionIndex(name)
    return i < 0 ? 0 : sections[i].count
  }
  function neighbour(from, dir) {
    for (var i = from + dir; i >= 0 && i < sections.length; i += dir) if (sections[i].count > 0) return i
    return -1
  }

  function isAt(section, index) {
    return cursorActive && focusSection === section && selectedIndex === index
  }

  function set(section, index) {
    if (sectionIndex(section) < 0) return
    focusSection = section
    selectedIndex = index
    cursorActive = true
    settle()
  }

  function reset() {
    cursorActive = false
    gate.reset()
  }

  function setCount(section, count) {
    var next = sections.slice()
    var i = sectionIndex(section)
    if (i < 0) return
    next[i] = { name: next[i].name, count: count }
    sections = next
    settle()
  }

  // Keep the cursor on a real row: off an empty section, within the count.
  function settle() {
    var s = sectionIndex(focusSection)
    if (s < 0 || sections[s].count === 0) {
      var n = neighbour(Math.max(0, s), 1)
      if (n < 0) n = neighbour(Math.max(0, s), -1)
      if (n < 0 && s < 0 && sections.length > 0) n = 0
      if (n >= 0) { focusSection = sections[n].name; selectedIndex = 0 }
    }
    selectedIndex = Math.max(0, Math.min(selectedIndex, countOf(focusSection) - 1))
  }

  // Show a hidden cursor; false when it was hidden (the key only woke it).
  function wake() {
    gate.reset()
    if (cursorActive) return true
    cursorActive = true
    settle()
    return false
  }

  function announce(byKey) { moved(focusSection, selectedIndex, byKey) }

  function move(dx, dy) {
    if (!wake()) { announce(true); return }
    var s = sectionIndex(focusSection)
    var count = countOf(focusSection)
    var index = selectedIndex
    if (dx !== 0 && columns > 1) {
      var col = index % columns + dx
      if (col >= 0 && col < columns && index + dx >= 0 && index + dx < count) index += dx
    }
    for (var step = 0; step < Math.abs(dy); step++) {
      var next = index + columns * (dy > 0 ? 1 : -1)
      if (next >= 0 && next < count) { index = next; continue }
      var n = neighbour(s, dy > 0 ? 1 : -1)
      if (n >= 0) {
        var c = sections[n].count
        if (dy > 0) index = Math.min(index % columns, c - 1)
        else index = Math.min(Math.floor((c - 1) / columns) * columns + index % columns, c - 1)
        s = n
        count = c
      } else if (dy > 0 && columns > 1 && Math.floor(index / columns) < Math.floor((count - 1) / columns)) {
        index = count - 1
      }
    }
    focusSection = sections[s].name
    selectedIndex = index
    announce(true)
  }

  function moveSection(delta) {
    if (!wake()) { announce(true); return }
    var n = neighbour(sectionIndex(focusSection), delta > 0 ? 1 : -1)
    if (n < 0) return
    focusSection = sections[n].name
    selectedIndex = 0
    announce(true)
  }

  function page(delta) {
    if (!wake()) { announce(true); return }
    var last = countOf(focusSection) - 1
    selectedIndex = Math.max(0, Math.min(last, selectedIndex + Math.max(1, pageSize) * columns * (delta > 0 ? 1 : -1)))
    announce(true)
  }

  function home() {
    cursorActive = true
    gate.reset()
    var n = neighbour(-1, 1)
    if (n >= 0) { focusSection = sections[n].name; selectedIndex = 0 }
    announce(true)
  }

  function end() {
    cursorActive = true
    gate.reset()
    var n = neighbour(sections.length, -1)
    if (n >= 0) { focusSection = sections[n].name; selectedIndex = sections[n].count - 1 }
    announce(true)
  }

  // The text a key types for a type-ahead filter: one printable character without Ctrl, Alt or
  // Meta, else "". Space is not filter text.
  function printable(event) {
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return ""
    var t = event.text || ""
    if (t.length < 1 || t.length > 2) return ""
    if (t.length === 2 && !(t.charCodeAt(0) >= 0xd800 && t.charCodeAt(0) < 0xdc00)) return ""
    if (/^[\s\x00-\x1f\x7f]$/.test(t)) return ""
    return t
  }

  // Handle a key the shell's way. Returns true (and accepts the event) when it was a cursor key.
  function handleKey(event) {
    var plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
    var k = event.key
    var t = plain ? event.text : ""
    var done = true
    if (k === Qt.Key_Down || t === "j") move(0, 1)
    else if (k === Qt.Key_Up || t === "k") move(0, -1)
    else if (k === Qt.Key_Right || t === "l") move(1, 0)
    else if (k === Qt.Key_Left || t === "h") move(-1, 0)
    else if (k === Qt.Key_PageDown) page(1)
    else if (k === Qt.Key_PageUp) page(-1)
    else if (k === Qt.Key_Home) home()
    else if (k === Qt.Key_End) end()
    else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) moveSection((event.modifiers & Qt.ShiftModifier) || k === Qt.Key_Backtab ? -1 : 1)
    else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) activated(focusSection, selectedIndex)
    else if (k === Qt.Key_Escape) closeRequested()
    else if (k === Qt.Key_Delete || t === "x" || t === "X") deleteRequested(focusSection, selectedIndex)
    else {
      var typed = printable(event)
      if (typed !== "") textTyped(typed)
      else done = false
    }
    if (done) event.accepted = true
    return done
  }

  // The pointer moved over row `index` of `section` (call from the row's onPositionChanged, or
  // ListRow's pointerMoved). Moves the cursor only when the pointer really moved.
  function pointerMoved(item, mouse, section, index) {
    if (!gate.moved(item, mouse)) return false
    if (isAt(section, index)) return true
    set(section, index)
    announce(false)
    return true
  }

  // A view opened by the pointer keeps the row under it.
  function allowInitialSample() { gate.allowInitialSample() }
}
