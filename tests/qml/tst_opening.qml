import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import "../../BoardStore.js" as Store

// A board filled in a slice at a time, the whole way through Qt: a real
// document, its session and its writer, with every row a slice of its own so
// the fill is still going over many ticks. While it is, the board is not
// loaded and nothing saves it; switching to another board midway leaves none
// of the first in the second; opened again, the first comes back whole,
// connectors and all, with its file as it was; and a write from outside while
// a board is opening reaches it once it is in.
ShellRoot {
  id: test
  property string dir: Quickshell.env("OMARCHYFORM_TEST_DIR")
  property int stage: 0
  property int ticks: 0
  property var doc: null
  property string original: ""
  property bool sawPart: false
  // Whether the outside write was noticed while long.json was still opening:
  // if not, the stage did not test what it is for.
  property bool changeSeenOpening: false
  function check(condition, message) {
    if (!condition) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  function read(path) { reader.path = ""; reader.path = path; reader.reload(); reader.waitForJob(); return reader.text() }
  FileView { id: reader; blockLoading: true; blockAllReads: true; printErrors: false }
  // The command line, an editor or a file sync, as in tst_session.qml.
  FileView { id: outside; preload: false; atomicWrites: true; printErrors: false }
  function writeOutside(path, text) {
    outside.path = ""
    outside.path = path
    Qt.callLater(function () { outside.setText(text) })
  }
  // Told of the change when the document is.
  FileView {
    id: watcher
    preload: false
    watchChanges: true
    printErrors: false
    onFileChanged: if (test.doc && test.doc.opening) test.changeSeenOpening = true
  }

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
    property int stateWrites: 0
    function backupPathFor(relative) { return test.dir + "/bak__" + relative + ".bak" }
    function lockPathFor(relative) { return test.dir + "/lock__" + relative + ".lock" }
    function fileCommand(action, args) { return ["bash", test.dir + "/BoardFiles.sh", action].concat(args) }
    function writeState() { stubWorkspace.stateWrites++ }
    function panesViewing(doc) { return [] }
    function recheckPictures(names) {}
  }

  Component {
    id: documents
    BoardDocument { workspace: stubWorkspace; fillSliceMs: 0 }
  }

  function texts() {
    var out = []
    for (var i = 0; i < test.doc.items.count; i++) out.push(test.doc.items.get(i).itext)
    return out
  }

  Timer {
    interval: 5
    repeat: true
    running: true
    onTriggered: {
      test.ticks++
      if (test.stage === 0) {
        test.original = test.read(test.dir + "/big.json")
        test.doc = documents.createObject(test, { currentBoard: "big.json" })
        test.stage = 1
      } else if (test.stage === 1 && test.doc.opening && test.doc.items.count > 2) {
        // Part of the board is in, and it is not a board anyone can change yet.
        test.check(test.doc.items.count < 40, "a row a slice is still filling: " + test.doc.items.count)
        test.check(!test.doc.boardLoaded && !test.doc.canEdit, "a board still opening is read-only")
        test.check(test.doc.openedShare > 0 && test.doc.openedShare < 1, "and says how far it is: " + test.doc.openedShare)
        test.doc.items.setProperty(0, "itext", "changed while opening")
        test.doc.save(true)
        test.doc.flushSave()
        // Away before it finishes.
        test.doc.openBoard("other.json")
        test.check(!test.doc.opening, "a switch leaves the fill where it was")
        test.ticks = 0
        test.stage = 2
      } else if (test.stage === 2 && test.doc.boardLoaded && test.doc.currentBoard === "other.json") {
        test.check(test.texts().join() === "first,second", "only the board switched to: " + test.texts())
        test.check(test.doc.links.count === 1, "with its own connector: " + test.doc.links.count)
        test.ticks = 0
        test.stage = 3
      } else if (test.stage === 3 && test.ticks > 5) {
        test.check(test.read(test.dir + "/big.json") === test.original, "the board left half open was not written")
        test.doc.openBoard("big.json")
        test.ticks = 0
        test.stage = 4
      } else if (test.stage === 4 && test.doc.opening) {
        test.sawPart = true
      } else if (test.stage === 4 && test.doc.boardLoaded && test.doc.currentBoard === "big.json") {
        test.check(test.sawPart, "it opened a slice at a time")
        test.check(test.doc.items.count === 40, "every item: " + test.doc.items.count)
        test.check(test.doc.links.count === 39, "every connector: " + test.doc.links.count)
        test.check(test.doc.items.get(0).itext === "note 1", "as the file has it: " + test.doc.items.get(0).itext)
        test.check(test.doc.nextId === 41, "and the next id after them: " + test.doc.nextId)
        test.check(test.doc.canEdit && test.doc.openedShare === 1, "an editable board, all in")
        test.check(test.read(test.dir + "/big.json") === test.original, "its file untouched by opening")
        watcher.path = test.dir + "/long.json"
        test.doc.openBoard("long.json")
        test.ticks = 0
        test.stage = 5
      } else if (test.stage === 5 && test.doc.opening && test.doc.items.count > 2) {
        // Rewritten from outside while it fills: what is going in was read
        // before the write.
        test.writeOutside(test.dir + "/long.json", JSON.stringify({ kind: "omarchyform.board", version: 5, nextId: 4,
          items: ["one", "two", "three"].map(function (text, i) {
            return { id: i + 1, kind: "note", x: i * 240, y: 0, w: 220, h: 160, tint: "foreground", text: text,
                     pinned: false, src: "" }
          }), links: [] }) + "\n")
        test.ticks = 0
        test.stage = 6
      } else if (test.stage === 6 && test.doc.boardLoaded && test.doc.items.count === 3) {
        test.check(test.changeSeenOpening, "the write landed after the fill; make long.json longer")
        test.check(test.texts().join() === "one,two,three", "the version from outside: " + test.texts())
        test.check(test.doc.canEdit, "and an editable board")
        test.doc.destroy()
        test.ticks = 0
        test.stage = 7
      } else if (test.stage === 6 && test.ticks > 600) {
        test.check(false, "a write while it was opening never reached the board: " + test.doc.items.count + " items")
      } else if (test.stage === 7 && test.ticks > 2) {
        console.log("OPENING_TESTS_PASSED")
        Qt.quit()
      } else if (test.ticks > 2000) test.check(false, "stuck at stage " + test.stage)
    }
  }
}
