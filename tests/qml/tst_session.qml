import QtQuick
import Quickshell
import Quickshell.Io
import "../.."

ShellRoot {
  id: test
  property string dir: Quickshell.env("OMARCHYFORM_TEST_DIR")
  property int stage: 0
  function check(condition, message) {
    if (!condition) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  function read(path) { reader.path = path; reader.reload(); reader.waitForJob(); return reader.text() }
  FileView { id: reader; blockLoading: true; blockAllReads: true; printErrors: false }
  Item {
    id: ctl
    property alias items: items
    property alias links: links
    property bool stateReady: false
    property string currentBoard: "a.json"
    readonly property string boardPath: test.dir + "/" + currentBoard
    property int nextId: 1
    property int nextColor: 0
    property bool windowMode: false
    // The session reads these off the controller; the stub has to carry the
    // same contract or a missing one only shows up as a runtime TypeError.
    property int autosaveMs: 700
    // Somewhere other than beside the board, which is the point, but without
    // needing a directory the app would have created at startup.
    function backupPathFor(relative) { return test.dir + "/bak__" + String(relative).replace(/\//g, "__") + ".bak" }
    property var undoStack: []
    property var redoStack: []
    property int selectedIndex: -1
    property int editIndex: -1
    property int linkingFrom: -1
    property bool browserVisible: false
    property string browserMessage: ""
    ListModel { id: items }
    ListModel { id: links }
    function resetView() {}
    function writeState() {}
    function repaintLinks() {}
    function focusKeys() {}
  }
  BoardSession { id: session; ctl: ctl }
  Timer {
    interval: 10
    repeat: true
    running: true
    onTriggered: {
      if (test.stage === 0 && session.boardLoaded) {
        ctl.items.append({iid: 1, kind: "note", ix: 0, iy: 0, iw: 180, ih: 140, itint: "accent", itext: "first"})
        ctl.nextId = 2
        session.save()
        ctl.items.append({iid: 2, kind: "note", ix: 100, iy: 0, iw: 180, ih: 140, itint: "accent", itext: "second"})
        ctl.nextId = 3
        session.save()
        session.openBoard("b.json", true)
        test.check(ctl.currentBoard === "a.json", "switch waits for save")
        test.check(!session.canEdit, "pending switch blocks edits")
        test.stage = 1
      } else if (test.stage === 1 && ctl.currentBoard === "b.json" && session.boardLoaded && !session.busy) {
        test.check(JSON.parse(test.read(test.dir + "/a.json")).items.length === 2, "queued edits persisted")
        test.check(JSON.parse(test.read(ctl.backupPathFor("a.json"))).items.length === 1, "previous snapshot backed up")
        test.check(JSON.parse(test.read(test.dir + "/b.json")).items.length === 0, "fresh board saved after load")
        test.stage = 2
        session.openBoard("damaged.json")
      } else if (test.stage === 2 && session.damaged) {
        test.check(!session.canEdit && !session.boardLoaded, "damaged board is read-only")
        session.save(true)
        test.check(test.read(test.dir + "/damaged.json") === "{broken", "damaged file preserved")
        test.stage = 3
        session.openBoard("a.json")
      } else if (test.stage === 3 && session.boardLoaded) {
        test.check(ctl.items.count === 2 && session.canEdit, "original board reopens")
        console.log("SESSION_TESTS_PASSED")
        Qt.quit()
      }
    }
  }
  Component.onCompleted: ctl.stateReady = true
}
