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
  property string pastedImage: ""
  property string importedBoard: ""
  property string lastMessage: ""
  // Which signal carried it, and what it said it was about. A failure that
  // arrives on `finished` reaches the board as an acknowledgement and is gone
  // in two and a half seconds; this is where that would be caught.
  property string lastKind: ""
  property bool lastFailed: false
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
    function imagePasted(name) { test.pastedImage = name }
    function imageDropped(name, x, y) {}
    function pasteText(text) {}
  }

  BoardExchange {
    id: exchange
    ctl: ctl
    onCreated: function (path, editFirst) { test.importedBoard = path }
    onFinished: function (message, kind) {
      test.lastMessage = message; test.lastKind = kind; test.lastFailed = false
    }
    onFailed: function (message, kind) {
      test.lastMessage = message; test.lastKind = kind; test.lastFailed = true
    }
  }

  Timer {
    interval: 10
    repeat: true
    running: true
    onTriggered: {
      if (test.stage === 0) {
        // A board carrying something that is not a picture cannot arrive
        // whole, so it does not arrive at all: an item pointing at nothing is
        // worse than being told, and the file it came from is still there.
        test.stage = 1
        exchange.importPath(test.dir + "/broken.omarchyform.json")
      } else if (test.stage === 1 && test.lastMessage !== "" && !exchange.busy) {
        test.check(test.importedBoard === "", "a board with an unreadable picture is not imported")
        test.check(test.lastMessage.indexOf("could not be read") > 0, test.lastMessage)
        test.check(test.lastFailed, "an import that could not finish is a failure, not a notice")
        test.check(test.lastKind === "board", "about the board that was being imported: " + test.lastKind)
        test.check(test.read(test.dir + "/broken.omarchyform.json") !== "", "and the file is left alone")
        test.check(test.read(ctl.boardsDir + "/broken.json") === "", "with nothing published")

        // A name no board would write is refused before anything is decoded.
        test.lastMessage = ""
        test.stage = 2
        exchange.importPath(test.dir + "/rejected.omarchyform.json")
      } else if (test.stage === 2 && test.lastMessage !== "" && !exchange.busy) {
        test.check(test.importedBoard === "", "nor is one naming a picture it may not name")
        test.check(test.lastMessage.indexOf("cannot accept") > 0, test.lastMessage)
        test.check(test.lastFailed && test.lastKind === "board", "reported as a board failure")

        // And a file too large to read is refused by its size, before it is.
        test.lastMessage = ""
        test.stage = 3
        exchange.importPath(test.dir + "/enormous.omarchyform.json")
      } else if (test.stage === 3 && test.lastMessage !== "" && !exchange.busy) {
        test.check(test.lastMessage.indexOf("too large") > 0, test.lastMessage)
        test.check(test.lastFailed && test.lastKind === "board", "reported as a board failure")
        test.check(test.importedBoard === "", "and nothing was imported")

        // One with a note the board would refuse to open. Refused here, with
        // the reason, rather than imported to open read-only.
        test.lastMessage = ""
        test.stage = 30
        exchange.importPath(test.dir + "/overlong.omarchyform.json")
      } else if (test.stage === 30 && test.lastMessage !== "" && !exchange.busy) {
        test.check(test.lastMessage === "That board has a note longer than 1 MB", test.lastMessage)
        test.check(test.lastFailed && test.lastKind === "board", "reported as a board failure")
        test.check(test.importedBoard === "", "and nothing was imported")
        test.check(test.read(ctl.boardsDir + "/overlong.json") === "", "or published")

        // One that carries no pictures but names one this library has. It
        // arrives, but the name does not: it would show this library's picture.
        test.lastMessage = ""
        test.stage = 31
        exchange.importPath(test.dir + "/foreign.omarchyform.json")
      } else if (test.stage === 31 && test.importedBoard !== "" && !exchange.busy) {
        test.check(test.importedBoard === "foreign.json", "named after the file it came from: " + test.importedBoard)
        var foreign = JSON.parse(test.read(ctl.boardsDir + "/" + test.importedBoard))
        test.check(foreign.items.length === 1, "the board arrives")
        test.check(foreign.items[0].src === "",
                   "without the name of a picture it did not carry: " + foreign.items[0].src)
        test.check(test.read(ctl.imagesDir + "/pic.png") === test.read(test.dir + "/raw-pixels"),
                   "and the picture of that name here is untouched")

        // The whole one. Two pictures, one of them named twice, and one of
        // them under a name this library already gave to different bytes.
        test.lastMessage = ""
        test.importedBoard = ""
        test.stage = 4
        exchange.importPath(test.dir + "/shared.omarchyform.json")
      } else if (test.stage === 4 && test.importedBoard !== "" && !exchange.busy) {
        test.check(test.importedBoard === "shared.json", "named after the file it came from")
        var board = JSON.parse(test.read(ctl.boardsDir + "/" + test.importedBoard))
        test.check(board.images === undefined, "the bytes do not stay in the board")
        test.check(/^shared-[0-9]+-0\.png$/.test(board.items[0].src),
                   "the picture landed under a name this machine chose: " + board.items[0].src)
        test.check(board.items[1].src === board.items[0].src,
                   "a picture named twice is one picture, landed once")
        test.check(/^shared-[0-9]+-1\.png$/.test(board.items[2].src), "and the other is its own")
        test.check(board.items[2].src !== board.items[0].src, "under a name of its own")
        // The bytes, compared rather than assumed: this is the whole promise.
        test.check(test.read(ctl.imagesDir + "/" + board.items[0].src) === test.read(test.dir + "/raw-other"),
                   "the bytes of the first arrive unchanged")
        test.check(test.read(ctl.imagesDir + "/" + board.items[2].src) === test.read(test.dir + "/raw-pixels"),
                   "and so do the bytes of the second")
        test.check(test.read(ctl.imagesDir + "/pic.png") === test.read(test.dir + "/raw-pixels"),
                   "and the picture this library already had is untouched")
        test.check(exchange.createdNote === "", "nothing to report about it")

        // Out again, from a board that names a picture this library has.
        items.append({iid: 1, kind: "image", ix: 0, iy: 0, iw: 100, ih: 100,
                      itint: "foreground", itext: "", ipinned: false, isrc: "pic.png"})
        ctl.nextId = 2
        test.lastMessage = ""
        test.stage = 5
        exchange.exportJson(test.dir + "/out.omarchyform.json")
        // Everything an export could race with while it reads the pictures out
        // of the library: the board it was taken from is left behind, its
        // picture is deleted, and something else is typed onto it.
        ctl.currentBoard = "somewhere-else.json"
        items.append({iid: 2, kind: "note", ix: 500, iy: 0, iw: 100, ih: 100,
                      itint: "foreground", itext: "after the snapshot", ipinned: false, isrc: ""})
        items.remove(0)
        ctl.nextId = 3
      } else if (test.stage === 5 && test.lastMessage !== "" && !exchange.busy) {
        var copy = JSON.parse(test.read(test.dir + "/out.omarchyform.json"))
        test.check(copy.items.length === 1, "the copy is the board as it was, not as it became")
        test.check(copy.items[0].src === "pic.png", "the copy still names its picture")
        test.check(copy.images !== undefined && copy.images["pic.png"] === test.pixels,
                   "and carries the bytes of it")
        test.check(test.lastMessage === "Editable copy saved, with its pictures", test.lastMessage)
        test.check(!test.lastFailed, "a copy that was written is not a failure")
        test.check(test.lastKind === "board", "and says which operation came back: " + test.lastKind)

        // The whole point, in one run: the copy that was just written is read
        // back in, and the bytes that come out of it are the bytes that went
        // in — under a name of this library's choosing, because the name it
        // travelled under is already taken here.
        test.lastMessage = ""
        test.importedBoard = ""
        test.stage = 51
        exchange.importPath(test.dir + "/out.omarchyform.json")
      } else if (test.stage === 51 && test.importedBoard !== "" && !exchange.busy) {
        var back = JSON.parse(test.read(ctl.boardsDir + "/" + test.importedBoard))
        test.check(back.items.length === 1, "the board comes back whole")
        test.check(back.images === undefined, "with its bytes in the pictures folder")
        test.check(back.items[0].src !== "pic.png", "under a name that was free: " + back.items[0].src)
        test.check(test.read(ctl.imagesDir + "/" + back.items[0].src) === test.read(test.dir + "/raw-pixels"),
                   "and the picture is the one that was sent")
        test.check(test.read(ctl.imagesDir + "/pic.png") === test.read(test.dir + "/raw-pixels"),
                   "with the library's own copy untouched")

        // A board naming a picture the library does not have cannot be copied
        // whole, and a copy that is not whole is not published.
        items.append({iid: 3, kind: "image", ix: 0, iy: 300, iw: 100, ih: 100,
                      itint: "foreground", itext: "", ipinned: false, isrc: "gone.png"})
        test.lastMessage = ""
        test.stage = 6
        exchange.exportJson(test.dir + "/incomplete.omarchyform.json")
      } else if (test.stage === 6 && test.lastMessage !== "" && !exchange.busy) {
        test.check(test.lastMessage.indexOf("missing from your library") > 0, test.lastMessage)
        test.check(test.lastFailed && test.lastKind === "board", "an export that could not finish is a failure")
        test.check(test.read(test.dir + "/incomplete.omarchyform.json") === "",
                   "nothing is published when a picture is missing")

        // Asking for it without its pictures is a different thing, by name.
        test.lastMessage = ""
        test.stage = 7
        exchange.omitPictures = true
        exchange.exportJson(test.dir + "/plain.omarchyform.json")
      } else if (test.stage === 7 && test.lastMessage !== "" && !exchange.busy) {
        var plain = JSON.parse(test.read(test.dir + "/plain.omarchyform.json"))
        test.check(plain.images === undefined, "which arrives without them")
        test.check(plain.items.length === 2, "and with everything else")
        test.check(test.lastMessage.indexOf("without its pictures") > 0, test.lastMessage)
        exchange.omitPictures = false

        // An export that cannot be published leaves whatever is there as it was.
        test.lastMessage = ""
        test.stage = 8
        exchange.exportJson(test.dir + "/locked/there.omarchyform.json")
      } else if (test.stage === 8 && test.lastMessage !== "" && !exchange.busy) {
        test.check(test.read(test.dir + "/locked/there.omarchyform.json") === "not mine to replace",
                   "a failed export does not touch the destination")
        test.check(exchange.error !== "", "and it says so: " + test.lastMessage)
        test.stage = 9
        test.lastMessage = ""
        exchange.paste()
      } else if (test.stage === 9 && (test.pastedImage !== "" || test.lastMessage !== "")) {
        test.check(/^paste-[0-9]+\.png$/.test(test.pastedImage), "clipboard image reaches controller: " + test.lastMessage)
        console.log("EXCHANGE_TESTS_PASSED")
        Qt.quit()
      }
    }
  }
}
