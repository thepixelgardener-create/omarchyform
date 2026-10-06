import QtQuick
import "../../BoardStore.js" as Store

// A stand-in for the pane, BoardPane.qml: the controller a Board reads as ctl.
// Written out rather than instantiated for the reason tst_layout gives —
// Theme.qml reads Omarchy's own singletons, and these suites run where there
// is only Qt. tst_pan mounts one board against it, tst_split two.
Item {
  id: ctl

  // ---- the camera, which is what a pan is allowed to touch
  property real camX: 0
  property real camY: 0
  property real zoom: 1
  property real viewW: 800
  property real viewH: 600
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
  // ---- one pane of one, which is the board as it has always been
  property bool active: true
  property bool split: false
  readonly property bool browsing: ctl.active && ctl.library.showing
  property int activations: 0
  function activate() { ctl.activations += 1 }
  function toggleSplit(layout) {}
  function otherPane() {}
  // The same shape the controller builds, because the board asks one question
  // of BoardStore rather than deciding the line twice.
  function statusState() {
    return {
      opened: true, helpVisible: ctl.helpVisible, browserVisible: ctl.browsing, active: ctl.active,
      finding: ctl.finding, saveError: ctl.saveError, trashIndexError: ctl.library.trashIndexError,
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
  // What a picture would be framed around, and what it would be drawn in.
  property string pngPalette: "theme"
  function targets() { return ctl.selectedIndex >= 0 ? [ctl.selectedIndex] : [] }
  function removeTargets() { ctl.removeCount++ }
  function pushUndo() { ctl.undoCount++ }
  function save(quiet) { ctl.saveCount++ }
  function scheduleSave() { ctl.saveCount++ }
  function flushSave() {}
  function beginTextPalette(editor) {}
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
  property string boardTitle: "notes"
  property string boardState: "Saved locally"
  property string currentBoard: "notes.json"
  property string dataDir: "/tmp"
  property string accentMarkup: "#00ffff"
  property bool showGrid: true
  property string canvasPattern: "Dots"
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
  property string paletteScope: "all"
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

  // Shaped like BoardLibrary.qml, for the browser the board carries.
  property QtObject library: QtObject {
    id: libraryStub
    property bool showing: false
    property bool searching: false
    property string query: ""
    property string promptLabel: ""
    property string input: ""
    property string trashIndexError: ""
    property string message: ""
    property string dir: ""
    property string currentBoard: ""
    property var rows: []
    property int index: 0
    property bool inTrash: false
    function enter() {}
    function key(event) {}
    function hide() { libraryStub.showing = false }
  }
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
    property color panelBackground: "#101315"
    property color panelText: "#cccccc"
    property color panelScrim: "#80101315"
    property color cursorFill: "#14cccccc"
    property color cursorText: "cyan"
    property var panelBorder: ({ color: "#cccccc", widths: { top: 2, right: 2, bottom: 2, left: 2 },
                                 gradient: { colors: [], angle: 0, enabled: false } })
    property var cursorBorder: ({ color: "transparent", widths: { top: 0, right: 0, bottom: 0, left: 0 },
                                  gradient: { colors: [], angle: 0, enabled: false } })
    // The shell's button fills, its section label and glyph sizes, and the
    // menu's family.
    property color controlFill: "#0acccccc"
    property color hoverFill: "#14cccccc"
    property string menuFontFamily: "monospace"
    property int fontCaption: 10
    property int fontIcon: 18
    property string fontFamily: "monospace"
    // Not readonly: one test below turns the text up to what a theme with
    // large type does in a small window, which is where a hint that does
    // not wrap covers the board instead of describing it.
    property int fontBody: 12
    property int fontSubtitle: 13
    property int fontHeading: 18
    property int borderWidth: 1
    property int cornerRadius: 0
    readonly property var markupColors: ({ foreground: "#cccccc", accent: "#00ffff",
                                           urgent: "#ff5555", muted: "#888888" })
    function sp(n) { return n }
    function tintFill(tint, strong) { return "#181818" }
    function tintBorder(tint, strong) { return "#cccccc" }
  }

  ListModel { id: itemModel }
  ListModel { id: linkModel }
}
