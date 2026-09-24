import QtQuick
import QtTest
import "../.."

TestCase {
  id: test
  name: "NodeInteraction"
  when: windowShown
  visible: true
  width: 640
  height: 480
  Item {
    id: ctl
    property alias items: model
    property bool canEdit: true
    property int selectedIndex: -1
    property int editIndex: -1
    property int linkingFrom: -1
    property int cornerRadius: 0
    property int borderWidth: 1
    property int minItemSize: 60
    property color foreground: "white"
    property color accent: "cyan"
    property color itemFill: "#222222"
    property string fontFamily: "monospace"
    property int fontSubtitle: 13
    property int undoCount: 0
    property int saveCount: 0
    property int flushCount: 0
    function sp(n) { return n }
    function tintFill(tint, strong) { return itemFill }
    function tintBorder(tint, strong) { return "#999999" }
    function repaintLinks() {}
    function selectOnly(index) { selectedIndex = index; editIndex = -1 }
    function pushUndo() { undoCount++ }
    function save() { saveCount++ }
    function scheduleSave() { saveCount++ }
    function flushSave() { flushCount++ }
    function stopEditing() { editIndex = -1 }
    function removeItem(index) { model.remove(index) }
    ListModel {
      id: model
      ListElement { ix: 100; iy: 100; iw: 180; ih: 140; itext: "" }
    }
  }
  Node {
    id: subject
    ctl: ctl
    index: 0
    iid: 1
    kind: "note"
    ix: model.get(0).ix
    iy: model.get(0).iy
    iw: model.get(0).iw
    ih: model.get(0).ih
    itint: "foreground"
    itext: model.get(0).itext
  }
  function init() {
    subject.kind = "note"
    ctl.itemFill = "#222222"
    ctl.canEdit = true
    ctl.selectedIndex = -1
    ctl.editIndex = -1
    ctl.undoCount = 0
    ctl.saveCount = 0
    ctl.flushCount = 0
    model.set(0, {ix:100, iy:100, iw:180, ih:140, itext:""})
  }
  function test_drag() {
    mousePress(test, 140, 140, Qt.LeftButton)
    mouseMove(test, 200, 160, -1, Qt.LeftButton)
    mouseRelease(test, 200, 160, Qt.LeftButton)
    compare(model.get(0).ix, 160)
    compare(model.get(0).iy, 120)
    compare(ctl.undoCount, 1)
    compare(ctl.saveCount, 1)
  }
  function test_resize() {
    mousePress(test, 272, 232, Qt.LeftButton)
    mouseMove(test, 312, 252, -1, Qt.LeftButton)
    mouseRelease(test, 312, 252, Qt.LeftButton)
    compare(model.get(0).iw, 220)
    compare(model.get(0).ih, 160)
    compare(ctl.undoCount, 1)
    compare(ctl.saveCount, 1)
  }
  function test_readOnly() {
    ctl.canEdit = false
    mousePress(test, 140, 140, Qt.LeftButton)
    mouseMove(test, 200, 160, -1, Qt.LeftButton)
    mouseRelease(test, 200, 160, Qt.LeftButton)
    compare(model.get(0).ix, 100)
    compare(model.get(0).iy, 100)
    mouseDoubleClickSequence(test, 140, 140, Qt.LeftButton)
    compare(ctl.editIndex, -1)
    compare(ctl.undoCount, 0)
  }
  function test_paintedShapeFollowsTheme() {
    subject.kind = "ellipse"
    verify(waitForRendering(subject))
    compare(grabImage(subject).pixel(70, 50), Qt.rgba(34/255, 34/255, 34/255, 1))
    ctl.itemFill = "#ff00ff"
    tryVerify(function() { return grabImage(subject).pixel(70, 50) === Qt.rgba(1, 0, 1, 1) })
  }
  function test_edit() {
    mouseDoubleClickSequence(test, 140, 140, Qt.LeftButton)
    compare(ctl.editIndex, 0)
    keyClick(Qt.Key_A)
    compare(model.get(0).itext, "a")
    ctl.flushCount = 0
    keyClick(Qt.Key_S, Qt.ControlModifier)
    compare(ctl.flushCount, 1)
    keyClick(Qt.Key_Escape)
    compare(ctl.editIndex, -1)
  }
}
