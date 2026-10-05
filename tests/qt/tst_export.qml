import QtQuick
import QtTest
import "../.."
import "../../BoardStore.js" as Store

// A PNG export is a photograph of the board, and the pictures on a board are
// decoded on a thread of their own, one after another. These six are big
// enough that they cannot all arrive within the fixed 80ms the export used to
// wait — it saved them as empty frames and reported success — so a picture
// missing from the file is an export that did not wait for it.
//
// The file is read back and its pixels checked, because "the export succeeded"
// was the one thing that was always true. tests/ui.js makes the picture.
TestCase {
  id: test
  name: "ExportWaitsForPictures"
  when: windowShown
  visible: true
  width: 640
  height: 480

  Item {
    id: ctl
    property alias items: itemModel
    property alias links: linkModel
    property int minItemSize: 60
    property QtObject theme: QtObject {
      property int cornerRadius: 0
      property int borderWidth: 1
      property color foreground: "white"
      property color accent: "cyan"
      property string fontFamily: "monospace"
      property int fontSubtitle: 13
      property int fontBody: 11
      property color muted: "#999999"
      property color canvasBackground: "#111111"
      readonly property var markupColors: ({ foreground: "#cccccc", accent: "#00ffff",
                                             urgent: "#ff5555", muted: "#888888" })
      function sp(n) { return n }
      function tintFill(tint, strong) { return "#333333" }
      function tintBorder(tint, strong) { return "#999999" }
    }
    function imagePath(name) { return Qt.resolvedUrl("generated/" + name) }
    ListModel { id: itemModel }
    ListModel { id: linkModel }
  }

  property var outcome: null
  property int told: 0
  BoardImage {
    id: picture
    ctl: ctl
    onFinished: function (success, reason) {
      test.outcome = { success: success, reason: reason, pending: picture.pending() }
    }
    onStillLoading: test.told++
  }
  Image { id: probe; asynchronous: false; cache: false; visible: false }
  Image { id: readBack; asynchronous: false; cache: false }

  function file(name) {
    return decodeURIComponent(Qt.resolvedUrl("generated/" + name).toString().replace(/^file:\/\//, ""))
  }

  function init() {
    probe.source = Qt.resolvedUrl("generated/slow.png")
    if (probe.status !== Image.Ready) skip("tests/ui.js makes the picture this test needs")
    probe.source = ""
    test.outcome = null
    test.told = 0
    picture.quietMs = 1000
    picture.patienceMs = 15000
  }

  function board() {
    var rows = []
    for (var i = 0; i < 6; i++)
      rows.push({ id: i + 1, kind: "image", x: (i % 3) * 110, y: Math.floor(i / 3) * 85, w: 100, h: 75,
                  tint: "foreground", text: "", pinned: false, src: "slow.png" })
    // A picture that is not there has finished loading as well, as a "missing
    // image" line, and must not hold the export up.
    rows.push({ id: 7, kind: "image", x: 330, y: 0, w: 100, h: 75,
                tint: "foreground", text: "", pinned: false, src: "gone.png" })
    Store.fillItems(itemModel, rows)
    linkModel.clear()
    linkModel.append({ lfrom: 1, lto: 2 })
  }

  function test_everyPictureIsInTheFile() {
    test.board()
    picture.save(test.file("export.png"))
    tryVerify(function () { return test.outcome !== null }, 15000, "the export finishes")
    verify(test.outcome.success, "the export succeeds: " + test.outcome.reason)
    compare(test.outcome.pending, 0, "no picture was still loading when the export was taken")

    readBack.source = Qt.resolvedUrl("generated/export.png")
    compare(readBack.status, Image.Ready)
    var shot = grabImage(readBack)
    // The frame is the items' bounds plus 32 pixels of padding on each side.
    for (var j = 0; j < 6; j++) {
      var c = shot.pixel(32 + (j % 3) * 110 + 50, 32 + Math.floor(j / 3) * 85 + 37)
      verify(c.r > 0.7 && c.g < 0.3 && c.b < 0.3, "picture " + (j + 1) + " is in the file, not " + c)
    }
  }

  // With no patience at all, the first look finds pictures still loading: the
  // export says it is waiting, then gives up with a reason and writes nothing.
  function test_givingUpSaysSoAndSavesNothing() {
    test.board()
    picture.quietMs = 0
    picture.patienceMs = 0
    picture.save(test.file("late.png"))
    tryVerify(function () { return test.outcome !== null }, 15000, "the export gives up")
    verify(!test.outcome.success, "an export that gave up does not report success")
    compare(test.outcome.reason, "Pictures took too long to load; PNG not saved")
    compare(test.told, 1, "it said it was waiting, once")
    readBack.source = Qt.resolvedUrl("generated/late.png")
    compare(readBack.status, Image.Error, "nothing was written")
  }
}
