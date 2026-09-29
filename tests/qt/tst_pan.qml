import QtQuick
import QtTest
import "../.."
import "../../BoardStore.js" as Store

// The middle button, on the whole canvas rather than on one component.
//
// The Node suite next door can say what a single item does with a press. It
// cannot say what happens to one the item does not take, and that is the whole
// question here: a middle drag has to reach the camera whatever it starts on,
// and a middle press has to reach nothing else on the way. So this mounts the
// real Board — grid, items, marquee, panels, header and all — against a stand
// in controller, and drives it with a pointer.
//
// The stub is written out rather than instantiated for the reason tst_layout
// gives: Theme.qml reads Omarchy's own singletons, and this suite runs where
// there is only Qt.
TestCase {
  id: test
  name: "CanvasPointer"
  when: windowShown
  visible: true
  width: 800
  height: 600

  Item {
    id: ctl

    // ---- the camera, which is what a pan is allowed to touch
    property real camX: 0
    property real camY: 0
    property real zoom: 1
    property real viewW: test.width
    property real viewH: test.height
    function panBy(dx, dy) { ctl.camX += dx; ctl.camY += dy }
    function zoomAt(sx, sy, factor) {
      var next = Math.max(0.2, Math.min(4, ctl.zoom * factor))
      if (next === ctl.zoom) return
      var wx = ctl.toWorldX(sx), wy = ctl.toWorldY(sy)
      ctl.zoom = next
      ctl.camX = sx - wx * ctl.zoom
      ctl.camY = sy - wy * ctl.zoom
    }
    function toWorldX(sx) { return (sx - ctl.camX) / ctl.zoom }
    function toWorldY(sy) { return (sy - ctl.camY) / ctl.zoom }
    function toScreenX(wx) { return wx * ctl.zoom + ctl.camX }
    function toScreenY(wy) { return wy * ctl.zoom + ctl.camY }

    // ---- what is on the board, and what has been done to it
    property alias items: itemModel
    property alias links: linkModel
    property int selectedIndex: -1
    property int editIndex: -1
    property int linkingFrom: -1
    property string linkOutcome: "none"
    property var markedRect: null
    property int undoCount: 0
    property int saveCount: 0
    property int removeCount: 0
    property int minItemSize: 60
    property bool culling: false
    // The same shape the controller builds, because the board asks one question
    // of BoardStore rather than deciding the line twice.
    function statusState() {
      return {
        opened: true, helpVisible: ctl.helpVisible, browserVisible: ctl.browserVisible,
        finding: ctl.finding, saveError: ctl.saveError, trashIndexError: ctl.trashIndexError,
        diskChanged: ctl.diskChanged, damaged: ctl.damaged, failureText: ctl.failureText,
        paletteVisible: ctl.paletteVisible, arranging: ctl.arranging,
        showPinned: ctl.showPinned, editing: ctl.editIndex >= 0,
        linking: ctl.linkingFrom >= 0, statusText: ctl.statusText,
        switching: ctl.pendingBoard !== null, saving: ctl.saving
      }
    }
    function isMarked(id) { return false }
    function matchesFind(text) { return false }
    // A two-pixel red PNG, inline: a real decode with no file to create, so an
    // image on this board is an image rather than an empty frame standing in
    // for one. The same picture tst_node uses.
    readonly property string redPixels: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg=="
    function imagePath(name) { return name === "" ? "" : ctl.redPixels }
    function pointerSelect(index, additive) { ctl.selectedIndex = index; ctl.editIndex = -1 }
    function selectOnly(index) { ctl.selectedIndex = index }
    function markInRect(x0, y0, x1, y1, additive) { ctl.markedRect = [x0, y0, x1, y1] }
    function moveTargets(dx, dy) {
      var i = Math.max(0, ctl.selectedIndex)
      itemModel.setProperty(i, "ix", itemModel.get(i).ix + dx)
      itemModel.setProperty(i, "iy", itemModel.get(i).iy + dy)
    }
    function resizeTargets(dx, dy) {
      var i = Math.max(0, ctl.selectedIndex)
      itemModel.setProperty(i, "iw", Math.max(ctl.minItemSize, itemModel.get(i).iw + dx))
      itemModel.setProperty(i, "ih", Math.max(ctl.minItemSize, itemModel.get(i).ih + dy))
    }
    function removeTargets() { ctl.removeCount++ }
    function pushUndo() { ctl.undoCount++ }
    function save(quiet) { ctl.saveCount++ }
    function scheduleSave() { ctl.saveCount++ }
    function flushSave() {}
    function stopEditing() { ctl.editIndex = -1 }
    function editSelected() { ctl.editIndex = ctl.selectedIndex }
    function addItem(kind, x, y) {
      itemModel.append({ iid: itemModel.count + 100, kind: kind, ix: x, iy: y, iw: 160, ih: 120,
                         itint: "foreground", itext: "", ipinned: false, isrc: "" })
    }

    // ---- the board's own state, and the panels that read it
    property bool canEdit: true
    property bool boardLoaded: true
    property bool damaged: false
    property string damageReason: ""
    property var pendingBoard: null
    property bool saving: false
    property string saveError: ""
    property bool diskChanged: false
    property string statusText: ""
    property string failureText: ""
    property string trashIndexError: ""
    property string boardTitle: "notes"
    property string boardState: "Saved locally"
    property string currentBoard: "notes.json"
    property string dataDir: "/tmp"
    property string accentMarkup: "#00ffff"
    property bool showGrid: true
    property bool showPinned: false
    property bool finding: false
    property string findQuery: ""
    property int findCount: 0
    property bool findDimming: false
    property bool arranging: false
    property bool helpVisible: false
    property bool imageBusy: false
    property var activeBoard: null

    property bool menuVisible: false
    property bool zoomMenuVisible: false
    property int menuIndex: 0
    property bool paletteVisible: false
    property string paletteQuery: ""
    property int paletteIndex: 0
    property int paletteRows: 9
    readonly property var paletteMatches: Store.matchCommands(ctl.paletteQuery)
    function commandReady(needs) { return true }
    function commandExcuse(needs) { return "" }
    function setPaletteQuery(text) { ctl.paletteQuery = text }
    function runPaletteChoice() {}
    function beginPalette() {}
    function endPalette() {}
    function movePalette(step) {}
    property bool conflictVisible: false
    property int conflictIndex: 0
    function runConflictChoice() {}
    function endConflictChoice() {}
    function moveConflict(step) {}

    property bool browserVisible: false
    property bool browserSearching: false
    property string browserQuery: ""
    property string browserPrompt: ""
    property string browserInput: ""
    property string browserMessage: ""
    property string browserDir: ""
    property var browserRows: []
    property int browserIndex: 0
    property bool browserTrash: false
    function browserEnter() {}
    function browserKey(event) {}
    function closeBrowser() { ctl.browserVisible = false }
    function openBrowser() {}

    // ---- everything a keystroke reaches, present and inert: this suite is
    // about the pointer, and a missing one is a TypeError rather than a
    // failure that says so.
    function addRelative(kind) {}
    function alignTargets(edge) {}
    function spreadTargets(axis) {}
    function beginArrange() {}
    function cancelArrange() {}
    function beginFind() {}
    function endFind() {}
    function nextMatch() {}
    function setFindQuery(text) {}
    function beginSelectionActions() { ctl.actionsOpened++ }
    property int actionsOpened: 0
    function back() {}
    function choosePng() {}
    function copySelection() {}
    function cycleKind() {}
    function dropFiles(urls, x, y) {}
    function duplicateTargets() {}
    function exportBoard() {}
    function finishPng(path) {}
    function fitToItems() {}
    function flash(text) { ctl.statusText = text }
    function focusKeys() { if (ctl.activeBoard) ctl.activeBoard.focusKeys() }
    function importBoard() {}
    function layerTargets(where) {}
    function markAll() {}
    function move(dx, dy, carry) {}
    function moveMenu(step) {}
    function newBoard() {}
    function pasteClipboard() {}
    function pasteImage(name, w, h) {}
    function recolorItem() {}
    function redo() {}
    function renameBoard() {}
    function repaintLinks() {}
    function resetView() {}
    function resizeSelected(dx, dy) {}
    function runMenu(index) {}
    function selectNext(step) {}
    function toggleHelp() {}
    function toggleLinking() {}
    function toggleMark() {}
    function toggleMenu() {}
    function togglePin() {}
    function togglePinnedSelection() {}
    function toggleWindowMode() {}
    function undo() {}
    function unlinkSelected() {}
    function zoomCentre(factor) {}

    property QtObject theme: QtObject {
      property color canvasBackground: "#101315"
      property color foreground: "#cccccc"
      property color barBackground: "#161b22"
      property color barForeground: "#e6e6e6"
      property color accent: "cyan"
      property color urgent: "red"
      property color muted: "gray"
      property color dotColor: "#202020"
      property string fontFamily: "monospace"
      // Not readonly: one test below turns the text up to what a theme with
      // large type does in a small window, which is where a hint that does
      // not wrap covers the board instead of describing it.
      property int fontBody: 12
      property int fontSubtitle: 13
      property int fontHeading: 18
      property int borderWidth: 1
      property int cornerRadius: 0
      function sp(n) { return n }
      function tintFill(tint, strong) { return "#181818" }
      function tintBorder(tint, strong) { return "#cccccc" }
    }

    ListModel { id: itemModel }
    ListModel { id: linkModel }
  }

  // Sized rather than anchored, so a test can shrink it to the window a small
  // screen gives the board.
  Board {
    id: surface
    ctl: ctl
    width: test.width
    height: test.height
  }

  // A note, a shape pinned as a background and a picture, and a camera at rest.
  // They sit well below the header, so a press on one is a press on the canvas
  // rather than on the chrome.
  function init() {
    itemModel.clear()
    linkModel.clear()
    itemModel.append({ iid: 1, kind: "note", ix: 100, iy: 200, iw: 200, ih: 150,
                       itint: "foreground", itext: "hello", ipinned: false, isrc: "" })
    itemModel.append({ iid: 2, kind: "rect", ix: 420, iy: 200, iw: 200, ih: 150,
                       itint: "foreground", itext: "", ipinned: true, isrc: "" })
    itemModel.append({ iid: 3, kind: "image", ix: 100, iy: 400, iw: 160, ih: 120,
                       itint: "foreground", itext: "", ipinned: false, isrc: "red.png" })
    ctl.camX = 0
    ctl.camY = 0
    ctl.zoom = 1
    ctl.selectedIndex = -1
    ctl.editIndex = -1
    ctl.showPinned = false
    ctl.helpVisible = false
    ctl.paletteVisible = false
    ctl.browserVisible = false
    ctl.menuVisible = false
    ctl.undoCount = 0
    ctl.saveCount = 0
    ctl.removeCount = 0
    ctl.actionsOpened = 0
    ctl.markedRect = null
    ctl.statusText = ""
    ctl.failureText = ""
    ctl.linkingFrom = -1
    ctl.linkOutcome = "none"
    ctl.conflictVisible = false
    ctl.saveError = ""
    ctl.trashIndexError = ""
    ctl.diskChanged = false
    ctl.damaged = false
    ctl.arranging = false
    ctl.theme.fontBody = 12
    surface.width = test.width
    surface.height = test.height
    wait(0)
  }

  // A point inside the first item, in screen coordinates.
  function onTheNote() {
    return [ctl.toScreenX(itemModel.get(0).ix + 60), ctl.toScreenY(itemModel.get(0).iy + 60)]
  }

  function drag(button, x, y, dx, dy) {
    mousePress(surface, x, y, button)
    // Two steps rather than one: a single move is enough to pan, and a gesture
    // that arrives in pieces is the one a hand actually makes.
    mouseMove(surface, x + dx / 2, y + dy / 2, -1, button)
    mouseMove(surface, x + dx, y + dy, -1, button)
    mouseRelease(surface, x + dx, y + dy, button)
  }

  function geometry() {
    var out = []
    for (var i = 0; i < itemModel.count; i++) {
      var n = itemModel.get(i)
      out.push([n.ix, n.iy, n.iw, n.ih, n.itext])
    }
    return JSON.stringify(out)
  }

  // ------------------------------------------------------------------ panning

  // The displacement is the pointer's, in screen pixels, wherever it started.
  function test_middleDragPansFromAnywhere_data() {
    return [
      { tag: "bare canvas", where: "canvas" },
      { tag: "a note", where: "item" },
      { tag: "a picture", where: "image" },
      { tag: "a pinned background", where: "pinned" },
      // And the same background while backgrounds are the thing being worked
      // on, where its own pointer handling is live rather than stepped aside.
      { tag: "a background in backgrounds mode", where: "pinnedMode" },
      { tag: "the resize grip", where: "grip" }
    ]
  }

  function test_middleDragPansFromAnywhere(row) {
    // The grip only exists on an item that is selected or hovered, so that row
    // selects one first — which is also when a hand would be near it.
    if (row.where === "grip") ctl.selectOnly(0)
    if (row.where === "pinnedMode") { ctl.showPinned = true; wait(0) }
    var was = ctl.selectedIndex
    var at = row.where === "canvas" ? [700, 520]
      : row.where === "item" ? onTheNote()
      : row.where === "image" ? [ctl.toScreenX(180), ctl.toScreenY(460)]
      : row.where === "pinned" || row.where === "pinnedMode"
        ? [ctl.toScreenX(480), ctl.toScreenY(260)]
      : [ctl.toScreenX(itemModel.get(0).ix + itemModel.get(0).iw - 8),
         ctl.toScreenY(itemModel.get(0).iy + itemModel.get(0).ih - 8)]
    var before = geometry()

    drag(Qt.MiddleButton, at[0], at[1], 60, -40)

    compare(ctl.camX, 60, "the camera followed the pointer across")
    compare(ctl.camY, -40, "and down")
    compare(geometry(), before, "and nothing on the board moved or resized")
    compare(ctl.selectedIndex, was, "nor did the selection change on the way")
    compare(ctl.editIndex, -1, "nor typed into")
    compare(ctl.undoCount, 0, "a pan is not a board edit")
    compare(ctl.saveCount, 0, "so there is nothing to save")
    compare(ctl.removeCount, 0, "and nothing was deleted")
  }

  // Screen pixels, not world units. Measured inside an item this would be
  // divided by the zoom, which is a board that runs away from the pointer.
  function test_panFollowsTheScreenAtAnyZoom_data() {
    return [{ tag: "25%", zoom: 0.25 }, { tag: "100%", zoom: 1 },
            { tag: "200%", zoom: 2 }, { tag: "400%", zoom: 4 }]
  }

  function test_panFollowsTheScreenAtAnyZoom(row) {
    // The camera is put where the note's corner lands at a fixed spot on the
    // screen, so the same press is on the note at 25% as at 400%. A note is
    // 200x150, which is 50x37 on screen at the smallest of these.
    ctl.zoom = row.zoom
    ctl.camX = 250 - itemModel.get(0).ix * row.zoom
    ctl.camY = 300 - itemModel.get(0).iy * row.zoom
    wait(0)
    var at = [270, 320]
    verify(at[1] > surface.headerHeight, "clear of the header at " + row.tag)
    var fromX = ctl.camX, fromY = ctl.camY

    drag(Qt.MiddleButton, at[0], at[1], 48, 32)

    compare(ctl.camX - fromX, 48, "the same screen displacement at " + row.tag)
    compare(ctl.camY - fromY, 32, "in both directions")
    compare(ctl.zoom, row.zoom, "and the zoom is not what a pan changes")
  }

  // The gesture that used to delete what it landed on. It now does nothing at
  // all, on an item or off one.
  function test_middleClickWithoutMovementDoesNothing_data() {
    return [{ tag: "on a note", where: "item" }, { tag: "on bare canvas", where: "canvas" }]
  }

  function test_middleClickWithoutMovementDoesNothing(row) {
    ctl.selectOnly(1)
    var at = row.where === "item" ? onTheNote() : [700, 520]
    var before = geometry()

    mouseClick(surface, at[0], at[1], Qt.MiddleButton)

    compare(itemModel.count, 3, "the item is still there")
    compare(geometry(), before, "unchanged")
    compare(ctl.camX, 0, "the camera did not move either")
    compare(ctl.camY, 0)
    compare(ctl.selectedIndex, 1, "the selection is where it was")
    compare(ctl.editIndex, -1, "nothing is being typed in")
    compare(ctl.undoCount, 0, "and there is nothing to undo")
    compare(ctl.saveCount, 0)
    compare(ctl.removeCount, 0)
  }

  // A note being typed in has an editor under the pointer, and on this
  // platform the middle button pastes the primary selection into one. The
  // press never reaches it: the pan takes it first, which is visible here as
  // the camera moving while the text stays as it was.
  function test_middleDragOverAnEditorPansInsteadOfPasting() {
    ctl.selectOnly(0)
    ctl.editSelected()
    wait(0)
    compare(ctl.editIndex, 0, "the note is being typed in")
    var at = onTheNote()

    drag(Qt.MiddleButton, at[0], at[1], 35, 25)

    compare(ctl.camX, 35, "the board moved")
    compare(ctl.camY, 25)
    compare(itemModel.get(0).itext, "hello", "and nothing was pasted into the note")
    compare(ctl.editIndex, 0, "which is still being typed in")
    compare(ctl.saveCount, 0, "and was not written to")
  }

  // ------------------------------------------------------- what still works

  function test_leftDragStillMovesAnItem() {
    var at = onTheNote()
    drag(Qt.LeftButton, at[0], at[1], 40, 20)
    compare(ctl.selectedIndex, 0, "pressing on it selects it")
    compare(itemModel.get(0).ix, 140, "and dragging moves it")
    compare(itemModel.get(0).iy, 220)
    compare(ctl.undoCount, 1, "once, for the whole drag")
    compare(ctl.camX, 0, "and the camera stayed put")
    compare(ctl.camY, 0)
  }

  function test_leftDragOnCanvasStillSweeps() {
    drag(Qt.LeftButton, 660, 450, 80, 60)
    verify(ctl.markedRect !== null, "a rectangle was swept")
    compare(ctl.camX, 0, "and the camera did not move")
  }

  function test_resizeGripStillResizes() {
    ctl.selectOnly(0)
    wait(0)
    var n = itemModel.get(0)
    drag(Qt.LeftButton, ctl.toScreenX(n.ix + n.iw - 8), ctl.toScreenY(n.iy + n.ih - 8), 40, 30)
    compare(itemModel.get(0).iw, 240, "wider")
    compare(itemModel.get(0).ih, 180, "and taller")
    compare(ctl.camX, 0, "without moving the camera")
  }

  function test_rightButtonIsUnchanged() {
    drag(Qt.RightButton, 700, 520, 50, 50)
    compare(ctl.camX, 50, "a right drag still pans")
    compare(ctl.camY, 50)
    compare(ctl.actionsOpened, 0, "and a drag is not a click")

    ctl.camX = 0
    ctl.camY = 0
    mouseClick(surface, 700, 520, Qt.RightButton)
    compare(ctl.actionsOpened, 1, "a right click still asks what can be done")
    compare(ctl.camX, 0, "without panning")
  }

  function test_wheelStillZoomsAtThePointer() {
    var at = onTheNote()
    var worldX = ctl.toWorldX(at[0])
    mouseWheel(surface, at[0], at[1], 0, 120)
    verify(ctl.zoom > 1, "the wheel still zooms over an item")
    fuzzyCompare(ctl.toWorldX(at[0]), worldX, 0.5, "and keeps the point under the pointer")
  }

  function test_doubleClickOnCanvasStillLeavesANote() {
    mouseDoubleClickSequence(surface, 700, 520, Qt.LeftButton)
    compare(itemModel.count, 4, "a new note")
  }

  // The gesture leaves the caret where it was: panning past a note being typed
  // in must not end the editing it crossed, or take the keyboard with it.
  function test_typingStillWorksAfterPanningOverTheEditor() {
    ctl.selectOnly(0)
    ctl.editSelected()
    wait(0)
    var at = onTheNote()
    drag(Qt.MiddleButton, at[0], at[1], 40, 30)
    compare(ctl.camX, 40, "the board moved")
    compare(ctl.editIndex, 0, "and the note is still being typed in")

    keyClick(Qt.Key_Z)
    compare(itemModel.get(0).itext, "helloz", "and the keyboard still reaches it")
  }

  // The windowed mode is a smaller surface, not a different one. This is the
  // size, not the window: what the compositor does with a real toplevel is
  // checked by hand, and docs/usability-checklist.md says how.
  function test_theSameGesturesAtAWindowedSize() {
    surface.width = 520
    surface.height = 380
    wait(0)
    var at = onTheNote()
    verify(at[1] > surface.headerHeight && at[1] < surface.height, "the note is on screen")

    drag(Qt.MiddleButton, at[0], at[1], 40, 25)
    compare(ctl.camX, 40, "a middle drag still pans")
    compare(ctl.camY, 25)
    compare(ctl.selectedIndex, -1, "without touching the selection")

    var was = itemModel.get(0).ix
    at = onTheNote()
    drag(Qt.LeftButton, at[0], at[1], 30, 0)
    compare(itemModel.get(0).ix, was + 30, "and a left drag still moves an item")

    at = onTheNote()
    mouseWheel(surface, at[0], at[1], 0, 120)
    verify(ctl.zoom > 1, "and the wheel still zooms")
  }

  // ------------------------------------------------- the chrome owns itself

  // The pan surface is below the header and the panels. They are not the
  // canvas, and dragging on one should not slide the board about behind it.
  function test_chromeDoesNotPanTheBoard_data() {
    return [
      { tag: "the header", open: "", x: 400, y: 30 },
      { tag: "the command panel", open: "palette", x: 400, y: 120 },
      { tag: "the conflict panel", open: "conflict", x: 400, y: 120 },
      { tag: "the browser", open: "browser", x: 400, y: 300 },
      { tag: "the help panel", open: "help", x: 400, y: 300 }
    ]
  }

  // ------------------------------------------------ what the line says

  // The line under the header is where the connector gesture explains itself,
  // and it is written from the controller's reading of the board rather than
  // from a second guess at it.
  function test_theStatusLineSaysWhatTheGestureWillDo_data() {
    return [
      { tag: "nothing chosen yet", outcome: "none", says: "pick the other end" },
      { tag: "a fresh pair", outcome: "create", says: "connects these two" },
      { tag: "one runs the other way", outcome: "reverse", says: "turns this connector round" },
      { tag: "one runs this way", outcome: "remove", says: "removes this connector" }
    ]
  }

  function test_theStatusLineSaysWhatTheGestureWillDo(row) {
    ctl.linkingFrom = 1
    ctl.linkOutcome = row.outcome
    wait(0)
    var line = findChild(surface, "board-status")
    verify(line !== null, "the board says things somewhere")
    verify(line.visible, "and is saying one now")
    var plain = line.text.replace(/<[^>]*>/g, "")
    verify(plain.indexOf(row.says) >= 0, "it says '" + row.says + "', not: " + plain)
    verify(plain.indexOf("esc") >= 0, "and how to get out of it")
  }

  // A flash says what just happened; the connector line says what is about to.
  // They shared one line and the flash won, so removing a connector and then
  // starting another gesture inside the two and a half seconds the message
  // lasts left "connector removed" on screen where the next outcome belonged —
  // the line promising the wrong thing, which is the one failure the outcome
  // line exists to prevent.
  function test_anActiveConnectorOutranksAStaleMessage_data() {
    return [
      { tag: "after a duplicate", said: "Duplicated", outcome: "create", says: "connects these two" },
      { tag: "after a removal", said: "connector removed · u to undo", outcome: "reverse",
        says: "turns this connector round" },
      { tag: "after a delete", said: "deleted · u to undo", outcome: "remove",
        says: "removes this connector" },
      { tag: "with no far end yet", said: "3 marked", outcome: "none", says: "pick the other end" }
    ]
  }

  function test_anActiveConnectorOutranksAStaleMessage(row) {
    // statusText only: what arrives here is an acknowledgement. A failure that
    // reached the same property would be covered by this very rule, which is
    // what test_aFailureIsVisibleThroughWhateverIsBeingDone is about.
    ctl.statusText = row.said
    ctl.linkingFrom = 1
    ctl.linkOutcome = row.outcome
    wait(0)

    var plain = findChild(surface, "board-status").text.replace(/<[^>]*>/g, "")
    verify(plain.indexOf(row.says) >= 0, "says '" + row.says + "', not: " + plain)
    verify(plain.indexOf(row.said) < 0, "and not the message that had just faded in: " + plain)
  }

  // And the message is still there to read once the gesture is over, rather
  // than being thrown away to make room — until its own timer clears it.
  function test_finishingTheGestureGivesTheMessageTheLineBack() {
    ctl.statusText = "connector removed · u to undo"
    ctl.linkingFrom = 1
    ctl.linkOutcome = "remove"
    wait(0)
    var line = findChild(surface, "board-status")
    verify(line.text.indexOf("removes this connector") >= 0, "the outcome while it is being chosen")

    ctl.linkingFrom = -1
    wait(0)
    verify(line.text.indexOf("connector removed") >= 0, "and what happened once it is done")

    // What the flash timer does. Nothing the line has been holding back comes
    // out of hiding when it fires.
    ctl.statusText = ""
    wait(0)
    verify(line.text.indexOf("connector removed") < 0, "an expired message stays expired")
    verify(line.text.indexOf("removes this connector") < 0, "and nothing takes its place")
  }

  // A board that is not being saved says so, over anything else on the line.
  // These are not messages that fade: each one names something the person has
  // to do before their edits reach the disk, and a connector gesture is a few
  // seconds of edits that would go nowhere.
  function test_aBoardThatCannotSaveSaysSoAboveEverything_data() {
    return [
      { tag: "a failed write", set: "saveError", says: "could not be written" },
      { tag: "a trash index that will not save", set: "trashIndexError", says: "trash index" },
      { tag: "two versions of the board", set: "diskChanged", says: "changed on disk" },
      { tag: "a board that could not be read", set: "damaged", says: "not saving over it" }
    ]
  }

  function test_aBoardThatCannotSaveSaysSoAboveEverything(row) {
    // Everything that competes for the line, all at once, with the connector
    // gesture running: the one that must win is the one that blocks a save.
    ctl.statusText = "Duplicated"
    ctl.linkingFrom = 1
    ctl.linkOutcome = "create"
    ctl.editIndex = 0
    ctl.arranging = true
    ctl.showPinned = true
    if (row.set === "saveError") ctl.saveError = "notes.json could not be written"
    else if (row.set === "trashIndexError") ctl.trashIndexError = "the trash index could not be saved"
    else if (row.set === "diskChanged") ctl.diskChanged = true
    else ctl.damaged = true
    wait(0)

    var line = findChild(surface, "board-status")
    var plain = line.text.replace(/<[^>]*>/g, "")
    verify(plain.toLowerCase().indexOf(row.says) >= 0, "says '" + row.says + "', not: " + plain)
    verify(plain.indexOf("connects these two") < 0, "not the connector outcome: " + plain)
    verify(plain.indexOf("Duplicated") < 0, "and not a message that is about to fade")
    verify(line.visible, "and it is on screen to be acted on")

    ctl.saveError = ""
    ctl.trashIndexError = ""
    ctl.diskChanged = false
    ctl.damaged = false
    ctl.arranging = false
    ctl.showPinned = false
    ctl.editIndex = -1
  }

  // Typing is the narrower claim on the keyboard: while a caret is in a note,
  // x is the letter x, so the line must not offer to connect anything.
  function test_typingStillOwnsTheLineOverAHeldConnector() {
    ctl.statusText = "Text pasted · enter to edit"
    ctl.linkingFrom = 1
    ctl.linkOutcome = "create"
    ctl.editIndex = 0
    wait(0)

    var plain = findChild(surface, "board-status").text.replace(/<[^>]*>/g, "")
    verify(plain.indexOf("done typing") >= 0, "says how to stop typing, not: " + plain)
    verify(plain.indexOf("connects these two") < 0, "and does not promise x will connect anything")
    ctl.editIndex = -1
  }

  // The other half of the same problem. Ranking the connector outcome above a
  // flash fixed a stale "Duplicated" covering it — and would have buried a
  // clipboard that never answered under the same rule, because both arrive on
  // statusText. A failure is its own rank: under the things that stop the
  // board saving, over everything the person has started since.
  function test_aFailureIsVisibleThroughWhateverIsBeingDone_data() {
    return [
      { tag: "while connecting", mode: "linking", said: "Could not reach the clipboard" },
      { tag: "while typing", mode: "editing", said: "Could not save PNG; choose a location outside the app data folder" },
      { tag: "while arranging", mode: "arranging", said: "That is not an image this can read" },
      { tag: "in backgrounds", mode: "pinned", said: "A picture in that board could not be read; nothing was imported" },
      { tag: "with the command list open", mode: "palette", said: "Clipboard has no available text" },
      { tag: "with nothing else going on", mode: "", said: "Could not copy that picture" }
    ]
  }

  function test_aFailureIsVisibleThroughWhateverIsBeingDone(row) {
    // And a stale acknowledgement underneath it, which is what it has to beat.
    ctl.statusText = "Duplicated"
    if (row.mode === "linking") { ctl.linkingFrom = 1; ctl.linkOutcome = "create" }
    else if (row.mode === "editing") ctl.editIndex = 0
    else if (row.mode === "arranging") ctl.arranging = true
    else if (row.mode === "pinned") ctl.showPinned = true
    else if (row.mode === "palette") ctl.paletteVisible = true
    ctl.failureText = row.said
    wait(0)

    var line = findChild(surface, "board-status")
    var plain = line.text.replace(/<[^>]*>/g, "")
    compare(plain, row.said, "the failure has the line " + row.tag)
    verify(line.visible, "and is on screen to be read")
  }

  // Under the four that do not go away on their own. Those are conditions, not
  // events: each one is a reason the board is not saving at all, and a failed
  // copy is not a reason to stop saying so.
  function test_aBlockedSaveStillOutranksAFailure_data() {
    return [
      { tag: "a failed write", set: "saveError", says: "could not be written" },
      { tag: "a trash index that will not save", set: "trashIndexError", says: "trash index" },
      { tag: "two versions of the board", set: "diskChanged", says: "changed on disk" },
      { tag: "a board that could not be read", set: "damaged", says: "not saving over it" }
    ]
  }

  function test_aBlockedSaveStillOutranksAFailure(row) {
    ctl.failureText = "Could not reach the clipboard"
    if (row.set === "saveError") ctl.saveError = "notes.json could not be written"
    else if (row.set === "trashIndexError") ctl.trashIndexError = "the trash index could not be saved"
    else if (row.set === "diskChanged") ctl.diskChanged = true
    else ctl.damaged = true
    wait(0)

    var plain = findChild(surface, "board-status").text.replace(/<[^>]*>/g, "")
    verify(plain.toLowerCase().indexOf(row.says) >= 0, "says '" + row.says + "', not: " + plain)
    verify(plain.indexOf("clipboard") < 0, "and not the failure underneath it: " + plain)

    ctl.saveError = ""
    ctl.trashIndexError = ""
    ctl.diskChanged = false
    ctl.damaged = false
  }

  // The line renders markup, and a failure has been through a file name, a
  // helper's output or a board somebody else wrote. This is the one place on
  // the board that reads tags, so what arrives here is escaped like everything
  // else that reaches it from outside.
  function test_aFailureCannotPutMarkupOnTheLine() {
    ctl.failureText = "Could not read <b>bold</b> & <font color=\"red\">red</font>.png"
    wait(0)
    var line = findChild(surface, "board-status")
    verify(line.text.indexOf("&lt;b&gt;") >= 0, "the tags arrive as text: " + line.text)
    verify(line.text.indexOf("&amp;") >= 0, "and so does the ampersand")
    verify(line.text.indexOf("<b>") < 0, "nothing in it is a tag the line obeys")
    verify(line.text.indexOf("<font color=\"red\">") < 0, "including one that would recolour it")
  }

  // A theme with large text in a small window is where a hint stops fitting.
  // It has to wrap into the line rather than run off the side of the board or
  // climb over the header, whichever of the four things it is saying.
  function test_theLineWrapsInASmallWindowAtALargeSize_data() {
    return test_theStatusLineSaysWhatTheGestureWillDo_data()
  }

  function test_theLineWrapsInASmallWindowAtALargeSize(row) {
    surface.width = 380
    surface.height = 320
    ctl.theme.fontBody = 24
    ctl.linkingFrom = 1
    ctl.linkOutcome = row.outcome
    wait(0)

    var line = findChild(surface, "board-status")
    verify(line.width <= surface.width, "the line stays inside the board")
    verify(line.x >= 0, "and starts inside it")
    verify(line.contentWidth <= line.width + 1, "it wrapped rather than running off the side")
    verify(line.y >= surface.headerHeight, "and sits under the header rather than over it")
    verify(line.y + line.height < surface.height, "with the canvas still showing below it")
  }

  function test_chromeDoesNotPanTheBoard(row) {
    if (row.open === "palette") ctl.paletteVisible = true
    else if (row.open === "conflict") ctl.conflictVisible = true
    else if (row.open === "browser") ctl.browserVisible = true
    else if (row.open === "help") ctl.helpVisible = true
    wait(0)
    // The panel has to actually be under the point the drag starts at, or this
    // passes by pressing on bare canvas that happens not to pan either.
    if (row.open !== "") {
      var panel = findChild(surface, row.open === "palette" ? "command-palette"
        : row.open === "conflict" ? "conflict-panel"
        : row.open === "browser" ? "browser-panel" : "help-panel")
      verify(panel !== null && panel.visible, row.tag + " is on screen")
      var at = panel.mapFromItem(surface, row.x, row.y)
      verify(at.x >= 0 && at.y >= 0 && at.x <= panel.width && at.y <= panel.height,
             row.tag + " is under the press at " + row.x + "," + row.y)
    }

    drag(Qt.MiddleButton, row.x, row.y, 70, 50)

    compare(ctl.camX, 0, "the board stayed where it was under " + row.tag)
    compare(ctl.camY, 0)
  }
}
