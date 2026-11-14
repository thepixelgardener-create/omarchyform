import QtQuick
import Quickshell
import Quickshell.Io
import "BoardStore.js" as Store

// A picture of a board with no shell and no display: what `omarchyform render`
// starts, on Quickshell's offscreen platform, in a process of its own. It is
// the board's own export scene (BoardImage, and the Node every item is drawn
// by) behind a controller that holds a board and nothing else, so a picture
// made here and one made with ctrl+e are drawn by the same code.
//
// The command line has read and bounded the board before this starts, and has
// had every picture on it checked. What it found is in the staging folder it
// names: board.json, written the way a board is saved, and job.json, which
// says what to draw and which pictures may be opened. The PNG goes into the
// same folder, and how it went is the exit status: nothing is logged, and
// nothing else is written.
ShellRoot {
  id: render

  readonly property string stage: Quickshell.env("OMARCHYFORM_RENDER_DIR")
  property var job: null
  property var board: null
  property bool answered: false

  // Read back by RENDER_EXITS in bin/omarchyform.
  readonly property int drawn: 0
  readonly property int unreadable: 3
  readonly property int nothingToDraw: 4
  readonly property int picturesTooSlow: 5

  function answer(code) {
    if (render.answered) return
    render.answered = true
    Qt.exit(code)
  }

  function begin() {
    if (render.job === null || render.board === null || render.answered) return
    Store.fillItems(itemModel, render.board.items)
    Store.fillLinks(linkModel, itemModel, render.board.links)
    picture.exportColors = render.job.colors
    picture.crop = render.job.only
    picture.save(render.stage + "/out.png")
  }

  // Both files are this program's own, written a moment ago by the command
  // line, but they are read as anything else is: bounded, and a file that is
  // not what it should be is an answer rather than an exception.
  FileView {
    path: render.stage + "/job.json"
    watchChanges: false
    printErrors: false
    onLoaded: {
      var job = null
      try { job = Store.parseJson(text()) } catch (e) { job = null }
      if (!job || !Store.exportPalette(job.colors) || !Array.isArray(job.only) || !job.pictures || typeof job.imagesDir !== "string")
        return render.answer(render.unreadable)
      render.job = job
      render.begin()
    }
    onLoadFailed: render.answer(render.unreadable)
  }
  FileView {
    path: render.stage + "/board.json"
    watchChanges: false
    printErrors: false
    onLoaded: {
      var board = Store.readFile(text())
      if (!board || Store.boardLimit(board) !== "") return render.answer(render.unreadable)
      render.board = board
      render.begin()
    }
    onLoadFailed: render.answer(render.unreadable)
  }

  // Everything BoardImage reads off a controller. The theme is what Theme.qml
  // falls back to without the shell: a picture made here is always in one of
  // the export palettes, which name their colours outright, so of the theme
  // only the type and the metrics are drawn.
  Item {
    id: holder
    property alias items: itemModel
    property alias links: linkModel
    readonly property int minItemSize: Store.MIN_SIZE
    readonly property QtObject theme: QtObject {
      readonly property color canvasBackground: "#101315"
      readonly property color foreground: "#CACCCC"
      readonly property color accent: "#CACCCC"
      readonly property color urgent: "#A55555"
      readonly property color muted: "#707880"
      readonly property bool isLight: false
      readonly property color dotColor: "#14CACCCC"
      readonly property color panelScrim: "#80101315"
      readonly property var markupColors: ({ foreground: "#CACCCC", accent: "#CACCCC", urgent: "#A55555", muted: "#707880" })
      readonly property string fontFamily: "monospace"
      readonly property int fontBody: 12
      readonly property int fontSubtitle: 13
      readonly property int fontHeading: 16
      readonly property int borderWidth: 1
      readonly property int cornerRadius: 0
      function sp(n) { return n }
      function tintFill(tint, strong, under) { return "#101315" }
      function tintBorder(tint, strong) { return "#CACCCC" }
    }
    readonly property QtObject sceneTheme: QtObject {
      readonly property var chosen: null
      readonly property string shade: "Theme"
    }
    // The gate imagePath is in the shell: a picture is opened only once the
    // helper's checkimages has found it fit. The command line asked before
    // this started, and anything it did not clear is drawn as a missing one.
    function imagePath(name) {
      return holder.pictureState(name) === "" ? "file://" + render.job.imagesDir + "/" + name : ""
    }
    // A picture made here is said in English, as the command line itself
    // speaks: it answers a program, and what is in the file is the board.
    function t(text, a, b, c) { return Store.translated(null, text, [a, b, c]) }
    function tv(text) { return text }
    function pictureState(name) {
      if (!Store.imageIsValid(name) || render.job === null) return "missing"
      var found = render.job.pictures[name]
      return typeof found === "string" ? found : "could not be checked"
    }
    ListModel { id: itemModel }
    ListModel { id: linkModel }
  }

  // The scene needs a window to be drawn in; offscreen, nobody sees it.
  FloatingWindow {
    visible: true
    implicitWidth: 64
    implicitHeight: 64
    BoardImage {
      id: picture
      ctl: holder
      // The one reason an export gives is that its pictures did not arrive;
      // without one, there was nothing to put a frame round.
      onFinished: function (success, reason) {
        render.answer(success ? render.drawn : reason !== "" ? render.picturesTooSlow : render.nothingToDraw)
      }
    }
  }
}
