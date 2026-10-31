import QtQuick
import QtTest
import "../.."
import "../../BoardStore.js" as Store

// What the board's connector canvas draws, and what drawing it costs.
//
// Mounted on the real Board against the stand-in controller, as tst_pan is,
// with the pattern off so nothing but the connector is on the canvas.
TestCase {
  id: test
  name: "Connectors"
  when: windowShown
  visible: true
  width: 800
  height: 600

  PaneStub {
    id: ctl
    viewW: test.width
    viewH: test.height
  }

  Board {
    id: surface
    ctl: ctl
    width: test.width
    height: test.height
  }

  // A second board on the same items, as a split shows one document twice.
  Board {
    id: twin
    ctl: ctl
    width: test.width
    height: test.height
    visible: false
  }

  // Where paths are built to be timed, and never shown.
  Canvas { id: scratch; width: test.width; height: test.height; visible: false }

  function note(id, x, y) {
    return { iid: id, kind: "note", ix: x, iy: y, iw: 120, ih: 80, itint: "foreground",
             itexture: "plain", itext: "", ipinned: false, isrc: "" }
  }

  function init() {
    surface.width = test.width
    ctl.items.clear()
    ctl.links.clear()
    ctl.camX = 0
    ctl.camY = 0
    ctl.zoom = 1
    ctl.showGrid = false
    ctl.selectedIndex = -1
    ctl.linkingFrom = -1
  }

  // The canvas once it has drawn what it was last asked to.
  function drawn() {
    var canvas = findChild(surface, "connectors")
    var painted = signalSpy.createObject(test, { target: canvas, signalName: "painted" })
    surface.repaintLinks()
    painted.wait(5000)
    painted.destroy()
    return grabImage(surface)
  }
  property Component signalSpy: SignalSpy {}

  // A screen reader on the canvas hears the board and the item the keyboard
  // is on, from the one item holding focus; the delegates carry nothing, and
  // every grabImage in this file still produces a picture.
  function test_theCanvasSaysWhatIsSelected() {
    var keys = findChild(surface, "board-keys")
    verify(keys)
    compare(keys.Accessible.name, "Board notes")
    compare(keys.Accessible.description, "Empty")
    ctl.items.append(note(1, 0, 0))
    ctl.items.append(note(2, 200, 0))
    ctl.items.setProperty(1, "itext", "Second thought")
    compare(keys.Accessible.description, "2 items, none selected")
    ctl.selectedIndex = 1
    compare(keys.Accessible.description, "Note 2 of 2: Second thought")
    ctl.items.setProperty(1, "itext", "x".repeat(300))
    compare(keys.Accessible.description, "Note 2 of 2: " + "x".repeat(200) + "…", "a long note is cut short")
    ctl.linkingFrom = 1
    ctl.items.setProperty(1, "kind", "diamond")
    compare(keys.Accessible.description, "Diamond 2 of 2, connecting: " + "x".repeat(200) + "…")
  }

  // A head is a filled triangle at the far end, and the line stops at its base.
  function test_aConnectorEndsInAFilledHead() {
    ctl.items.append(note(1, 100, 250))
    ctl.items.append(note(2, 500, 250))
    ctl.links.append({ lfrom: 1, lto: 2 })
    var shot = drawn()
    var g = Store.connectorGeometry(ctl.items.get(0), ctl.items.get(1), 9, 2)
    var background = shot.pixel(400, 100)
    var inside = shot.pixel(Math.round((g.toX + g.leftX + g.rightX) / 3), Math.round((g.toY + g.leftY + g.rightY) / 3))
    verify(inside !== background, "the middle of the head is filled")
    verify(shot.pixel(300, 289) !== background || shot.pixel(300, 290) !== background, "the line is drawn")
    compare(shot.pixel(Math.round(g.toX) - 4, Math.round(g.toY) + 12), background, "nothing beside the head")
  }

  // What a board would draw at 100%, the whole window in view, against what
  // the models hold now.
  function shown(board) {
    board.indexConnectors()
    return board.connectorsInView(0, 0, test.width, test.height, 9, 1, -1).normal
  }
  function expected() {
    var byId = Store.idIndex(ctl.items), all = []
    for (var i = 0; i < ctl.links.count; i++) {
      var l = ctl.links.get(i)
      if (byId[l.lfrom] === undefined || byId[l.lto] === undefined) continue
      var g = Store.connectorGeometry(ctl.items.get(byId[l.lfrom]), ctl.items.get(byId[l.lto]), 9, 2)
      if (g.visible) all.push(g)
    }
    return all
  }
  function headMiddle(shot, g) {
    return shot.pixel(Math.round((g.toX + g.leftX + g.rightX) / 3), Math.round((g.toY + g.leftY + g.rightY) / 3))
  }

  // The board keeps a copy of where items are; a move, a resize and a new
  // shape each reach it, and the head is drawn where the item now is.
  function test_aConnectorFollowsItsItems() {
    ctl.items.append(note(1, 100, 250))
    ctl.items.append(note(2, 500, 250))
    ctl.links.append({ lfrom: 1, lto: 2 })
    var before = drawn()
    var background = before.pixel(400, 100)
    var was = expected()[0]
    ctl.items.setProperty(1, "iy", 420)
    var after = drawn()
    compare(shown(surface), expected(), "moved")
    var now = expected()[0]
    verify(headMiddle(after, now) !== background, "the head is drawn where the item went")
    compare(headMiddle(after, was), background, "and not where it was")
    ctl.items.setProperty(1, "iw", 260)
    ctl.items.setProperty(1, "ih", 40)
    drawn()
    compare(shown(surface), expected(), "resized")
    ctl.items.setProperty(1, "kind", "ellipse")
    drawn()
    compare(shown(surface), expected(), "an ellipse, met at its outline")
    compare(shown(twin), expected(), "a second board on the same items follows them too")
  }

  function test_aConnectorComesAndGoesWithItsItems() {
    ctl.items.append(note(1, 100, 250))
    ctl.items.append(note(2, 500, 250))
    ctl.items.append(note(3, 300, 450))
    ctl.links.append({ lfrom: 1, lto: 2 })
    ctl.links.append({ lfrom: 2, lto: 3 })
    drawn()
    compare(shown(surface).length, 2)
    ctl.items.move(0, 2, 1)
    ctl.items.setProperty(0, "ix", 40)
    drawn()
    compare(shown(surface), expected(), "rows moved, then one of them moved on the board")
    ctl.items.remove(2)
    drawn()
    compare(shown(surface), expected(), "an end removed")
    compare(shown(surface).length, 1)
    ctl.items.append(note(1, 100, 100))
    drawn()
    compare(shown(surface), expected(), "and put back")
    ctl.items.clear()
    ctl.items.append(note(1, 600, 100))
    ctl.items.append(note(2, 100, 500))
    ctl.items.append(note(3, 600, 500))
    drawn()
    compare(shown(surface), expected(), "a board of the same ids, somewhere else")
  }

  // A board opens its items before its connectors, and keeps only the index
  // until there is a connector to draw: what moved meanwhile is where the
  // connector then starts, and so is what moves once the last one has gone.
  function test_connectorsArriveAfterTheirItems() {
    ctl.items.append(note(1, 100, 250))
    ctl.items.append(note(2, 500, 250))
    drawn()
    compare(surface.itemRows, null, "no copy of the items while there is nothing to walk")
    compare(surface.linkIndex[2], 1, "but the index is kept")
    ctl.items.setProperty(1, "iy", 420)
    drawn()
    ctl.links.append({ lfrom: 1, lto: 2 })
    drawn()
    compare(shown(surface), expected(), "drawn to where the item had moved")
    ctl.links.clear()
    drawn()
    compare(surface.itemRows, null)
    ctl.items.setProperty(0, "ix", 20)
    ctl.links.append({ lfrom: 2, lto: 1 })
    drawn()
    compare(shown(surface), expected(), "and again once the last connector had gone")
  }

  function paintsDuring(step) {
    var canvas = findChild(surface, "connectors")
    var spy = signalSpy.createObject(test, { target: canvas, signalName: "painted" })
    step()
    wait(150)
    var count = spy.count
    spy.destroy()
    return count
  }
  function moved(g, dx, dy) {
    return { toX: g.toX + dx, toY: g.toY + dy, leftX: g.leftX + dx, leftY: g.leftY + dy,
             rightX: g.rightX + dx, rightY: g.rightY + dy }
  }

  // A pan moves a drawing that holds every connector rather than drawing it
  // again, and it is where the camera put it.
  function test_aPanMovesTheConnectorsItHasDrawn() {
    ctl.items.append(note(1, 100, 250))
    ctl.items.append(note(2, 500, 250))
    ctl.links.append({ lfrom: 1, lto: 2 })
    var before = drawn()
    var background = before.pixel(400, 100)
    var g = expected()[0]
    compare(paintsDuring(function () { ctl.camX += 60; ctl.camY += 40; surface.panned() }), 0,
            "nothing drawn again")
    var after = grabImage(surface)
    verify(headMiddle(after, moved(g, 60, 40)) !== background, "the head went with the camera")
    compare(headMiddle(after, g), background, "and is not left where it was")
    ctl.zoom = 1.5
    verify(paintsDuring(function () { surface.panned() }) > 0, "a zoom draws them again")
  }

  // A drawing that left a connector out cannot be moved: what comes into view
  // is drawn.
  function test_aPanDrawsAConnectorComingIntoView() {
    ctl.items.append(note(1, 100, 250))
    ctl.items.append(note(2, 1000, 250))
    ctl.links.append({ lfrom: 1, lto: 2 })
    drawn()
    verify(paintsDuring(function () { ctl.camX -= 400; surface.panned() }) > 0, "drawn again")
    var shot = grabImage(surface)
    var g = Store.connectorGeometry(ctl.items.get(0), ctl.items.get(1), 9, 2)
    verify(headMiddle(shot, moved(g, -400, 0)) !== shot.pixel(400, 100), "the head that came into view")
  }

  // What a pan moves stays on the board: beside it is another pane in a split.
  function test_aMovedDrawingStaysOnTheBoard() {
    surface.width = 400
    ctl.items.append(note(1, 20, 250))
    ctl.items.append(note(2, 240, 250))
    ctl.links.append({ lfrom: 1, lto: 2 })
    drawn()
    var g = expected()[0]
    var past = moved(g, 200, 0)
    verify(past.toX > 410, "the head is moved past the board's edge")
    var beside = grabImage(test).pixel(Math.round((past.toX + past.leftX + past.rightX) / 3) , 100)
    compare(paintsDuring(function () { ctl.camX += 200; surface.panned() }), 0)
    var shot = grabImage(test)
    compare(shot.pixel(Math.round((past.toX + past.leftX + past.rightX) / 3), Math.round((past.toY + past.leftY + past.rightY) / 3)),
            beside, "nothing drawn past the board")
  }

  // A connector turned round, as connecting the same two the other way does.
  function test_aConnectorTurnedRound() {
    ctl.items.append(note(1, 100, 250))
    ctl.items.append(note(2, 500, 250))
    ctl.links.append({ lfrom: 1, lto: 2 })
    drawn()
    ctl.links.setProperty(0, "lfrom", 2)
    ctl.links.setProperty(0, "lto", 1)
    drawn()
    compare(shown(surface), expected(), "its head is at the other end")
    verify(shown(surface)[0].toX < 300)
    ctl.links.remove(0)
    drawn()
    compare(shown(surface).length, 0, "and gone once removed")
  }

  // Context2D's closePath measures the bounds of the whole path it is given,
  // so closing each head in the one path every head shares made the paint
  // quadratic: 16,000 heads took 1.2 seconds to hand over, against 3 ms for
  // the same heads left for fill() to close, which it does anyway.
  function test_manyHeadsAreQuickToBuild() {
    var heads = []
    for (var i = 0; i < 16000; i++) {
      var x = (i * 37) % 760 + 20, y = (i * 53) % 560 + 20
      heads.push({ visible: true, fromX: x - 60, fromY: y, toX: x, toY: y,
                   leftX: x - 9, leftY: y - 4, rightX: x - 9, rightY: y + 4 })
    }
    var ctx = scratch.getContext("2d")
    ctx.reset()
    var started = Date.now()
    surface.paintConnectors(ctx, heads, 1, 0, 0)
    var took = Date.now() - started
    ctx.reset()
    verify(took < 250, "16,000 connectors handed to the canvas in " + took + " ms")
  }
}
