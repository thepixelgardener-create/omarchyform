import QtQuick
import QtTest
import "../.."
import "../../BoardStore.js" as Store

// An arrow's end dragged onto a note with the pointer, on the real Board,
// with the board filled the way a board file fills it.
TestCase {
  id: test
  name: "GlueByPointer"
  when: windowShown
  visible: true
  width: 800
  height: 600

  PaneStub { id: ctl; viewW: test.width; viewH: test.height }
  Board { id: surface; ctl: ctl; width: test.width; height: test.height }

  function test_endDroppedOnANoteGlues() {
    ctl.items.clear()
    Store.fillItems(ctl.items, [
      { id: 1, kind: "note", x: 100, y: 200, w: 200, h: 150, tint: "foreground", text: "hello" },
      { id: 2, kind: "arrow", x: 400, y: 250, w: 200, h: 60, ax: 0, ay: 0.5, bx: 1, by: 0.5, tint: "foreground", text: "" }])
    ctl.camX = 0; ctl.camY = 0; ctl.zoom = 1
    ctl.selectedIndex = 1
    wait(50)
    var node = findChild(surface, "board-item-2")
    verify(node, "the arrow is drawn")
    var end = findChild(node, "line-end-0")
    verify(end, "its tail has a handle")
    var from = end.mapToItem(test, end.width / 2, end.height / 2)
    mousePress(test, from.x, from.y, Qt.LeftButton)
    for (var i = 1; i <= 10; i++) mouseMove(test, from.x - i * 18, from.y, 10, Qt.LeftButton)
    // Over the note, before the drop, the note is ringed: the one guide is it.
    compare(ctl.guides.length, 1, "one guide while the end is over the note")
    compare(ctl.guides[0].glue, true, "and it is the note's ring")
    var rings = findChild(surface, "align-guides")
    verify(rings && rings.count === 1, "drawn on the board")
    mouseRelease(test, from.x - 180, from.y, Qt.LeftButton)
    wait(20)
    var n = ctl.items.get(1)
    compare(n.aon, 1, "the tail is glued to the note")
    compare(ctl.guides.length, 0, "and the ring goes with the drag")
  }
}
