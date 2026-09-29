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
  property string palette: "theme"
  property var crop: []
  readonly property var chosen: Store.exportPalette(picture.palette)
  signal finished(bool success)
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
    if (!area) { finished(false); return }
    ratio = Math.min(1, 4096 / (area.maxX-area.minX+64), 4096 / (area.maxY-area.minY+64))
    destination = path
    connectors.requestPaint()
    capture.restart()
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
    // a picture, so a tint that would be drawn strongly on screen is drawn
    // plainly here. Shaped like the real theme because a Node cannot tell the
    // difference — tests/contract.js is what holds the two shapes together.
    property QtObject theme: QtObject {
      property color foreground: picture.chosen ? picture.chosen.foreground : picture.theme.foreground
      property color accent: picture.chosen ? picture.chosen.borders.accent : picture.theme.accent
      property color muted: picture.chosen ? picture.chosen.borders.muted : picture.theme.muted
      property color canvasBackground: picture.chosen ? picture.chosen.background : picture.theme.canvasBackground
      property string fontFamily: picture.theme.fontFamily
      property int fontSubtitle: picture.theme.fontSubtitle
      property int fontBody: picture.theme.fontBody
      property int borderWidth: picture.theme.borderWidth
      property int cornerRadius: picture.theme.cornerRadius
      function sp(n) { return picture.theme.sp(n) }
      // A chosen palette names its fills and borders outright rather than
      // blending them, so nothing here has to reproduce the theme's arithmetic
      // against colours it was never chosen for. `strong` is ignored either
      // way: nothing in a picture is selected.
      function tintFill(tint, strong) {
        return picture.chosen ? Store.paletteTint(picture.chosen, "fills", tint)
                              : picture.theme.tintFill(tint, false)
      }
      function tintBorder(tint, strong) {
        return picture.chosen ? Store.paletteTint(picture.chosen, "borders", tint)
                              : picture.theme.tintBorder(tint, false)
      }
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
    function stopEditing() {}
    function newBoard() {}
    function removeItem(index) {}
    function pointerSelect(index, additive) {}
    function moveTargets(dx, dy) {}
    function resizeTargets(dx, dy) {}
  }
  Rectangle {
    anchors.fill: parent
    color: picture.chosen ? picture.chosen.background : picture.theme.canvasBackground
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
      onPaint: {
        var c = getContext("2d")
        c.reset()
        c.scale(picture.ratio, picture.ratio)
        c.translate(picture.area ? 32-picture.area.minX : 0, picture.area ? 32-picture.area.minY : 0)
        c.strokeStyle = picture.chosen ? picture.chosen.connector : picture.theme.foreground
        c.fillStyle = c.strokeStyle
        // A chosen palette's connector colour is already the weight it wants
        // against its own background; the theme's foreground is not, and is
        // held back here the way the board holds it back.
        c.globalAlpha = picture.chosen ? 1 : 0.65
        c.lineWidth = 1.5
        var byId = Store.idIndex(nodes)
        for (var i=0; i<edges.count; i++) {
          var link = edges.get(i), a=nodes.get(byId[link.lfrom]), b=nodes.get(byId[link.lto])
          var ax=a.ix+a.iw/2, ay=a.iy+a.ih/2, bx=b.ix+b.iw/2, by=b.iy+b.ih/2
          var p=Store.edgePoint(a,ax,ay,bx,by), q=Store.edgePoint(b,bx,by,ax,ay)
          c.beginPath(); c.moveTo(p.x,p.y); c.lineTo(q.x,q.y); c.stroke()
          var angle=Math.atan2(q.y-p.y,q.x-p.x)
          c.beginPath(); c.moveTo(q.x,q.y)
          c.lineTo(q.x-7*Math.cos(angle-0.42),q.y-7*Math.sin(angle-0.42))
          c.lineTo(q.x-7*Math.cos(angle+0.42),q.y-7*Math.sin(angle+0.42))
          c.closePath(); c.fill()
        }
      }
    }
    Item { id: foregrounds }
    Repeater {
      model: nodes
      delegate: Node {
        ctl: renderCtl
        parent: ipinned ? backgrounds : foregrounds
        enabled: false
      }
    }
  }
  Timer {
    id: capture
    interval: 80
    onTriggered: {
      if (!picture.grabToImage(function(result) { picture.finished(result.saveToFile(picture.destination)) })) picture.finished(false)
    }
  }
}
