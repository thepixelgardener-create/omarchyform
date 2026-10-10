import QtQuick
import "BoardStore.js" as Store

// A separate, read-only scene: no camera changes, grid, grips or selection.
Item {
  id: picture
  required property var ctl
  readonly property var theme: picture.ctl.theme
  property var area: null
  property real ratio: 1
  property string destination: ""
  // Which colours to draw in, and which items to draw around. Both are set by
  // the board just before it asks for a picture: "theme" and an empty crop are
  // the whole board in its own colours, which is what ctrl+e has always done.
  property string exportColors: "theme"
  property var crop: []
  readonly property var chosen: Store.exportPalette(picture.exportColors)
  // `reason` is empty unless there is something more useful to say than that
  // the picture could not be made.
  signal finished(bool success, string reason)
  // Once, when the pictures are taking long enough that the board — read-only
  // until the export is done — should say why it is not answering.
  signal stillLoading()
  width: area ? Math.ceil((area.maxX - area.minX + 64) * ratio) : 1
  height: area ? Math.ceil((area.maxY - area.minY + 64) * ratio) : 1
  z: -100

  function save(path) {
    // What is drawn and what the frame is put round are two lists: a crop
    // keeps the backgrounds its items were sitting on without being framed
    // around them.
    var part = Store.cropRows(Store.itemRows(picture.ctl.items), picture.crop)
    Store.fillItems(nodes, part.draw)
    Store.fillLinks(edges, nodes, Store.linkRows(picture.ctl.links))
    area = Store.boundsOfRows(part.frame)
    if (!area) { finished(false, ""); return }
    ratio = Math.min(1, 4096 / (area.maxX-area.minX+64), 4096 / (area.maxY-area.minY+64))
    destination = path
    linksPainted = false
    toldLoading = false
    lastPending = -1
    asked = Date.now()
    progressed = asked
    connectors.requestPaint()
    capture.restart()
  }

  // Pictures are decoded on a thread of their own, one after another, so when
  // a board is ready to be photographed depends on how many it carries, how big
  // they are and the machine. A fixed 80ms stood in for that: five phone-sized
  // photos took 600ms to arrive offscreen and 2.3s on the desktop, and the
  // export saved four or five empty frames and said it had worked. This looks
  // instead, and gives up — saying so — rather than save a picture of a board
  // that is not all there.
  //
  // It gives up when nothing has arrived for a while rather than after a while
  // in all: a board of a hundred photos is slow, not stuck, and a total budget
  // big enough for it is one a single stuck picture would sit out in silence.
  property bool linksPainted: false
  property bool toldLoading: false
  property int lastPending: -1
  property real asked: 0
  property real progressed: 0
  // How long before saying it is waiting, and how long without a picture
  // arriving before giving up. Settable so a test can reach both at once.
  property int quietMs: 1000
  property int patienceMs: 15000
  function pending() {
    var count = 0
    for (var i = 0; i < drawn.count; i++) {
      var node = drawn.itemAt(i)
      if (node && node.pictureLoading) count++
    }
    return count
  }
  ListModel { id: nodes }
  ListModel { id: edges }
  Item {
    id: renderCtl
    property alias items: nodes
    property int selectedIndex: -1
    property int editIndex: -1
    property int linkingFrom: -1
    property bool canEdit: false
    property bool showPinned: false
    // The board's palette, with its emphasis taken out: nothing is selected in
    // a picture. Unless a palette was asked for, it is the board as it looks,
    // on its own canvas colour, Paper and Ink included.
    property QtObject sceneTheme: BoardPalette {
      base: picture.theme
      chosen: picture.chosen ? picture.chosen : picture.ctl.sceneTheme.chosen
      shade: picture.ctl.sceneTheme.shade
      plain: true
    }
    property int minItemSize: picture.ctl.minItemSize
    function imagePath(name) { return picture.ctl.imagePath(name) }
    function isMarked(id) { return false }
    // An export has no viewport to fall outside of, so nothing is culled and
    // the camera it would be culled against is never read.
    property bool culling: false
    property real zoom: 1
    property real camX: 0
    property real camY: 0
    property real viewW: 0
    property real viewH: 0
    // An export is not a search result: every item is drawn at full strength.
    readonly property bool findDimming: false
    function matchesFind(text) { return false }
    function repaintLinks() { connectors.requestPaint() }
    // Everything a Node can reach, present and doing nothing. The delegates
    // here are disabled so none of it is ever called, but a member missing
    // from this list is a member that breaks an exported image the first time
    // a binding does reach for it, which is why the contract check counts
    // them rather than trusting that they stay unreachable.
    function flushSave() {}
    function save() {}
    function scheduleSave() {}
    function pushUndo() {}
    property var pointerEdit: null
    function beginPointerEdit(label) {}
    function finishPointerEdit(cancel) {}
    function beginTextPalette(editor) {}
    function stopEditing() {}
    function flash(text) {}
    function newBoard() {}
    function removeItem(index) {}
    function pointerSelect(index, additive) {}
    function moveTargets(dx, dy) {}
    function resizeTargets(dx, dy) {}
  }
  Rectangle {
    anchors.fill: parent
    color: renderCtl.sceneTheme.canvasBackground
  }
  Item {
    id: world
    z: 2
    x: picture.area ? (32-picture.area.minX)*picture.ratio : 0
    y: picture.area ? (32-picture.area.minY)*picture.ratio : 0
    scale: picture.ratio
    transformOrigin: Item.TopLeft
    Item {
      id: backgrounds
      parent: picture
      x: world.x; y: world.y
      scale: picture.ratio
      transformOrigin: Item.TopLeft
    }
    Canvas {
      id: connectors
      parent: picture
      z: 1
      width: picture.width
      height: picture.height
      onPainted: picture.linksPainted = true
      onPaint: {
        var c = getContext("2d")
        c.reset()
        c.scale(picture.ratio, picture.ratio)
        c.translate(picture.area ? 32-picture.area.minX : 0, picture.area ? 32-picture.area.minY : 0)
        c.strokeStyle = renderCtl.sceneTheme.connector
        c.fillStyle = c.strokeStyle
        c.globalAlpha = renderCtl.sceneTheme.connectorAlpha
        c.lineWidth = 1.5
        c.lineCap = "round"
        c.lineJoin = "round"
        var byId = Store.idIndex(nodes)
        for (var i = 0; i < edges.count; i++) {
          var link = edges.get(i)
          var g = Store.connectorGeometry(nodes.get(byId[link.lfrom]), nodes.get(byId[link.lto]), 9, 2)
          if (!g.visible) continue
          c.beginPath(); c.moveTo(g.fromX, g.fromY); c.lineTo((g.leftX + g.rightX) / 2, (g.leftY + g.rightY) / 2); c.stroke()
          c.beginPath(); c.moveTo(g.toX, g.toY); c.lineTo(g.leftX, g.leftY); c.lineTo(g.rightX, g.rightY)
          c.closePath(); c.fill()
        }
      }
    }
    // The repeater lives in the foreground layer, as the board's does, so it
    // only fails to stand an item after the one before when one of the two is
    // a background. Beside the layer, every item it made had moved away from
    // it, and each one logged a QQuickItem::stackAfter warning: one per item
    // on the board, on every export.
    Item {
      id: foregrounds
      Repeater {
        id: drawn
        model: nodes
        delegate: Node {
          ctl: renderCtl
          parent: ipinned ? backgrounds : foregrounds
          // Stacked by place on the board, as the board stacks them.
          z: index
          enabled: false
        }
      }
    }
  }
  Timer {
    id: capture
    interval: 25
    repeat: true
    onTriggered: {
      var now = Date.now()
      var pending = picture.pending()
      if (pending !== picture.lastPending) {
        picture.lastPending = pending
        picture.progressed = now
      }
      if (pending === 0 && picture.linksPainted) {
        capture.stop()
        // Everything has arrived; the grab itself is taken on the next frame,
        // after the scene has caught up with it.
        if (!picture.grabToImage(function(result) { picture.finished(result.saveToFile(picture.destination), "") }))
          picture.finished(false, "")
        return
      }
      if (!picture.toldLoading && now - picture.asked >= picture.quietMs) {
        picture.toldLoading = true
        picture.stillLoading()
      }
      if (now - picture.progressed >= picture.patienceMs) {
        capture.stop()
        picture.finished(false, "Pictures took too long to load; PNG not saved")
      }
    }
  }
}
