import QtQuick
import QtTest
import "../.."

TestCase {
  id: test
  name: "NodeInteraction"
  when: windowShown
  visible: true
  width: 640
  height: 480
  Item {
    id: ctl
    property alias items: model
    property bool canEdit: true
    property bool showPinned: false
    property int selectedIndex: -1
    property int editIndex: -1
    property int linkingFrom: -1
    property int minItemSize: 60
    property color itemFill: "#222222"
    // Shaped like Theme.qml, because a node cannot tell the difference between
    // this and the real one. tests/contract.js checks that every token a node
    // reads is declared in both.
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
      function tintFill(tint, strong) { return ctl.itemFill }
      function tintBorder(tint, strong) { return "#999999" }
    }
    property int undoCount: 0
    property int saveCount: 0
    property int flushCount: 0
    function isMarked(id) { return false }
    // The camera a node culls itself against. Off by default: these tests are
    // about what one node draws, and a node outside the viewport draws itself
    // plain on purpose, which would make every appearance check here pass for
    // the wrong reason. The culling itself is checked in its own test below.
    property bool culling: false
    property real zoom: 1
    property real camX: 0
    property real camY: 0
    property real viewW: 800
    property real viewH: 600
    property bool findDimming: false
    property string findNeedle: ""
    function matchesFind(text) {
      return findDimming && findNeedle !== "" && text.toLowerCase().indexOf(findNeedle) >= 0
    }
    // A two-pixel red PNG, inline: a real decode with no file to create, clean
    // up, or have the runner refuse to read.
    readonly property string redPixels: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg=="
    function imagePath(name) {
      if (name === "") return ""
      return name === "gone.png" ? "file:///nonexistent/gone.png" : redPixels
    }
    function newBoard() {}
    function repaintLinks() {}
    function pointerSelect(index, additive) { selectedIndex = index; editIndex = -1 }
    function moveTargets(dx, dy) { model.setProperty(0, "ix", model.get(0).ix + dx); model.setProperty(0, "iy", model.get(0).iy + dy) }
    function resizeTargets(dx, dy) { model.setProperty(0, "iw", Math.max(60, model.get(0).iw + dx)); model.setProperty(0, "ih", Math.max(60, model.get(0).ih + dy)) }
    function pushUndo() { undoCount++ }
    function save() { saveCount++ }
    function scheduleSave() { saveCount++ }
    function flushSave() { flushCount++ }
    function stopEditing() { editIndex = -1 }
    function removeItem(index) { model.remove(index) }
    ListModel {
      id: model
      ListElement { ix: 100; iy: 100; iw: 180; ih: 140; itext: "" }
    }
  }
  property int backgroundDoubleClicks: 0
  property int backgroundMiddlePresses: 0
  // Stands in for whatever is under an item on the real board — where the
  // middle button is the camera's. It accepts that button so this suite can
  // say the item let it through rather than only that the item did nothing
  // with it: an item that swallows the press is an item a pan dies on.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    onDoubleClicked: test.backgroundDoubleClicks++
    onPressed: function (mouse) {
      if (mouse.button === Qt.MiddleButton) test.backgroundMiddlePresses++
    }
  }
  Node {
    id: subject
    ctl: ctl
    index: 0
    iid: 1
    ipinned: false
    kind: "note"
    ix: model.get(0).ix
    iy: model.get(0).iy
    iw: model.get(0).iw
    ih: model.get(0).ih
    itint: "foreground"
    itext: model.get(0).itext
    isrc: ""
  }
  function init() {
    backgroundDoubleClicks = 0
    subject.kind = "note"
    subject.isrc = ""
    subject.ipinned = false
    ctl.showPinned = false
    ctl.findDimming = false
    ctl.findNeedle = ""
    ctl.culling = false
    ctl.camX = 0
    ctl.camY = 0
    ctl.zoom = 1
    ctl.itemFill = "#222222"
    ctl.canEdit = true
    ctl.selectedIndex = -1
    ctl.editIndex = -1
    ctl.undoCount = 0
    ctl.saveCount = 0
    ctl.flushCount = 0
    backgroundMiddlePresses = 0
    model.set(0, {ix:100, iy:100, iw:180, ih:140, itext:""})
  }
  function test_drag() {
    mousePress(test, 140, 140, Qt.LeftButton)
    mouseMove(test, 200, 160, -1, Qt.LeftButton)
    mouseRelease(test, 200, 160, Qt.LeftButton)
    compare(model.get(0).ix, 160)
    compare(model.get(0).iy, 120)
    compare(ctl.undoCount, 1)
    compare(ctl.saveCount, 1)
  }
  function test_resize() {
    mousePress(test, 272, 232, Qt.LeftButton)
    mouseMove(test, 312, 252, -1, Qt.LeftButton)
    mouseRelease(test, 312, 252, Qt.LeftButton)
    compare(model.get(0).iw, 220)
    compare(model.get(0).ih, 160)
    compare(ctl.undoCount, 1)
    compare(ctl.saveCount, 1)
  }
  function test_pinnedPointer() {
    subject.ipinned = true
    mousePress(test, 140, 140, Qt.LeftButton)
    mouseMove(test, 200, 160, -1, Qt.LeftButton)
    mouseRelease(test, 200, 160, Qt.LeftButton)
    compare(ctl.selectedIndex, -1)
    mouseDoubleClickSequence(test, 140, 140, Qt.LeftButton)
    compare(backgroundDoubleClicks, 1)
    ctl.showPinned = true
    mouseClick(test, 140, 140, Qt.LeftButton)
    compare(ctl.selectedIndex, 0)
    mouseDoubleClickSequence(test, 140, 140, Qt.LeftButton)
    compare(ctl.editIndex, -1)
    compare(model.get(0).ix, 100)
    compare(ctl.undoCount, 0)
  }
  function test_readOnly() {
    ctl.canEdit = false
    mousePress(test, 140, 140, Qt.LeftButton)
    mouseMove(test, 200, 160, -1, Qt.LeftButton)
    mouseRelease(test, 200, 160, Qt.LeftButton)
    compare(model.get(0).ix, 100)
    compare(model.get(0).iy, 100)
    mouseDoubleClickSequence(test, 140, 140, Qt.LeftButton)
    compare(ctl.editIndex, -1)
    compare(ctl.undoCount, 0)
  }
  function test_image() {
    subject.kind = "image"
    subject.isrc = "ok.png"
    verify(waitForRendering(subject))
    // Inside the frame, and actually decoded rather than left as a tinted box.
    tryVerify(function () { return grabImage(subject).pixel(90, 70) === Qt.rgba(1, 0, 0, 1) })
  }

  function test_missingImage() {
    subject.kind = "image"
    subject.isrc = "gone.png"
    verify(waitForRendering(subject))
    // The frame stays, so a board that lost its pictures still reads as a
    // board rather than as a hole.
    tryVerify(function () { return grabImage(subject).pixel(90, 70) === Qt.rgba(34/255, 34/255, 34/255, 1) })
  }

  function test_findMatchStandsOut() {
    ctl.findDimming = true
    ctl.findNeedle = "keep"
    model.set(0, {ix:100, iy:100, iw:180, ih:140, itext:"keep this one"})
    verify(waitForRendering(subject))
    compare(subject.opacity, 1, "a match stays at full strength")
    verify(subject.foundMatch)

    // What does not match recedes rather than disappearing, so the shape of
    // the board is still readable while searching.
    model.set(0, {ix:100, iy:100, iw:180, ih:140, itext:"something else"})
    verify(waitForRendering(subject))
    verify(!subject.foundMatch)
    verify(subject.opacity < 0.5 && subject.opacity > 0)

    ctl.findDimming = false
    verify(waitForRendering(subject))
    compare(subject.opacity, 1, "and everything comes back when the search ends")
  }

  // An item off the edge of the screen draws itself plain, whatever the board
  // says about it: it is not there to be looked at, and asking every item on a
  // large board to restyle itself for a mark nobody can see was most of what
  // marking one cost. What it must not do is lie once it comes back into view.
  function test_offScreenItemsStayPlain() {
    ctl.culling = true
    ctl.findDimming = true
    ctl.findNeedle = "keep"
    model.set(0, {ix: 40, iy: 40, iw: 180, ih: 140, itext: "keep this one"})
    verify(waitForRendering(subject))
    verify(subject.onScreen, "an item inside the viewport is live")
    verify(subject.foundMatch, "and answers the search")

    // Well past the right-hand edge of an 800-wide viewport.
    model.set(0, {ix: 4000, iy: 40, iw: 180, ih: 140, itext: "keep this one"})
    verify(!subject.onScreen, "an item beyond the viewport is not live")
    verify(!subject.foundMatch, "and does not restyle itself for a search")
    compare(subject.opacity, 1, "nor dim itself where nobody can see it")

    // The camera catches up with it, and it tells the truth again.
    ctl.camX = -3900
    verify(waitForRendering(subject))
    verify(subject.onScreen, "panning to it brings it back")
    verify(subject.foundMatch, "and the match reads as a match again")

    ctl.camX = 0
    ctl.findDimming = false
    ctl.culling = false
    model.set(0, {ix: 100, iy: 100, iw: 180, ih: 140, itext: ""})
    verify(waitForRendering(subject))
  }

  // The edges of the rule, where an off-by-one would show as an item going
  // plain while half of it is still on the screen.
  //
  // Asserted on the property rather than after waitForRendering: culling an
  // item that was already drawing plain changes nothing on screen, so there is
  // no frame to wait for and waiting for one fails.
  function test_cullingEdges() {
    ctl.culling = true

    // Hanging off the right edge by all but a sliver: still live.
    model.set(0, {ix: ctl.viewW - 4, iy: 40, iw: 180, ih: 140, itext: ""})
    verify(subject.onScreen, "an item overlapping the right edge is live")

    // Its trailing edge exactly on the left edge: past it, and out.
    model.set(0, {ix: -180, iy: 40, iw: 180, ih: 140, itext: ""})
    verify(!subject.onScreen, "an item flush against the left edge is out")

    // Zoom counts: the same world position is off screen zoomed in.
    model.set(0, {ix: 700, iy: 40, iw: 180, ih: 140, itext: ""})
    verify(subject.onScreen, "on screen at 1:1")
    ctl.zoom = 4
    verify(!subject.onScreen, "and off it once zoomed in")

    // As does the camera, which is what a pan moves.
    ctl.camX = -2500
    verify(subject.onScreen, "panning to it brings it back")
  }

  function test_paintedShapeFollowsTheme() {
    subject.kind = "ellipse"
    verify(waitForRendering(subject))
    compare(grabImage(subject).pixel(70, 50), Qt.rgba(34/255, 34/255, 34/255, 1))
    ctl.itemFill = "#ff00ff"
    tryVerify(function() { return grabImage(subject).pixel(70, 50) === Qt.rgba(1, 0, 1, 1) })
  }
  // The middle button used to press here: it selected the item and deleted it
  // on release, so a drag meant to move the view destroyed whatever it began
  // on. The item takes no part in it now — it does not consume it either, or
  // the board's pan would stop at the edge of every note.
  function test_middleButtonPassesThroughToWhatIsBehind() {
    mousePress(test, 140, 140, Qt.MiddleButton)
    mouseMove(test, 200, 160, -1, Qt.MiddleButton)
    mouseRelease(test, 200, 160, Qt.MiddleButton)

    compare(backgroundMiddlePresses, 1, "the layer behind the item got the press")
    compare(model.count, 1, "the item is still there")
    compare(model.get(0).ix, 100, "and did not move")
    compare(model.get(0).iy, 100)
    compare(model.get(0).iw, 180, "or resize")
    compare(model.get(0).ih, 140)
    compare(ctl.selectedIndex, -1, "nothing was selected")
    compare(ctl.editIndex, -1, "nothing was typed into")
    compare(ctl.undoCount, 0, "and there is nothing to undo")
    compare(ctl.saveCount, 0)
  }

  // Selected first, because that is the gesture that used to destroy what it
  // landed on: press, release, gone.
  function test_middleClickOnASelectedItemDoesNotDeleteIt() {
    mouseClick(test, 140, 140, Qt.LeftButton)
    compare(ctl.selectedIndex, 0, "selected the ordinary way")

    mouseClick(test, 140, 140, Qt.MiddleButton)
    compare(model.count, 1, "still one item")
    compare(ctl.selectedIndex, 0, "still selected")
    compare(backgroundMiddlePresses, 1, "and the button went past it")
  }

  // The note shows what it says; the editor shows how it was said. They are two
  // items, swapped on the caret, because the text being edited and the text
  // being looked at have to be the same string for the caret to land right.
  function test_aNoteShowsItsMarkupAndEditsItsSource() {
    model.set(0, {ix:100, iy:100, iw:180, ih:140, itext:"# Head\npress `n` for *this*"})
    verify(waitForRendering(subject))

    var shown = findChild(subject, "")  // the rendered Text is the visible one
    compare(ctl.editIndex, -1, "not being typed in")
    // Rendered: the marks are gone and tags have taken their place.
    verify(subject.markup.indexOf("<b>Head</b>") > 0, "the heading is heavy: " + subject.markup)
    verify(subject.markup.indexOf("<b>this</b>") > 0, "and the emphasis is emphasis")
    verify(subject.markup.indexOf("`") < 0, "the marks themselves are not drawn")

    // Editing shows the source, marks and all, so what is typed is what is there.
    mouseDoubleClickSequence(test, 140, 140, Qt.LeftButton)
    compare(ctl.editIndex, 0, "now being typed in")
    compare(model.get(0).itext.indexOf("# Head"), 0, "the source still carries the marks")
    keyClick(Qt.Key_Escape)
  }

  // ctrl+b and the rest put a mark round the selection, and take it off again
  // when pressed a second time.
  function test_chordsWrapTheSelection_data() {
    return [
      { tag: "bold", key: Qt.Key_B, wrapped: "*ab*" },
      { tag: "italic", key: Qt.Key_I, wrapped: "_ab_" },
      { tag: "a key", key: Qt.Key_K, wrapped: "`ab`" },
      { tag: "the accent role", key: Qt.Key_2, wrapped: "[accent]ab[/]" }
    ]
  }

  function test_chordsWrapTheSelection(row) {
    model.set(0, {ix:100, iy:100, iw:180, ih:140, itext:"ab"})
    mouseDoubleClickSequence(test, 140, 140, Qt.LeftButton)
    compare(ctl.editIndex, 0)
    var editor = findChild(subject, "note-editor")
    verify(editor !== null, "the editor is there to type into")
    editor.selectAll()

    keyClick(row.key, Qt.ControlModifier)
    compare(model.get(0).itext, row.wrapped, row.tag + " goes round it")
    keyClick(row.key, Qt.ControlModifier)
    compare(model.get(0).itext, "ab", "and comes off again")
    keyClick(Qt.Key_Escape)
  }

  // Typing replaces the binding that filled the editor, so what it holds and
  // what the board holds can part company. Undo changes the board; the note on
  // screen follows it, and the editor has to as well the next time it is opened.
  function test_theEditorTakesTheBoardsVersionBack() {
    mouseDoubleClickSequence(test, 140, 140, Qt.LeftButton)
    keyClick(Qt.Key_A)
    compare(model.get(0).itext, "a")
    keyClick(Qt.Key_Escape)

    // Something else changes the item — an undo does exactly this.
    model.setProperty(0, "itext", "from the board")
    verify(waitForRendering(subject))
    verify(subject.markup.indexOf("from the board") >= 0, "the note shows it: " + subject.markup)

    mouseDoubleClickSequence(test, 140, 140, Qt.LeftButton)
    compare(ctl.editIndex, 0)
    compare(findChild(subject, "note-editor").text, "from the board",
            "and so does the editor, rather than what was typed before")
    keyClick(Qt.Key_Escape)
  }

  // A board is a file somebody else can send you, and the note is the part they
  // write. Whatever is in it reaches the renderer through the same parser, in
  // QML's own engine rather than the one the store suite runs in — a different
  // stack and a different regex implementation, so the store's word for it is
  // not enough. What must not happen is the board going down on being opened.
  function test_aHostileNoteCannotTakeTheBoardDown_data() {
    return [
      { tag: "tags", text: "<b>x</b><img src='/etc/passwd'><a href='http://x'>y</a>" },
      { tag: "entities", text: "&lt;b&gt;&amp;&#60;script&#62;" },
      { tag: "quotes in a span", text: '[accent]a" onload="x[/]' },
      { tag: "deep nesting", text: "DEEPNEST" },
      { tag: "a very long note", text: "LONGNOTE" },
      { tag: "lone marks", text: "* _ ` [accent] [/] # " }
    ]
  }

  function test_aHostileNoteCannotTakeTheBoardDown(row) {
    var text = row.text
    if (text === "DEEPNEST") {
      text = ""
      for (var d = 0; d < 2000; d++) text += "[accent]"
      text += "x"
      for (var e = 0; e < 2000; e++) text += "[/]"
    } else if (text === "LONGNOTE") {
      text = ""
      for (var n = 0; n < 4000; n++) text += "[urgent]word[/] *bold* `key` "
    }

    model.set(0, {ix:100, iy:100, iw:180, ih:140, itext:text})
    verify(waitForRendering(subject), row.tag + ": the board is still drawing")

    var drawn = subject.markup
    verify(typeof drawn === "string" && drawn.length > 0, row.tag + ": it rendered something")

    // The precise claim, rather than a list of tags to be afraid of: take out
    // the handful this file emits, and no angle bracket may be left. Anything
    // the note itself said arrives as &lt; and is drawn as a character.
    // `href` and `onload` appear in the output of the first row — as text,
    // which is exactly right, so looking for the words would prove nothing.
    var ours = drawn.replace(/<\/?b>|<\/?i>|<br>|<font (?:color="#[0-9a-f]{6}"|size="\d")>|<\/font>/g, "")
    verify(ours.indexOf("<") < 0, row.tag + ": only this file's own tags survive: "
           + ours.slice(0, 120))
    verify(ours.indexOf(">") < 0, row.tag + ": and no stray bracket either")
    // And the board is still working afterwards, which is the whole claim.
    model.set(0, {ix:100, iy:100, iw:180, ih:140, itext:"after"})
    verify(waitForRendering(subject))
    compare(subject.markup, "after", row.tag + ": the next note draws normally")
  }

  function test_edit() {
    mouseDoubleClickSequence(test, 140, 140, Qt.LeftButton)
    compare(ctl.editIndex, 0)
    keyClick(Qt.Key_A)
    compare(model.get(0).itext, "a")
    ctl.flushCount = 0
    keyClick(Qt.Key_S, Qt.ControlModifier)
    compare(ctl.flushCount, 1)
    keyClick(Qt.Key_Escape)
    compare(ctl.editIndex, -1)
  }
}
