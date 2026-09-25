import QtQuick
import "BoardStore.js" as Store

// A separate, read-only scene: no camera changes, grid, grips or selection.
Item {
  id: picture
  required property var ctl
  property var area: null
  property real ratio: 1
  property string destination: ""
  signal finished(bool success)
  width: area ? Math.ceil((area.maxX - area.minX + 64) * ratio) : 1
  height: area ? Math.ceil((area.maxY - area.minY + 64) * ratio) : 1
  z: -100

  function save(path) {
    Store.fillItems(nodes, Store.itemRows(picture.ctl.items))
    Store.fillLinks(edges, nodes, Store.linkRows(picture.ctl.links))
    area = Store.bounds(nodes)
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
    property color foreground: picture.ctl.foreground
    property color accent: picture.ctl.accent
    property color muted: picture.ctl.muted
    property color canvasBackground: picture.ctl.canvasBackground
    property string fontFamily: picture.ctl.fontFamily
    property int fontSubtitle: picture.ctl.fontSubtitle
    property int fontBody: picture.ctl.fontBody
    property int borderWidth: picture.ctl.borderWidth
    property int cornerRadius: picture.ctl.cornerRadius
    property int minItemSize: picture.ctl.minItemSize
    function sp(n) { return picture.ctl.sp(n) }
    function imagePath(name) { return picture.ctl.imagePath(name) }
    function tintFill(tint, strong) { return picture.ctl.tintFill(tint, false) }
    function tintBorder(tint, strong) { return picture.ctl.tintBorder(tint, false) }
    function isMarked(id) { return false }
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
  Rectangle { anchors.fill: parent; color: picture.ctl.canvasBackground }
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
        c.strokeStyle = picture.ctl.foreground
        c.fillStyle = picture.ctl.foreground
        c.globalAlpha = 0.65
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
