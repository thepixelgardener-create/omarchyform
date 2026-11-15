import QtQuick
import QtTest
import "../.."
import "../../BoardStore.js" as Store

// Gluing, ungluing and lining up, done the way a person does them: with the
// pointer, on the real Board, at the zooms a board is used at. The question
// each answers is whether it is easy: how near a drop has to be to hold, in
// screen pixels, whatever the zoom; that what was glued comes away when it
// should and only then; and that a drag lines up and lets go again.
//
// The stand-in moves items the way BoardPane.moveTargets does, from the same
// store functions: magnetic unless shift is held, a line moved on its own
// comes away from what it is glued to, and a glued line follows its item.
TestCase {
  id: test
  name: "EaseOfGlueAndAlignment"
  when: windowShown
  visible: true
  width: 1400
  height: 1200

  PaneStub {
    id: ctl
    viewW: test.width
    viewH: test.height
    function moveTargets(dx, dy, magnetic) {
      var t = ctl.targets()
      var model = ctl.items
      if (magnetic && ctl.pointerEdit && t.length > 0) {
        var edit = ctl.pointerEdit
        if (!edit.drag) edit.drag = { x0: model.get(t[0]).ix, y0: model.get(t[0]).iy, box: Store.groupAlignBox(model, t) }
        var curX = model.get(t[0]).ix - edit.drag.x0, curY = model.get(t[0]).iy - edit.drag.y0
        var want = Store.magneticMove(model, t, edit.drag.box, curX + dx, curY + dy, 8 / ctl.zoom)
        dx = want.dx - curX
        dy = want.dy - curY
        ctl.guides = want.guides
      } else if (ctl.guides.length > 0) ctl.guides = []
      var move = Store.boundedMove(model, t, dx, dy)
      for (var i = 0; i < t.length; i++) {
        var n = model.get(t[i])
        model.setProperty(t[i], "ix", n.ix + move.dx)
        model.setProperty(t[i], "iy", n.iy + move.dy)
      }
      if (move.dx !== 0 || move.dy !== 0) {
        Store.unglueMoved(model, t)
        Store.followGlue(model)
      }
    }
  }
  Board { id: surface; ctl: ctl; width: test.width; height: test.height }

  // Note 1 at (100, 200), 200 by 150: its right side is at x 300. Note 2 to
  // the right and lower. The arrow, item 3, lies level to the right of note 1.
  function lay(zoom) {
    ctl.items.clear()
    Store.fillItems(ctl.items, [
      { id: 1, kind: "note", x: 100, y: 200, w: 200, h: 150, tint: "foreground", text: "one" },
      { id: 2, kind: "note", x: 520, y: 420, w: 180, h: 100, tint: "foreground", text: "two" },
      { id: 3, kind: "arrow", x: 330, y: 255, w: 100, h: 40, ax: 0, ay: 0.5, bx: 1, by: 0.5, tint: "foreground", text: "" }])
    ctl.zoom = zoom
    ctl.camX = 20; ctl.camY = 0
    ctl.guides = []
    wait(30)
  }
  function sx(wx) { return wx * ctl.zoom + ctl.camX }
  function sy(wy) { return wy * ctl.zoom + ctl.camY }

  // The handle for one end of the arrow, selected first.
  function handle(end) {
    ctl.selectedIndex = 2
    wait(20)
    var h = findChild(findChild(surface, "board-item-3"), "line-end-" + end)
    verify(h, "the arrow's end " + end + " has a handle")
    return h
  }

  // Drags the arrow's end so the end itself lands at screen (tx, ty), in a
  // few steps as a hand would. `during` is called before the drop.
  function dragEnd(end, tx, ty, modifiers, during) {
    var h = handle(end)
    var at = h.mapToItem(test, h.width / 2, h.height / 2)
    var p = Store.lineEndPoint(ctl.items.get(2), end)
    var ox = tx - sx(p.x), oy = ty - sy(p.y)
    mousePress(test, at.x, at.y, Qt.LeftButton, modifiers)
    for (var i = 1; i <= 8; i++) {
      var x = at.x + ox * i / 8, y = at.y + oy * i / 8
      if (modifiers & Qt.ShiftModifier) {
        // Qt's test events cannot hold shift through a move; the handle
        // takes it in as its own drag would.
        mouseMove(test, x, y, 5, Qt.LeftButton)
        var local = h.mapFromItem(test, x, y)
        h.aim(local.x, local.y, true)
      } else mouseMove(test, x, y, 5, Qt.LeftButton)
    }
    if (during) during()
    mouseRelease(test, at.x + ox, at.y + oy, Qt.LeftButton, modifiers)
    wait(20)
  }

  // Drags an item by its body by (dx, dy) screen pixels.
  function dragItem(index, dx, dy, modifiers, during) {
    ctl.selectedIndex = index
    var node = findChild(surface, "board-item-" + ctl.items.get(index).iid)
    var at = node.mapToItem(test, node.width / 2, node.height / 2)
    mousePress(test, at.x, at.y, Qt.LeftButton, modifiers)
    for (var i = 1; i <= 8; i++) mouseMove(test, at.x + dx * i / 8, at.y + dy * i / 8, 5, Qt.LeftButton, modifiers)
    if (during) during()
    mouseRelease(test, at.x + dx, at.y + dy, Qt.LeftButton, modifiers)
    wait(20)
  }

  function tail() { return ctl.items.get(2) }

  // How far outside a note's side a drop still holds, in screen pixels, is
  // the same at every zoom: about ten, and no more than that.
  function test_aDropHoldsWithinTenPixelsOfASideAtAnyZoom() {
    var reach = []
    var zooms = [0.5, 1, 2]
    for (var z = 0; z < zooms.length; z++) {
      var furthest = -1
      for (var d = 0; d <= 16; d += 2) {
        test.lay(zooms[z])
        test.dragEnd(0, test.sx(300) + d, test.sy(275), Qt.NoModifier)
        if (test.tail().aon === 1) furthest = d
      }
      reach.push(zooms[z] + "x: " + furthest + " px")
      verify(furthest >= 8 && furthest <= 10, "at " + zooms[z] + "x a drop holds up to ten pixels out, not " + furthest)
    }
    console.log("glue reach outside a side — " + reach.join(", "))
  }

  // Anywhere inside holds, at every zoom, even right by the middle.
  function test_aDropAnywhereInsideHolds() {
    var zooms = [0.5, 1, 2]
    var spots = [[110, 210], [200, 275], [290, 340], [150, 340], [295, 205]]
    for (var z = 0; z < zooms.length; z++)
      for (var s = 0; s < spots.length; s++) {
        test.lay(zooms[z])
        test.dragEnd(0, test.sx(spots[s][0]), test.sy(spots[s][1]), Qt.NoModifier)
        compare(test.tail().aon, 1, "dropped at " + spots[s] + " at " + zooms[z] + "x")
        var p = Store.lineEndPoint(test.tail(), 0)
        var onSide = Math.abs(p.x - 100) < 0.5 || Math.abs(p.x - 300) < 0.5 || Math.abs(p.y - 200) < 0.5 || Math.abs(p.y - 350) < 0.5
        verify(onSide, "and the end sits on the outline, not inside: " + JSON.stringify(p))
      }
  }

  // The ring shows while the end is over the note and only then.
  function test_theRingShowsOnlyWhileTheDropWouldHold() {
    test.lay(1)
    var rings = function () { return ctl.guides.filter(function (g) { return g.glue === true }).length }
    test.dragEnd(0, test.sx(250), test.sy(275), Qt.NoModifier, function () {
      compare(rings(), 1, "over the note: ringed")
    })
    compare(rings(), 0, "gone once it is dropped")
    test.lay(1)
    test.dragEnd(0, test.sx(330), test.sy(120), Qt.NoModifier, function () {
      compare(rings(), 0, "over nothing: no ring")
    })
  }

  // Glued, the arrow goes where the note goes; dragged off, it lets go; shift
  // puts it down on the note unglued; the arrow moved on its own lets go too.
  function test_gluedFollowsAndLetsGoWhenItShould() {
    test.lay(1)
    test.dragEnd(0, test.sx(250), test.sy(275), Qt.NoModifier)
    compare(test.tail().aon, 1, "glued")
    test.dragItem(0, -60, 40, Qt.NoModifier)
    var p = Store.lineEndPoint(test.tail(), 0)
    var n = ctl.items.get(0)
    verify(Math.abs(p.x - (n.ix + n.iw)) < 0.5, "the tail moved with the note to its side: " + p.x + " vs " + (n.ix + n.iw))
    compare(test.tail().aon, 1, "and is still glued")

    test.dragEnd(0, test.sx(n.ix + n.iw + 120), test.sy(150), Qt.NoModifier)
    compare(test.tail().aon, 0, "dragged off into the open: let go")

    test.lay(1)
    test.dragEnd(0, test.sx(250), test.sy(275), Qt.ShiftModifier)
    compare(test.tail().aon, 0, "shift: on the note, not glued")

    test.lay(1)
    test.dragEnd(0, test.sx(250), test.sy(275), Qt.NoModifier)
    compare(test.tail().aon, 1)
    test.dragItem(2, 0, 120, Qt.NoModifier)
    compare(test.tail().aon, 0, "the arrow moved on its own comes away")
  }

  // Both ends, one note each: the arrow joins them and follows either.
  function test_anArrowJoinsTwoNotes() {
    test.lay(1)
    test.dragEnd(0, test.sx(250), test.sy(275), Qt.NoModifier)
    test.dragEnd(1, test.sx(600), test.sy(480), Qt.NoModifier)
    compare([test.tail().aon, test.tail().bon], [1, 2], "tail on one, head on two")
    var at = Store.lineEndPoint(test.tail(), 1)
    verify(Math.abs(at.x - 520) < 0.5 || Math.abs(at.y - 420) < 0.5,
           "the head stops at the side of note two it arrives at, not across it: " + JSON.stringify(at))
    test.dragItem(1, 100, -80, Qt.NoModifier)
    var head = Store.lineEndPoint(test.tail(), 1), two = ctl.items.get(1)
    verify(head.x >= two.ix - 0.5 && head.x <= two.ix + two.iw + 0.5 && head.y >= two.iy - 0.5 && head.y <= two.iy + two.ih + 0.5,
           "the head stayed on note two as it moved")
    compare([test.tail().aon, test.tail().bon], [1, 2], "both still glued")
  }

  // A slanting arrow's box covers the notes it joins. A press on the arrow
  // takes the arrow; a press anywhere else in its box takes what is under it.
  function test_aSlantingArrowTakesOnlyPressesOnIt() {
    // Note three lies under the slanting arrow's box, off its stroke: the
    // arrow joins note one's right side to note two's left.
    ctl.items.clear()
    Store.fillItems(ctl.items, [
      { id: 1, kind: "note", x: 100, y: 200, w: 200, h: 150, tint: "foreground", text: "one" },
      { id: 2, kind: "note", x: 520, y: 420, w: 180, h: 100, tint: "foreground", text: "two" },
      { id: 4, kind: "note", x: 320, y: 380, w: 80, h: 50, tint: "foreground", text: "under" },
      { id: 3, kind: "arrow", x: 0, y: 0, w: 100, h: 40, tint: "foreground", text: "",
        from: { id: 1, x: 1, y: 0.5 }, to: { id: 2, x: 0, y: 0.5 } }])
    Store.followGlue(ctl.items)
    ctl.zoom = 1; ctl.camX = 20; ctl.camY = 0
    ctl.selectedIndex = -1
    wait(30)
    var arrow = findChild(surface, "board-item-3")
    var e = Store.lineEnds(ctl.items.get(3))
    var off = { x: test.sx(340), y: test.sy(405) }
    var box = arrow.mapToItem(test, 0, 0)
    verify(off.x > box.x && off.y > box.y && off.x < box.x + arrow.width && off.y < box.y + arrow.height, "inside the arrow's box")
    mousePress(test, off.x, off.y, Qt.LeftButton)
    mouseRelease(test, off.x, off.y, Qt.LeftButton)
    wait(20)
    compare(ctl.selectedIndex, 2, "a press off the stroke takes the note under it")
    // Dragging that note leaves the arrow where it is, glued.
    test.dragItem(2, 0, 30, Qt.NoModifier)
    compare([ctl.items.get(3).aon, ctl.items.get(3).bon], [1, 2], "and dragging it lets go of nothing")
    // On the stroke, half way along.
    var on = arrow.mapToItem(test, (e.ax + e.bx) / 2 * arrow.width, (e.ay + e.by) / 2 * arrow.height)
    mousePress(test, on.x, on.y, Qt.LeftButton)
    mouseRelease(test, on.x, on.y, Qt.LeftButton)
    wait(20)
    compare(ctl.selectedIndex, 3, "a press on the stroke takes the arrow")
  }

  // A note dragged near another's side lines up with it exactly and shows a
  // guide, at every zoom, within eight screen pixels; further, or with
  // shift, it goes where it is put.
  function test_aDraggedNoteLinesUpAndLetsGo() {
    var zooms = [0.5, 1, 2]
    for (var z = 0; z < zooms.length; z++) {
      var zoom = zooms[z]
      // Note two's left side 6 screen pixels right of note one's right side,
      // and its top 5 screen pixels below note one's top.
      var dx = (300 - 520) * zoom + 6, dy = (200 - 420) * zoom + 5
      test.lay(zoom)
      var shown = 0
      test.dragItem(1, dx, dy, Qt.NoModifier, function () { shown = ctl.guides.length })
      var two = ctl.items.get(1)
      compare([two.ix, two.iy], [300, 200], zoom + "x: side to side and tops level")
      compare(shown, 2, zoom + "x: a guide for each")
      compare(ctl.guides.length, 0, zoom + "x: and the guides go with the drag")

      test.lay(zoom)
      test.dragItem(1, dx + 10, dy + 10, Qt.NoModifier)
      two = ctl.items.get(1)
      verify(Math.abs(two.ix - 300) > 1 && Math.abs(two.iy - 200) > 1, zoom + "x: sixteen pixels off, it stays where it was put")

      test.lay(zoom)
      test.dragItem(1, dx, dy, Qt.ShiftModifier)
      two = ctl.items.get(1)
      verify(Math.abs(two.ix - 300) > 1, zoom + "x: shift: no pull")
    }
  }
}
