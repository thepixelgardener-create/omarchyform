import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import "../../BoardStore.js" as Store

// A board's earlier versions the whole way through Qt and the real helper: a
// real document, its session and its writer, against a board written by
// tests/persistence.js. A save keeps what it replaces; saves that follow soon
// after keep nothing more; going back puts a version in the board's place,
// keeps the board as it was, and arrives on screen by the path every change
// on disk arrives by; and something typed and not yet written is written
// first rather than lost.
ShellRoot {
  id: test
  property string dir: Quickshell.env("OMARCHYFORM_TEST_DIR")
  property int stage: 0
  property int ticks: 0
  property var doc: null
  property string first: ""
  function check(condition, message) {
    if (!condition) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  function read(path) { reader.path = ""; reader.path = path; reader.reload(); reader.waitForJob(); return reader.text() }
  FileView { id: reader; blockLoading: true; blockAllReads: true; printErrors: false }
  function texts(raw) {
    var data = Store.readFile(raw)
    return data ? data.items.map(function (r) { return r.text }).join(",") : "unreadable"
  }
  function onScreen() {
    var found = []
    for (var i = 0; i < test.doc.items.count; i++) found.push(test.doc.items.get(i).itext)
    return found.join(",")
  }
  function version(name) { return test.texts(test.read(test.dir + "/versions/v1/plan.json/" + name)) }
  function next(stage) { test.stage = stage; test.ticks = 0 }

  // What a document reads off the workspace, and no panes.
  QtObject {
    id: stubWorkspace
    readonly property string boardsDir: test.dir + "/boards"
    readonly property string backupsDir: test.dir + "/backups"
    readonly property string versionsDir: test.dir + "/versions"
    function versionsPathFor(relative) { return test.dir + "/versions/v1/" + relative }
    property int autosaveMs: 50
    property bool stateReady: true
    property QtObject library: QtObject {
      property bool showing: false
      property string message: ""
    }
    property var activePane: null
    function backupPathFor(relative) { return test.dir + "/backups/" + relative + ".bak" }
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

  function addNote(text) {
    var taken = Store.newIds(test.doc.items, test.doc.nextId, 1)
    test.doc.items.append({ iid: taken.ids[0], kind: "note", ix: taken.ids[0] * 240, iy: 0, iw: 220, ih: 160,
                            itint: "foreground", itext: text, ipinned: false, isrc: "", itexture: "plain" })
    test.doc.nextId = taken.next
    test.doc.noteEdit(null)
  }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      test.ticks++
      if (test.stage === 0) {
        test.doc = documents.createObject(test, { currentBoard: "plan.json" })
        test.next(1)
      } else if (test.stage === 1 && test.doc.items.count === 1 && test.doc.canEdit) {
        test.doc.listVersions()
        test.next(2)
      } else if (test.stage === 2 && !test.doc.versionsLoading && test.ticks > 2) {
        test.check(test.doc.versions.length === 0, "a board never saved over has no earlier versions")
        test.addNote("second")
        test.doc.flushSave()
        test.next(3)
      } else if (test.stage === 3 && test.ticks > 6 && !test.doc.saving) {
        test.check(test.texts(test.read(test.dir + "/boards/plan.json")) === "first,second", "the edit is saved")
        // Straight after, another save: within ten minutes nothing more is kept.
        test.addNote("third")
        test.doc.flushSave()
        test.next(4)
      } else if (test.stage === 4 && test.ticks > 6 && !test.doc.saving) {
        test.doc.listVersions()
        test.next(5)
      } else if (test.stage === 5 && !test.doc.versionsLoading && test.ticks > 2) {
        test.check(test.doc.versions.length === 1, "one version is kept, not one a save: " + test.doc.versions.length)
        test.first = test.doc.versions[0].name
        test.check(test.version(test.first) === "first", "and it is the board the first save replaced: " + test.version(test.first))
        test.doc.restoreVersion(test.first)
        test.next(6)
      } else if (test.stage === 6 && test.doc.items.count === 1 && test.doc.canEdit && !test.doc.saving) {
        test.check(test.onScreen() === "first", "going back puts that version on screen: " + test.onScreen())
        test.check(test.texts(test.read(test.dir + "/boards/plan.json")) === "first", "and in the board's file")
        test.check(test.texts(test.read(test.dir + "/backups/plan.json.bak")) === "first,second,third", "with what it replaced as the backup")
        test.check(test.doc.undoStack.length === 0, "read again as any change on disk is")
        test.doc.listVersions()
        test.next(7)
      } else if (test.stage === 7 && !test.doc.versionsLoading && test.ticks > 2) {
        test.check(test.doc.versions.length === 2, "the board as it was is kept as a version too: " + test.doc.versions.length)
        test.check(test.doc.versions[1].name === test.first, "newest first")
        test.check(test.version(test.doc.versions[0].name) === "first,second,third", "and it is what was there: " + test.version(test.doc.versions[0].name))
        // Typed and not yet written, then going back at once: what was typed
        // is written first, and is what is kept.
        test.addNote("typed just before")
        test.doc.restoreVersion(test.doc.versions[0].name)
        test.next(8)
      } else if (test.stage === 8 && test.doc.items.count === 3 && test.doc.canEdit && !test.doc.saving && test.ticks > 6) {
        test.check(test.onScreen() === "first,second,third", "the version gone back to: " + test.onScreen())
        test.check(test.texts(test.read(test.dir + "/backups/plan.json.bak")) === "first,typed just before",
                   "what was typed was written before the board was replaced")
        test.doc.listVersions()
        test.next(9)
      } else if (test.stage === 9 && !test.doc.versionsLoading && test.ticks > 2) {
        test.check(test.doc.versions.length === 3, "and kept: " + test.doc.versions.length)
        test.check(test.version(test.doc.versions[0].name) === "first,typed just before", "as the newest version")
        // A version that is not there leaves the board as it is.
        test.doc.restoreVersion("20010101-000000.json")
        test.next(10)
      } else if (test.stage === 10 && test.ticks > 8) {
        test.check(test.onScreen() === "first,second,third" && test.doc.canEdit, "a version that is gone changes nothing")
        test.doc.destroy()
        test.next(11)
      } else if (test.stage === 11 && test.ticks > 2) {
        console.log("VERSIONS_TESTS_PASSED")
        Qt.quit()
      } else if (test.ticks > 200) test.check(false, "stuck at stage " + test.stage + " with " + test.onScreen())
    }
  }
}
