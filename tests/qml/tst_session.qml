import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import "../../BoardStore.js" as Store

ShellRoot {
  id: test
  property string dir: Quickshell.env("OMARCHYFORM_TEST_DIR")
  property int stage: 0
  function check(condition, message) {
    if (!condition) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  function read(path) { reader.path = path; reader.reload(); reader.waitForJob(); return reader.text() }
  FileView { id: reader; blockLoading: true; blockAllReads: true; printErrors: false }
  // Stands in for anything that is not this session: the command line, an
  // editor, a file sync. Deferred like every other write through a FileView,
  // because a path assigned in the same turn is not the one the write goes to.
  FileView { id: outside; preload: false; atomicWrites: true; printErrors: false }
  function writeOutside(path, text) {
    outside.path = ""
    outside.path = path
    Qt.callLater(function () { outside.setText(text) })
  }
  function boardOf(texts) {
    var items = []
    for (var i = 0; i < texts.length; i++)
      items.push({id: i + 1, kind: "note", x: i * 260, y: 0, w: 220, h: 160,
                  text: texts[i], tint: "foreground", pinned: false})
    return JSON.stringify({version: 4, nextId: texts.length + 1, items: items, links: []}) + "\n"
  }
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
    property bool failBackup: false
    function backupPathFor(relative) { if (ctl.failBackup) return test.dir + "/linked/refused.bak"; return test.dir + "/bak__" + String(relative).replace(/\//g, "__") + ".bak" }
    function lockPathFor(relative) { return test.dir + "/lock__" + String(relative).replace(/\//g, "__") + ".lock" }
    function fileCommand(action, args) {
      return ["bash", test.dir + "/BoardFiles.sh", action].concat(args)
    }
    property var undoStack: []
    property var redoStack: []
    readonly property string boardsDir: test.dir
    readonly property string backupsDir: test.dir
    // What was selected is the panes'; the document only says when to forget it.
    function resetSelection(endModes) {}
    // The history is the document's; this one keeps none, as a board written
    // before history did.
    function fileText() { return Store.writeFile(items, links, ctl.nextId) }
    function adoptHistory(text, boardText, raw) { return "" }
    property bool historyChecking: false
    property var pointerOwner: null
    // The session asks whether the library is open, and leaves word there.
    property QtObject library: QtObject {
      property bool showing: false
      property string message: ""
    }
    ListModel { id: items }
    ListModel { id: links }
    function resetView() {}
    function writeState() {}
    function repaintLinks() {}
    function focusKeys() {}
    function flash(text) {}
    // The board puts the three choices on screen; this only has to be callable.
    property int decisions: 0
    function decideConflict() { ctl.decisions += 1 }
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
        test.stage = 4
        session.openBoard("linked/a.json")
      } else if (test.stage === 4 && session.damaged) {
        test.check(session.damageReason !== "" && !session.canEdit, "board behind a symlink is refused")
        test.check(ctl.items.count === 0, "board behind a symlink is not read")
        test.stage = 5
        session.openBoard("a.json")
      } else if (test.stage === 5 && session.boardLoaded) {
        test.check(session.damageReason === "" && session.canEdit, "a normal board opens after a refused one")
        // Something else writes the open board. Nothing is unsaved on screen, so
        // the newer version is what there is, and it appears.
        test.stage = 6
        test.writeOutside(test.dir + "/a.json", test.boardOf(["from outside"]))
      } else if (test.stage === 6 && ctl.items.count === 1) {
        test.check(ctl.items.get(0).itext === "from outside", "an external write is adopted when nothing is unsaved")
        test.check(session.canEdit && !session.conflict, "and the board stays editable")
        // Now both ends change: an edit on screen that has not been saved yet,
        // and three items written underneath it.
        ctl.items.append({iid: 9, kind: "note", ix: 0, iy: 0, iw: 180, ih: 140, itint: "accent", itext: "mine"})
        test.stage = 7
        test.writeOutside(test.dir + "/a.json", test.boardOf(["theirs", "also theirs", "and theirs"]))
      } else if (test.stage === 7 && session.conflict) {
        test.check(ctl.items.count === 2, "the unsaved screen is kept rather than reloaded")
        // Everything that is not someone choosing has to leave both versions
        // alone. This is the regression: flushing is what closing, switching
        // and renaming all call, and it used to resolve the conflict silently.
        session.save()
        session.scheduleSave()
        session.flushSave()
        test.check(!session.busy, "no write starts while the two disagree")
        test.check(session.conflict, "and flushing is not a decision")
        test.check(JSON.parse(test.read(test.dir + "/a.json")).items.length === 3,
                   "so the newer file is still the one on disk")
        // Nor is walking away from the board: the edits are only on screen.
        session.openBoard("b.json")
        test.check(ctl.currentBoard === "a.json", "switching waits for the choice")
        test.check(ctl.decisions > 0, "and asks for it")
        test.check(ctl.items.count === 2, "with the edits still there to choose")
        // Choice three: this version wins, and the other goes to backups.
        session.replaceDisk()
        test.stage = 8
      } else if (test.stage === 8 && !session.conflict && !session.busy) {
        var written = JSON.parse(test.read(test.dir + "/a.json"))
        test.check(written.items.length === 2, "replacing writes what is on screen")
        test.check(written.items[1].text === "mine", "including the edit that was never autosaved")
        test.check(JSON.parse(test.read(ctl.backupPathFor("a.json"))).items.length === 3,
                   "and the version it replaced is in backups")
        // Every save replaces the file rather than changing it, which is enough
        // to end a watch on the old one. So the watch has to still be there
        // after this session's own write, or it only stops noticing.
        test.stage = 9
        test.writeOutside(test.dir + "/a.json", test.boardOf(["after", "our", "own", "write"]))
      } else if (test.stage === 9 && ctl.items.count === 4) {
        test.check(ctl.items.get(3).itext === "write", "the board is still watched after this session saves it")
        // And choice one: the version on disk wins, whatever is on screen.
        ctl.items.append({iid: 21, kind: "note", ix: 0, iy: 0, iw: 180, ih: 140, itint: "accent", itext: "doomed"})
        test.stage = 10
        test.writeOutside(test.dir + "/a.json", test.boardOf(["theirs alone"]))
      } else if (test.stage === 10 && session.conflict) {
        // Change the disk a second time while the first conflict is open.
        test.writeOutside(test.dir + "/a.json", test.boardOf(["latest disk version"]))
        test.stage = 101
      } else if (test.stage === 101 && test.read(test.dir + "/a.json") === test.boardOf(["latest disk version"])) {
        session.useDisk()
        test.stage = 11
      } else if (test.stage === 11 && !session.conflict && ctl.items.count === 1) {
        test.check(ctl.items.get(0).itext === "latest disk version", "resolution reads the latest bytes with their revision")
        test.check(session.canEdit, "and the board is editable again")
        // Which leaves the revision fresh enough to write against without a
        // second conflict: this is the write that used to be refused for ever.
        ctl.items.append({iid: 22, kind: "note", ix: 0, iy: 0, iw: 180, ih: 140, itint: "accent", itext: "after"})
        session.save()
        test.stage = 12
      } else if (test.stage === 12 && !session.busy && !session.conflict) {
        test.check(JSON.parse(test.read(test.dir + "/a.json")).items.length === 2,
                   "a board that took the disk version can be written to again")
        ctl.items.setProperty(0, "itext", "local after failed replacement")
        session.raiseConflict()
        ctl.failBackup = true
        session.replaceDisk()
        test.stage = 13
      } else if (test.stage === 13 && session.conflict && !session.busy) {
        test.check(ctl.items.get(0).itext === "local after failed replacement", "failed replacement keeps local edits")
        ctl.failBackup = false
        session.useDisk()
        test.stage = 14
      } else if (test.stage === 14 && !session.conflict && !session.busy) {
        test.check(ctl.items.get(0).itext === "latest disk version", "use disk recovers after real write failure")
        ctl.items.setProperty(0, "itext", "local before stale switch")
        // Suppress watcher handling to exercise rejection at the write boundary.
        session.pendingBoard = {path: "b.json", fresh: false}
        test.writeOutside(test.dir + "/a.json", test.boardOf(["changed before switch"]))
        test.stage = 141
      } else if (test.stage === 141 && test.read(test.dir + "/a.json") === test.boardOf(["changed before switch"])) {
        session.pendingBoard = null
        session.openBoard("b.json")
        test.stage = 15
      } else if (test.stage === 15 && session.conflict && !session.busy) {
        test.check(session.pendingBoard === null, "stale write cancels its queued switch")
        session.useDisk()
        test.stage = 16
      } else if (test.stage === 16 && !session.conflict && !session.busy) {
        test.check(ctl.currentBoard === "a.json" && session.canEdit, "resolved board remains editable")
        console.log("SESSION_TESTS_PASSED")
        Qt.quit()
      }
    }
  }
  Component.onCompleted: ctl.stateReady = true
}
