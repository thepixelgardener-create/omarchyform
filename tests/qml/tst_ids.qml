import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import "../../BoardStore.js" as Store

// A board that came with an item at the largest id there is, the whole way
// through Qt: a real document, its session and its writer, against a board
// written by tests/persistence.js. New items take their ids as a pane takes
// them (Store.newIds), into the document's int nextId, which must hold one
// past the largest id without wrapping; written and opened again by another
// document, every id and every connector is still there.
ShellRoot {
  id: test
  property string dir: Quickshell.env("OMARCHYFORM_TEST_DIR")
  property int stage: 0
  property int ticks: 0
  property var doc: null
  property var again: null
  property var added: []
  function check(condition, message) {
    if (!condition) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  function read(path) { reader.path = ""; reader.path = path; reader.reload(); reader.waitForJob(); return reader.text() }
  FileView { id: reader; blockLoading: true; blockAllReads: true; printErrors: false }

  // What a document reads off the workspace, and no panes.
  QtObject {
    id: stubWorkspace
    readonly property string boardsDir: test.dir
    readonly property string backupsDir: test.dir
    property int autosaveMs: 50
    property bool stateReady: true
    property QtObject library: QtObject {
      property bool showing: false
      property string message: ""
    }
    property var activePane: null
    function backupPathFor(relative) { return test.dir + "/bak__" + relative + ".bak" }
    function lockPathFor(relative) { return test.dir + "/lock__" + relative + ".lock" }
    function fileCommand(action, args) { return ["bash", test.dir + "/BoardFiles.sh", action].concat(args) }
    function writeState() {}
    function panesViewing(doc) { return [] }
    function recheckPictures(names) {}
  }

  Component {
    id: documents
    BoardDocument { workspace: stubWorkspace }
  }

  // What BoardPane.addItem does with an id.
  function addNote(x) {
    var taken = Store.newIds(test.doc.items, test.doc.nextId, 1)
    test.doc.items.append({ iid: taken.ids[0], kind: "note", ix: x, iy: 300, iw: 180, ih: 140,
                            itint: "foreground", itext: "new", ipinned: false, isrc: "", itexture: "plain" })
    test.doc.nextId = taken.next
    return taken.ids[0]
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      test.ticks++
      if (test.stage === 0) {
        test.doc = documents.createObject(test, { currentBoard: "ceiling.json" })
        test.stage = 1
      } else if (test.stage === 1 && test.doc.items.count === 2 && test.doc.canEdit) {
        test.check(test.doc.nextId === Store.MAX_ID + 1, "a board at the largest id has run out: " + test.doc.nextId)
        test.added = [test.addNote(0), test.addNote(300)]
        test.check(test.added[0] === 1 && test.added[1] === 3, "new notes take the smallest free ids: " + test.added)
        test.check(test.doc.nextId === Store.MAX_ID + 1, "and the int holds one past the largest id: " + test.doc.nextId)
        test.doc.links.append({ lfrom: 2, lto: test.added[0] })
        test.doc.links.append({ lfrom: test.added[1], lto: Store.MAX_ID })
        test.doc.noteEdit(null)
        test.doc.flushSave()
        test.ticks = 0
        test.stage = 2
      } else if (test.stage === 2 && test.ticks > 10 && !test.doc.saving) {
        var saved = JSON.parse(test.read(test.dir + "/ceiling.json"))
        test.check(saved.items.map(function (r) { return r.id }).join() === [2, Store.MAX_ID, 1, 3].join(),
                   "every id written: " + saved.items.map(function (r) { return r.id }))
        test.check(saved.links.length === 3, "with every connector")
        test.again = documents.createObject(test, { currentBoard: "ceiling.json" })
        test.ticks = 0
        test.stage = 3
      } else if (test.stage === 3 && test.again.items.count === 4) {
        var ids = []
        for (var i = 0; i < test.again.items.count; i++) ids.push(test.again.items.get(i).iid)
        test.check(ids.join() === [2, Store.MAX_ID, 1, 3].join(), "opened again, every id is kept: " + ids)
        test.check(test.again.links.count === 3, "and every connector: " + test.again.links.count)
        test.doc.destroy()
        test.again.destroy()
        test.ticks = 0
        test.stage = 4
      } else if (test.stage === 4 && test.ticks > 2) {
        console.log("IDS_TESTS_PASSED")
        Qt.quit()
      } else if (test.ticks > 200) test.check(false, "stuck at stage " + test.stage)
    }
  }
}
