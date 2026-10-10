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
      property color urgent: "#ff5555"
      property color canvasBackground: "#111111"
      property bool isLight: false
      property color dotColor: "#202020"
      property int fontHeading: 16
      property color panelScrim: "#80000000"
      readonly property var markupColors: ({ foreground: "#cccccc", accent: "#00ffff",
                                             urgent: "#ff5555", muted: "#888888" })
      function sp(n) { return n }
      function tintFill(tint, strong, under) { return "#333333" }
      function tintBorder(tint, strong) { return "#999999" }
    }
    // The board's own canvas colour, which a picture "as it looks" follows.
    property QtObject sceneTheme: QtObject {
      property var chosen: null
      property string shade: "Theme"
    }
    function imagePath(name) { return Qt.resolvedUrl("generated/" + name) }
    ListModel { id: itemModel }
    ListModel { id: linkModel }
  }

  property var outcome: null
  property color expectedCanvas: "transparent"
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
    ctl.sceneTheme.chosen = null
    ctl.sceneTheme.shade = "Theme"
    picture.exportColors = "theme"
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

  function test_canvasPaletteAndTextureInSavedPng_data() {
    return [{tag:"Theme", colour:"Theme"}, {tag:"Paper", colour:"Paper"}, {tag:"Ink", colour:"Ink"}]
  }
  function test_canvasPaletteAndTextureInSavedPng(row) {
    ctl.sceneTheme.chosen = Store.canvasPalette(row.colour)
    ctl.sceneTheme.shade = row.colour
    Store.fillItems(itemModel, [{id:1, kind:"rect", x:0, y:0, w:180, h:140,
      text:"", tint:"foreground", texture:"grid"}])
    linkModel.clear()
    var patternedFile = "texture-" + row.colour + ".png"
    picture.save(test.file(patternedFile))
    tryVerify(function () { return test.outcome !== null }, 15000)
    verify(test.outcome.success)
    readBack.source = Qt.resolvedUrl("generated/" + patternedFile)
    compare(readBack.status, Image.Ready)
    var textured = grabImage(readBack)
    test.expectedCanvas = row.colour === "Theme" ? ctl.theme.canvasBackground : ctl.sceneTheme.chosen.background
    compare(textured.pixel(5, 5), test.expectedCanvas, "canvas colour reaches PNG")
    itemModel.setProperty(0, "itexture", "plain")
    test.outcome = null
    var plainFile = "plain-" + row.colour + ".png"
    picture.save(test.file(plainFile))
    tryVerify(function () { return test.outcome !== null }, 15000)
    verify(test.outcome.success)
    readBack.source = Qt.resolvedUrl("generated/" + plainFile)
    compare(readBack.status, Image.Ready)
    verify(!textured.equals(grabImage(readBack)), "texture reaches PNG")
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

  // Each item an export draws used to log a QQuickItem::stackAfter warning:
  // the repeater sat beside the layer its items moved into, so it could stand
  // none of them after the one before. On a board with no backgrounds there is
  // nothing it cannot stand after now, so there is nothing to warn about.
  function test_anExportStacksWithoutWarnings() {
    failOnWarning(/stack(After|Before)/)
    var rows = []
    for (var i = 0; i < 12; i++)
      rows.push({ id: i + 1, kind: "note", x: (i % 4) * 110, y: Math.floor(i / 4) * 85, w: 100, h: 75,
                  tint: "foreground", text: "note " + i, pinned: false })
    Store.fillItems(itemModel, rows)
    linkModel.clear()
    picture.save(test.file("quiet.png"))
    tryVerify(function () { return test.outcome !== null }, 15000, "the export finishes")
    verify(test.outcome.success, "the export succeeds: " + test.outcome.reason)
  }
}
