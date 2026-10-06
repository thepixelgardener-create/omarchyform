import QtQuick
import "BoardStore.js" as Store

// One open board: what is on it, the ids it hands out, its undo history and
// the session that loads and saves its file. A pane shows a document and the
// workspace keeps the list of them; two panes on the same board are two views
// of one of these, so they cannot disagree about what the board holds or race
// each other to write it.
//
// The session reads its controller by name, as it always has. This is that
// controller now: what the session asks of the view — forget the selection,
// frame the board, say something on the line — goes on to every pane showing
// this board, and the rest comes from the workspace.
Item {
  id: doc

  required property var workspace

  property alias items: itemModel
  property alias links: linkModel

  ListModel { id: itemModel }
  ListModel { id: linkModel }

  property int nextId: 1
  property int nextColor: 0
  property var undoStack: []
  property var redoStack: []

  // Relative to boardsDir, e.g. "work/project-a.json".
  property string currentBoard: "board.json"
  readonly property string boardPath: doc.workspace.boardsDir + "/" + doc.currentBoard
  readonly property string boardTitle: Store.displayName({ path: doc.currentBoard, dir: false })

  // ------------------------------------------------------- what panes read
  readonly property bool boardLoaded: session.boardLoaded
  readonly property bool damaged: session.damaged
  readonly property string damageReason: session.damageReason
  readonly property string saveError: session.saveError
  // Someone else wrote this board while it was open and the screen has changes
  // of its own. Autosave is waiting, and nothing but a choice clears it.
  readonly property bool diskChanged: session.conflict
  readonly property bool saving: session.busy
  readonly property var pendingBoard: session.pendingBoard
  readonly property bool canEdit: session.canEdit

  // A pane changed what is on the board. Every edit ends in a save, so this is
  // said there; the other pane showing this board looks its cursor up again,
  // because a cursor is a row and rows move when someone else deletes one.
  signal edited(var by)
  function noteEdit(by) { doc.edited(by) }

  function save(allowEmpty) { session.save(allowEmpty) }
  function scheduleSave() { session.scheduleSave() }
  function flushSave() { session.flushSave() }
  function openBoard(path, fresh) { session.openBoard(path, fresh) }
  function useDisk() { session.useDisk() }
  function replaceDisk() { session.replaceDisk() }
  function keptAsCopy(name) { session.keptAsCopy(name) }

  // A new board opened straight into a pane: the file is made once it is
  // confirmed missing, the way a board switched to in place is made. Set when
  // the document is made, before its file has been looked for.
  property bool fresh: false
  Component.onCompleted: if (doc.fresh) session.createWhenLoaded = true

  // ------------------------------------------------ what the session reads
  readonly property int autosaveMs: doc.workspace.autosaveMs
  readonly property bool stateReady: doc.workspace.stateReady
  readonly property string boardsDir: doc.workspace.boardsDir
  readonly property string backupsDir: doc.workspace.backupsDir
  readonly property var library: doc.workspace.library
  function backupPathFor(relative) { return doc.workspace.backupPathFor(relative) }
  function lockPathFor(relative) { return doc.workspace.lockPathFor(relative) }
  function fileCommand(action, args) { return doc.workspace.fileCommand(action, args) }
  function writeState() { doc.workspace.writeState() }

  // Every pane showing this board, for what the session has to say to the view.
  function viewers() { return doc.workspace.panesViewing(doc) }

  // The pane the keyboard is in, if it is showing this board. Filling the model
  // takes the keyboard from the delegates it tears down, and only a pane that
  // had it needs it back.
  function focusKeys() {
    var pane = doc.workspace.activePane
    if (pane && pane.doc === doc) pane.focusKeys()
  }

  // The board under every view is about to be a different one, or the same one
  // read again: what was selected on it means nothing now. Leaving the board
  // also ends what was half done on it.
  function resetSelection(endModes) {
    var panes = doc.viewers()
    for (var i = 0; i < panes.length; i++) panes[i].resetSelection(endModes)
  }

  function resetView() {
    var panes = doc.viewers()
    for (var i = 0; i < panes.length; i++) panes[i].resetView()
  }

  function repaintLinks() {
    var panes = doc.viewers()
    for (var i = 0; i < panes.length; i++) panes[i].repaintLinks()
  }

  function flash(text) {
    var panes = doc.viewers()
    for (var i = 0; i < panes.length; i++) panes[i].flash(text)
  }

  // The question goes where the keyboard is, if that pane is showing this
  // board, and otherwise to whichever pane is.
  function decideConflict() {
    var pane = doc.workspace.activePane
    var panes = doc.viewers()
    if (!pane || pane.doc !== doc) pane = panes.length > 0 ? panes[0] : null
    if (pane) pane.decideConflict()
  }

  BoardSession { id: session; ctl: doc }
}
