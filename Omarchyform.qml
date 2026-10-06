pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "BoardStore.js" as Store

// The plugin entry point, and the workspace every pane lives in: the settings
// and state.json, the boards folder and its library, files coming in and going
// out, the open boards, and the two surfaces the board can live on. A pane
// (BoardPane.qml) is one view of a board and the controller its views read; a
// document (BoardDocument.qml) is one open board and the session saving it.
// The drawing lives in Board.qml and Node.qml, the pure logic in BoardStore.js.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  // --------------------------------------------------------------- appearance
  // What the board looks like is in Theme.qml: one object to pass around and
  // one object for a test to hold, rather than twenty properties here that a
  // stub has to guess at.
  Theme { id: themeTokens }
  readonly property Theme theme: themeTokens

  // -------------------------------------------------------------------- panes
  // The view the keyboard is in. Commands from the keys, the palette, the
  // library and files arriving from outside go to it.
  BoardPane { id: firstPane; workspace: root }
  readonly property var panes: [firstPane]
  property BoardPane activePane: firstPane

  // ---------------------------------------------------------------- documents
  // Every board that is open, each once, however many panes show it.
  property var documents: []

  Component {
    id: documentComponent
    BoardDocument { workspace: root }
  }

  function createDocument(path) {
    var doc = documentComponent.createObject(root, { currentBoard: path })
    root.documents = root.documents.concat([doc])
    return doc
  }

  function panesViewing(doc) {
    var out = []
    for (var i = 0; i < root.panes.length; i++) if (root.panes[i].doc === doc) out.push(root.panes[i])
    return out
  }

  // A pane asks for a board. With one pane and one document, that is the
  // session's own switch: it saves what is open first, waits for a write in
  // flight, and will not walk away from two versions of a board.
  function openInPane(pane, path, fresh) {
    if (!pane.doc) { pane.doc = root.createDocument(path); return }
    pane.doc.openBoard(path, fresh)
  }

  property bool launchNewBoard: false
  Timer {
    interval: 20
    repeat: true
    running: root.launchNewBoard
    onTriggered: if (root.stateReady && !root.library.busy && !boardExchange.busy) {
      root.launchNewBoard = false
      root.activePane.newBoard()
    }
  }

  // A board handed in from outside — a file manager opening one, or a summon
  // carrying a path. It waits for the same three things a new board waits for,
  // because a summon arrives before the state has been read and importing into
  // a board that is still loading is how you lose one.
  //
  // It goes through the exchange rather than straight to openBoard: a path
  // from outside is not a board in the library, and the exchange is what knows
  // how to bring one in, refuse what is not a board, and leave the original
  // alone.
  property string launchOpenPath: ""
  Timer {
    interval: 20
    repeat: true
    running: root.launchOpenPath !== ""
    onTriggered: if (root.stateReady && !root.library.busy && !boardExchange.busy) {
      var path = root.launchOpenPath
      root.launchOpenPath = ""
      boardExchange.importPath(path)
    }
  }

  BoardExchange {
    id: boardExchange
    ctl: root.activePane
    onCreated: function(path, editFirst) {
      var pane = root.activePane
      if (editFirst) pane.pendingFirstNote = path
      pane.openBoard(path, false)
      root.library.rescan()
      pane.flash(editFirst ? "New board · F2 to name it" : "Board imported" + boardExchange.createdNote, "board")
    }
    onFinished: function(message, kind) { root.activePane.flash(message, kind) }
    onFailed: function(message, kind) { root.activePane.report(message, kind) }
    onCopied: function(name) {
      root.library.rescan()
      var doc = root.copyingFor
      root.copyingFor = null
      if (doc) doc.keptAsCopy(name)
    }
  }
  readonly property BoardExchange exchange: boardExchange

  // The board whose edits are being kept as a copy before it takes the version
  // from disk. Held from the request to the answer, because the answer is the
  // exchange's to give and the pane that asked may be somewhere else by then.
  property var copyingFor: null
  function saveConflictCopy(doc, text, name) {
    if (!boardExchange.saveCopy(text, name)) return
    root.copyingFor = doc
  }

  // Configurable from the bar widget's settings, and remembered in state.json
  // so opening from the keyboard uses the same values.
  property int autosaveMs: 700
  property int step: 40
  property bool showGrid: true
  property string canvasPattern: "Dots"
  property bool canvasBackgroundChosen: false
  property bool startWindowed: false
  property bool windowMode: false

  property bool stateReady: false

  readonly property string helperScript: decodeURIComponent(Qt.resolvedUrl("BoardFiles.sh").toString().replace(/^file:\/\//, ""))
  function fileCommand(action, args) {
    return ["bash", root.helperScript, action].concat(args)
  }

  property var boardScreen: null

  function toggleWindowMode() {
    root.windowMode = !root.windowMode
    root.writeState()
  }

  // The same background behind every pane: it is a setting, not part of a
  // board. Whether it changed is the caller's to say.
  function setCanvasBackground(pattern) {
    if (pattern !== "Plain" && Store.CANVAS_PATTERNS.indexOf(pattern) < 0) return false
    root.showGrid = pattern !== "Plain"
    if (root.showGrid) root.canvasPattern = pattern
    // A deliberate choice in the board wins over the bar's opening defaults.
    root.canvasBackgroundChosen = true
    root.writeState()
    return true
  }

  // ------------------------------------------------------------------ library
  // Browsing, naming, folders and the trash, in BoardLibrary.qml. It is told
  // where the library is and which board is open, and asks for the rest.
  BoardLibrary {
    id: boardLibrary
    boardsDir: root.boardsDir
    trashDir: root.trashDir
    trashIndexPath: root.trashIndexPath
    helperScript: root.helperScript
    currentBoard: root.activePane.currentBoard
    boardConflicted: root.activePane.diskChanged
    boardSettled: !root.activePane.saving && root.activePane.saveError === ""
    onOpenRequested: function (path, fresh) { root.activePane.openBoard(path, fresh) }
    onCurrentMoved: function (path) {
      if (root.activePane.doc) root.activePane.doc.currentBoard = path
      root.writeState()
    }
    onNotice: function (message) { root.activePane.flash(message) }
    onClosed: root.activePane.focusKeys()
    onAboutToRename: root.activePane.flushSave()
  }
  readonly property BoardLibrary library: boardLibrary

  function writeState() {
    stateFile.setText(JSON.stringify({
      version: 1,
      lastBoard: root.panes[0].doc ? root.panes[0].doc.currentBoard : "board.json",
      windowMode: root.windowMode,
      autosaveMs: root.autosaveMs,
      step: root.step,
      showGrid: root.showGrid,
      canvasPattern: root.canvasPattern,
      canvasBackgroundChosen: root.canvasBackgroundChosen,
      startWindowed: root.startWindowed
    }, null, 2) + "\n")
  }

  // Which board was open last time, and whether it was windowed. Kept out of
  // the board files so the same board can be opened on two machines without
  // dragging one machine's window preference along with it.
  function applyState(raw) {
    var st = null
    try { st = JSON.parse(raw) } catch (e) { st = null }
    var board = st && Store.safeRelative(st.lastBoard) ? st.lastBoard : ""
    // The first pane's board is the one the state names. Until now nothing was
    // open: there was no board to say what is on it.
    var first = root.panes[0]
    if (!first.doc) first.doc = root.createDocument(board !== "" ? board : "board.json")
    else if (board !== "") first.doc.currentBoard = board
    if (st) {
      root.windowMode = st.windowMode === true
      if (typeof st.autosaveMs === "number") root.autosaveMs = st.autosaveMs
      if (typeof st.step === "number") root.step = st.step
      if (typeof st.showGrid === "boolean") root.showGrid = st.showGrid
      if (Store.CANVAS_PATTERNS.indexOf(st.canvasPattern) >= 0) root.canvasPattern = st.canvasPattern
      root.canvasBackgroundChosen = st.canvasBackgroundChosen === true
      if (typeof st.startWindowed === "boolean") root.startWindowed = st.startWindowed
      // With no board open yet, the bar's preference decides the surface.
      if (st.windowMode === undefined) root.windowMode = root.startWindowed
    }
    root.stateReady = true
  }

  // ----------------------------------------------------------------- lifecycle
  // The output Hyprland has focused, which is where a keyboard-summoned board
  // belongs. Without this the overlay lands wherever Quickshell picks, which
  // on a two-monitor desk is rarely the one being used.
  function focusedScreen() {
    // The same guard the theme reads its own singletons through: this one is
    // Hyprland's, and it is no more a versioned API than the palette is.
    var monitor = root.theme.token(function () { return Hyprland.focusedMonitor }, null)
    var wanted = monitor ? String(monitor.name || "") : ""
    var screens = Quickshell.screens
    if (!screens || screens.length === 0) return null
    for (var i = 0; i < screens.length; i++)
      if (String(screens[i].name) === wanted) return screens[i]
    return screens[0]
  }

  // A summon from the bar carries that widget's settings. Applying them here
  // and writing them to state keeps the two entry points in step: configure on
  // the bar, and the keybinding opens the same board the same way.
  function applyPayload(payloadJson) {
    var p = null
    try { p = JSON.parse(payloadJson || "{}") } catch (e) { return false }
    if (!p || !p.settings) return false
    var st = p.settings
    if (typeof st.autosaveMs === "number") root.autosaveMs = Math.max(100, Math.min(5000, st.autosaveMs))
    if (typeof st.step === "number") root.step = Math.max(5, Math.min(200, st.step))
    if (!root.canvasBackgroundChosen) {
      if (typeof st.showGrid === "boolean") root.showGrid = st.showGrid
      if (Store.CANVAS_PATTERNS.indexOf(st.canvasPattern) >= 0) root.canvasPattern = st.canvasPattern
    }
    if (typeof st.startWindowed === "boolean") root.startWindowed = st.startWindowed
    return true
  }

  function open(payloadJson) {
    var request = null
    try { request = JSON.parse(payloadJson || "{}") } catch (e) {}
    if (request && request.action === "new") root.launchNewBoard = true
    if (request && request.action === "open" && typeof request.path === "string" && request.path !== "")
      root.launchOpenPath = request.path
    if (root.applyPayload(payloadJson)) root.writeState()
    root.boardScreen = root.focusedScreen()
    root.opened = true
    Qt.callLater(function () {
      root.activePane.focusKeys()
      for (var i = 0; i < root.panes.length; i++) {
        root.panes[i].repaintGrid()
        root.panes[i].repaintLinks()
      }
    })
  }

  // The host calls close() for IPC hide/toggle; Escape and window close use
  // the same cleanup before notifying the scoped shell facade.
  function close() {
    for (var p = 0; p < root.panes.length; p++)
      if (root.panes[p].imageBusy) { root.panes[p].flash("Finishing image export…"); return }
    // Closing is not a decision either. A board with two versions keeps both —
    // the edits stay in the session, and the question is still there when it
    // comes back — rather than being asked on the way out of the window.
    for (var d = 0; d < root.documents.length; d++) {
      if (root.documents[d].diskChanged) continue
      root.library.retryTrashIndex()
      root.documents[d].flushSave()
    }
    root.opened = false
    for (var v = 0; v < root.panes.length; v++) root.panes[v].closeView()
    root.library.reset()
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "thepixelgardener.omarchyform")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  readonly property string dataDir: Quickshell.env("HOME") + "/.local/share/omarchyform"
  readonly property string boardsDir: root.dataDir + "/boards"
  // Backups sit outside the boards tree: that tree is meant to be browsed,
  // hand-edited and committed, and .bak files beside every board are noise in
  // all three. The relative path is flattened so one directory holds them all
  // without needing a folder created for every board folder.
  readonly property string backupsDir: root.dataDir + "/backups"
  // Deleting moves a board aside rather than destroying it. The index records
  // where each one came from, so putting it back is exact.
  readonly property string trashDir: root.dataDir + "/trash"
  readonly property string trashIndexPath: root.trashDir + "/index.json"
  // Pasted pictures are shared by every board, and nothing deletes them: a
  // board in the trash still points at its images, and so does a copy someone
  // exported last month. An orphan costs disk; a missing one costs the board.
  readonly property string imagesDir: root.dataDir + "/images"
  // One lock per board, outside the boards tree: the folder people are invited
  // to browse, hand-edit and commit stays free of files that are not boards.
  readonly property string locksDir: root.dataDir + "/locks"
  function lockPathFor(relative) {
    return root.locksDir + "/" + Store.lockKey(String(relative)) + ".lock"
  }

  // The only way a file name out of a board file becomes a URL to load.
  function imagePath(name) {
    return Store.imageIsValid(name) ? "file://" + root.imagesDir + "/" + name : ""
  }

  function backupPathFor(relative) {
    return root.backupsDir + "/" + "v2/" + relative + ".bak"
  }
  readonly property string legacyPath: root.dataDir + "/board.json"
  readonly property string statePath: root.dataDir + "/state.json"

  // The boards directory has to exist before the first atomic write, otherwise
  // the board silently fails to save on a fresh install. A board from before
  // there were folders is copied in rather than moved, so the old file stays
  // put as a fallback. Private like everything BoardFiles.sh creates: -m sets
  // the mode of each folder named, whatever the shell's umask, and only when
  // this creates it — a folder that is already there keeps the mode it has.
  // The data folder is named first so it is one of them, not a parent made in
  // passing with the umask's mode.
  Process {
    id: initProc
    running: true
    command: ["mkdir", "-p", "-m", "700", root.dataDir, root.boardsDir, root.backupsDir, root.trashDir, root.imagesDir, root.locksDir]
    onExited: migrateProc.running = true
  }

  Process {
    id: migrateProc
    command: ["cp", "-n", root.legacyPath, root.boardsDir + "/board.json"]
    onExited: stateFile.reload()
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyState(text())
    onLoadFailed: root.applyState("")
  }

  // ----------------------------------------------------------------- surfaces
  // Built through Variants so the surface is constructed with its screen
  // already set: assigning `screen` to a window that already exists leaves it
  // unmapped, which looks exactly like the board failing to open.
  Variants {
    model: root.opened && !root.windowMode && root.boardScreen ? [root.boardScreen] : []

    delegate: Component {
      PanelWindow {
        required property var modelData

        screen: modelData
        visible: true
        color: "transparent"
        WlrLayershell.namespace: "omarchyform"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: boardExchange.dialogOpen ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }

        Board {
          anchors.fill: parent
          ctl: root.activePane
        }
      }
    }
  }

  // An ordinary toplevel, so Hyprland tiles it beside your other windows.
  FloatingWindow {
    id: boardWindow
    visible: root.opened && root.windowMode
    title: "Omarchyform"
    color: root.theme.canvasBackground
    implicitWidth: 1100
    implicitHeight: 750
    minimumSize: Qt.size(480, 360)

    // Closing from the titlebar or a compositor keybind ends the session the
    // same way Escape does.
    onVisibleChanged: if (!visible && root.opened && root.windowMode) root.dismiss()

    Loader {
      anchors.fill: parent
      focus: true
      active: boardWindow.visible
      sourceComponent: Component {
        Board { ctl: root.activePane }
      }
    }
  }
}
