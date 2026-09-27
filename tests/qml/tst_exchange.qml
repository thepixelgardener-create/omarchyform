import QtQuick
import Quickshell
import Quickshell.Io
import "../.."

// A board with pictures, out of one library and into another. The two halves
// only make sense against each other: a copy that carries its bytes is worth
// nothing unless a machine that has never seen this images folder can open it,
// so the same run does both, through the real helper script.
ShellRoot {
  id: test
  property string dir: Quickshell.env("OMARCHYFORM_TEST_DIR")
  property int stage: 0
  property string importedBoard: ""
  property string lastMessage: ""
  function check(condition, message) {
    if (!condition) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  function read(path) { reader.path = ""; reader.path = path; reader.reload(); reader.waitForJob(); return reader.text() }
  FileView { id: reader; blockLoading: true; blockAllReads: true; printErrors: false }
  // The bytes the fixture was built from, base64 as they travel. Read rather
  // than repeated here, so there is one copy of them in the test — and read
  // once, because a binding through the reader would keep re-reading itself.
  property string pixels: ""
  Component.onCompleted: test.pixels = test.read(test.dir + "/pixels.b64")

  Item {
    id: ctl
    property alias items: items
    property alias links: links
    property int nextId: 1
    property bool boardLoaded: true
    property bool canEdit: true
    property string currentBoard: "a.json"
    // The data folder is below the test folder, because saving a copy into the
    // app's own data folder is refused — which is the rule being relied on.
    readonly property string dataDir: test.dir + "/data"
    readonly property string boardsDir: ctl.dataDir + "/boards"
    readonly property string imagesDir: ctl.dataDir + "/images"
    property var activeBoard: null
    ListModel { id: items }
    ListModel { id: links }
    function fileCommand(action, args) {
      return ["bash", test.dir + "/BoardFiles.sh", action].concat(args)
    }
    function focusKeys() {}
    function stopEditing() {}
    function exportPng(path) {}
    function imagePasted(name) {}
    function imageDropped(name, x, y) {}
    function pasteText(text) {}
  }

  BoardExchange {
    id: exchange
    ctl: ctl
    onCreated: function (path, editFirst) { test.importedBoard = path }
    onFinished: function (message) { test.lastMessage = message }
  }

  Timer {
    interval: 10
    repeat: true
    running: true
    onTriggered: {
      if (test.stage === 0) {
        test.stage = 1
        exchange.importPath(test.dir + "/shared.omarchyform.json")
      } else if (test.stage === 1 && test.importedBoard !== "" && !exchange.busy) {
        test.check(test.importedBoard === "shared.json", "named after the file it came from")
        var board = JSON.parse(test.read(ctl.boardsDir + "/" + test.importedBoard))
        test.check(board.images === undefined, "the bytes do not stay in the board")
        test.check(/^shared-[0-9]+-0\.png$/.test(board.items[0].src),
                   "the picture landed under a name this machine chose: " + board.items[0].src)
        test.check(test.read(ctl.imagesDir + "/" + board.items[0].src).length > 8,
                   "and the file it names is there")
        test.check(board.items[1].src === "", "a picture that could not be read points at nothing")
        test.check(exchange.createdNote.indexOf("1 picture could not be read") > 0,
                   "and that is said out loud: " + exchange.createdNote)
        // The other direction, from a board that names a picture this library has.
        items.append({iid: 1, kind: "image", ix: 0, iy: 0, iw: 100, ih: 100,
                      itint: "foreground", itext: "", ipinned: false, isrc: "pic.png"})
        ctl.nextId = 2
        test.stage = 2
        exchange.exportJson(test.dir + "/out.omarchyform.json")
      } else if (test.stage === 2 && test.lastMessage !== "" && !exchange.busy) {
        var copy = JSON.parse(test.read(test.dir + "/out.omarchyform.json"))
        test.check(copy.items.length === 1 && copy.items[0].src === "pic.png", "the copy still names its picture")
        test.check(copy.images !== undefined && copy.images["pic.png"] === test.pixels,
                   "and carries the bytes of it")
        test.check(test.lastMessage === "Editable copy saved, with its pictures", test.lastMessage)
        console.log("EXCHANGE_TESTS_PASSED")
        Qt.quit()
      }
    }
  }
}
