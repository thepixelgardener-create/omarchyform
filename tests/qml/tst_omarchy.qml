import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import "services" as Host

ShellRoot {
  id: test
  property int stage: 0

  // `saving` is a write being in flight, and it reads false on both sides of
  // one — before it starts as well as after it ends. Waiting for it to be
  // false is therefore not waiting for a write: under load the tick that
  // checked arrived in the gap before the write began, and read the file as it
  // was before the change. That is the flake this replaces.
  //
  // These watch the edges instead. `expectWrite()` arms before the thing that
  // causes the write, and `wrote` turns true only once one has both started
  // and finished since. A stage that never sees its write runs out the clock
  // and says which stage it was, rather than passing on stale contents.
  property bool writing: false
  property bool wrote: false
  function expectWrite() { test.writing = false; test.wrote = false }
  Connections {
    target: plugin.activePane
    function onSavingChanged() {
      if (plugin.activePane.saving) test.writing = true
      else if (test.writing) { test.writing = false; test.wrote = true }
    }
  }
  property int ticks: 0
  property int hides: 0
  property int switchedAt: 0
  property real dropX: 0
  property real dropY: 0
  property string newPath: ""
  property var exchangeApi: null
  property var closedWindow: null
  property double newStarted: 0
  function findItem(parent, name) {
    if (parent.objectName === name) return parent
    for (var i = 0; i < parent.children.length; i++) {
      var found = test.findItem(parent.children[i], name)
      if (found) return found
    }
    return null
  }
  function pick(path) {
    for (var i = 0; i < plugin.library.rows.length; i++) {
      if (plugin.library.rows[i].path === path) { plugin.library.index = i; return true }
    }
    return false
  }
  FileView { id: disk; blockLoading: true; blockAllReads: true; printErrors: false }
  function boardData(path) {
    disk.path = plugin.boardsDir + "/" + path
    disk.reload()
    disk.waitForJob()
    try { return JSON.parse(disk.text()) } catch (e) { return null }
  }
  function key(name, modifiers) {
    var args = 'mods = ' + JSON.stringify(modifiers || "") + ', key = ' + JSON.stringify(name)
      + ', window = "pid:' + Quickshell.processId + '"'
    keyProc.command = ["hyprctl", "eval",
      'hl.dispatch(hl.dsp.send_key_state({' + args + ', state = "down"})); '
      + 'hl.dispatch(hl.dsp.send_key_state({' + args + ', state = "up"}))']
    keyProc.running = true
  }
  Process {
    id: keyProc
    stdout: StdioCollector { onStreamFinished: if (text.trim() !== "ok") console.log("KEY: " + text) }
    stderr: StdioCollector { onStreamFinished: if (text.trim()) console.log("KEYERR: " + text) }
    onExited: function(code) { test.check(code === 0, "targeted keyboard injection") }
  }
  function check(condition, message) {
    if (!condition) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  // No absolute placement in the plugin's own API: items move by dragging or
  // nudging, both relative. The model is what an export reads, so the test
  // writes it the same way it writes text into a note.
  function place(index, x, y, w, h) {
    plugin.activePane.items.setProperty(index, "ix", x)
    plugin.activePane.items.setProperty(index, "iy", y)
    plugin.activePane.items.setProperty(index, "iw", w)
    plugin.activePane.items.setProperty(index, "ih", h)
  }

  // Painting order is the order the delegates sit in under their parent: the
  // last one is drawn over the ones before it. Nothing exposes that as a
  // property, so it is read off the scene.
  function drawnAfter(later, earlier) {
    var a = test.findItem(plugin.activePane.activeBoard, later)
    var b = test.findItem(plugin.activePane.activeBoard, earlier)
    if (!a || !b || a.parent !== b.parent) return false
    var kids = a.parent.children
    var at = -1, before = -1
    for (var i = 0; i < kids.length; i++) {
      if (kids[i] === a) at = i
      if (kids[i] === b) before = i
    }
    return at >= 0 && before >= 0 && at > before
  }
  Host.PluginShellApi {
    id: facade
    pluginId: "thepixelgardener.omarchyform"
    _hide: function(id) { test.check(id === pluginId, "own-id lifecycle"); test.hides++; plugin.close(); return true }
  }
  Omarchyform { id: plugin; shell: facade; manifest: ({id: facade.pluginId}) }
  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      test.ticks++
      test.check(test.ticks < 400, "runtime test completes (stage " + test.stage + ")")
      if (test.stage === 0 && plugin.activePane.boardLoaded) {
        test.check(plugin.theme.fontBody === Style.font.body, "body font uses Style")
        test.check(plugin.theme.canvasBackground === Commons.Color.background,
                   "background uses Color (" + plugin.theme.canvasBackground + " vs " + Commons.Color.background
                   + ")")
        plugin.windowMode = true
        plugin.open("{}")
        test.stage = 1
      } else if (test.stage === 1 && plugin.activePane.activeBoard) {
        test.check(plugin.activePane.activeBoard.width > 0, "window surface mounted")
        plugin.activePane.addRelative("note")
        plugin.activePane.items.setProperty(0, "itext", "Omarchy compatibility test")
        plugin.activePane.stopEditing()
        plugin.activePane.addItem("ellipse", 420, 200)
        plugin.activePane.addLink(1, 2)
        test.check(plugin.activePane.items.count === 2 && plugin.activePane.links.count === 1, "items and connector")
        plugin.activePane.undo()
        test.check(plugin.activePane.links.count === 0, "undo connector")
        plugin.activePane.redo()
        test.check(plugin.activePane.links.count === 1, "redo connector")
        plugin.activePane.selectOnly(0)
        plugin.activePane.nudgeSelected(1, 0)
        plugin.activePane.recolorItem()
        plugin.activePane.fitToItems()
        plugin.activePane.openBrowser()
        test.stage = 2
      } else if (test.stage === 2 && plugin.library.showing) {
        plugin.library.key({key: Qt.Key_Slash, text: "/", modifiers: 0})
        test.check(plugin.library.searching, "browser search starts")
        plugin.library.key({key: Qt.Key_Escape, text: "", modifiers: 0})
        test.check(!plugin.library.searching, "browser search escapes")
        plugin.library.hide()
        plugin.activePane.editSelected()
        plugin.activePane.items.setProperty(0, "itext", "hide flushes pending typing")
        plugin.activePane.scheduleSave()
        plugin.activePane.helpVisible = true
        plugin.close()
        test.check(!plugin.opened, "host close hides plugin")
        test.check(plugin.activePane.editIndex === -1 && !plugin.activePane.helpVisible, "host close clears transient modes")
        test.stage = 3
      } else if (test.stage === 3 && !plugin.activePane.activeBoard) {
        plugin.open("{}")
        test.stage = 4
      } else if (test.stage === 4 && plugin.activePane.activeBoard) {
        test.check(plugin.activePane.items.count === 2, "reopen preserves document")
        test.stage = 41
        test.switchedAt = test.ticks
      } else if (test.stage === 41 && test.ticks > test.switchedAt + 5) {
        test.key("n")
        test.stage = 42
      } else if (test.stage === 42 && plugin.activePane.items.count === 3 && plugin.activePane.editIndex === 2) {
        test.key("a")
        test.stage = 43
      } else if (test.stage === 43 && plugin.activePane.items.get(2).itext === "a") {
        var note = test.findItem(plugin.activePane.activeBoard, "board-item-" + plugin.activePane.items.get(2).iid)
        var editor = test.findItem(note, "note-editor")
        editor.selectAll()
        test.key("p", "CTRL")
        test.stage = 431
      } else if (test.stage === 431 && plugin.activePane.paletteVisible) {
        test.check(plugin.activePane.paletteScope === "typing", "Ctrl+P opens text commands")
        test.check(plugin.activePane.editIndex === 2, "formatting keeps editing active")
        plugin.activePane.setPaletteQuery("bold")
        test.switchedAt = test.ticks
        test.stage = 432
      } else if (test.stage === 432 && test.ticks > test.switchedAt + 3) {
        test.key("Return")
        test.stage = 433
      } else if (test.stage === 433 && !plugin.activePane.paletteVisible) {
        test.check(plugin.activePane.items.get(2).itext === "*a*", "format command uses the selected text")
        test.check(plugin.activePane.textEditor.activeFocus, "format command restores editor focus")
        test.key("p", "CTRL")
        test.stage = 434
      } else if (test.stage === 434 && plugin.activePane.paletteVisible) {
        test.key("Escape")
        test.stage = 435
      } else if (test.stage === 435 && !plugin.activePane.paletteVisible) {
        test.check(plugin.activePane.editIndex === 2 && plugin.activePane.textEditor.activeFocus, "Escape returns to typing")
        test.check(plugin.activePane.items.get(2).itext === "*a*", "cancel leaves text unchanged")
        test.key("Escape")
        test.stage = 44
      } else if (test.stage === 44 && plugin.activePane.editIndex === -1) {
        test.key("b")
        test.stage = 45
      } else if (test.stage === 45 && plugin.library.showing) {
        // A name is typed into a real text field now. Only a real key can say
        // whether the keyboard reaches it: the harness calls functions, and a
        // field nothing has focused looks exactly the same from there.
        plugin.library.ask("rename", "new name:", "already-here")
        test.stage = 451
      } else if (test.stage === 451 && plugin.library.promptLabel !== "") {
        test.key("z")
        test.stage = 452
      } else if (test.stage === 452 && plugin.library.input === "z") {
        test.check(true, "one keystroke replaces the name the field opens with")
        plugin.library.key({key: Qt.Key_Escape, text: "", modifiers: 0})
        test.check(plugin.library.promptLabel === "", "and the field lets go")
        // Which the browser behind it has to notice: this closes it, so the
        // keyboard came back rather than staying in a field that is gone.
        test.key("Escape")
        test.stage = 46
      } else if (test.stage === 46 && !plugin.library.showing) {
        plugin.activePane.selectOnly(2)
        plugin.activePane.removeItem(2)
        plugin.activePane.fitToItems()
        // `d` took whatever was under the cursor, one key away from s, c and e.
        // It is not a command any more, and the board has to ignore it rather
        // than fall through to something else.
        plugin.activePane.selectOnly(1)
        test.key("d")
        test.switchedAt = test.ticks
        test.stage = 465
      } else if (test.stage === 465 && test.ticks > test.switchedAt + 3) {
        test.check(plugin.activePane.items.count === 2, "d no longer deletes")
        test.key("F1")
        test.stage = 461
      } else if (test.stage === 461 && plugin.activePane.helpVisible) {
        // A key that deletes on the board, so the check still means something:
        // the help panel has to swallow it rather than let it through.
        test.key("Delete")
        test.switchedAt = test.ticks
        test.stage = 462
      } else if (test.stage === 462 && test.ticks > test.switchedAt + 3) {
        test.check(plugin.activePane.items.count === 2, "help keys cannot delete underlying notes")
        test.stage = 464
        test.check(plugin.activePane.activeBoard.grabToImage(function(result) {
          test.check(result.saveToFile(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/help.png"), "help capture")
          test.key("Escape")
          test.stage = 463
        }), "help capture scheduled")
      } else if (test.stage === 463 && !plugin.activePane.helpVisible) {
        test.stage = 40
        test.check(plugin.activePane.activeBoard.grabToImage(function(result) {
          test.check(result.saveToFile(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/window.png"), "window capture")
          // Mutate only the isolated shell singleton, not the user's theme.
          Commons.Color.foreground = "#00ff00"
          Commons.Color.accent = "#ff00ff"
          test.switchedAt = test.ticks
          test.stage = 47
        }), "window capture scheduled")
      } else if (test.stage === 47 && test.ticks > test.switchedAt + 5) {
        test.check(plugin.theme.foreground === Commons.Color.foreground, "theme binding updates")
        test.stage = 48
        test.check(plugin.activePane.activeBoard.grabToImage(function(result) {
          test.check(result.saveToFile(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/window-themed.png"), "theme capture")
          plugin.toggleWindowMode()
          test.switchedAt = test.ticks
          test.stage = 5
        }), "theme capture scheduled")
      } else if (test.stage === 5 && plugin.activePane.activeBoard && !plugin.windowMode && test.ticks > test.switchedAt + 5) {
        test.check(plugin.boardScreen !== null, "focused output selected")
        test.check(plugin.boardScreen.name === Hyprland.focusedMonitor.name, "overlay uses focused monitor")
        console.log("MONITOR: " + plugin.boardScreen.name + " " + plugin.boardScreen.width + "x" + plugin.boardScreen.height)
        test.check(plugin.activePane.activeBoard.width === plugin.boardScreen.width, "overlay fills focused output: " + plugin.activePane.activeBoard.width + " vs " + plugin.boardScreen.width)
        test.stage = 50
        test.check(plugin.activePane.activeBoard.grabToImage(function(result) {
          test.check(result.saveToFile(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/overlay.png"), "overlay capture")
          test.stage = 6
        }), "overlay capture scheduled")
      } else if (test.stage === 6) {
        // Which item is drawn over which, in the scene rather than in the
        // model: the two notes are put on top of each other, and the order
        // they are drawn in is the order their delegates sit in.
        plugin.activePane.items.setProperty(1, "ix", plugin.activePane.items.get(0).ix + 20)
        plugin.activePane.items.setProperty(1, "iy", plugin.activePane.items.get(0).iy + 20)
        plugin.activePane.selectOnly(0)
        test.check(test.drawnAfter("board-item-2", "board-item-1"), "the later item starts on top")
        test.expectWrite()
        plugin.activePane.layerTargets("front")
        test.stage = 610
      } else if (test.stage === 610 && test.wrote) {
        test.check(test.drawnAfter("board-item-1", "board-item-2"),
                   "bringing one forward draws it over the other")
        test.check(test.boardData(plugin.activePane.currentBoard).items[1].id === 1,
                   "and the file says so too, which is what reopening reads")
        test.expectWrite()
        plugin.activePane.undo()
        test.stage = 611
      } else if (test.stage === 611 && test.wrote) {
        test.check(test.drawnAfter("board-item-2", "board-item-1"), "undo puts the order back")
        test.stage = 612
      } else if (test.stage === 612) {
        // Pin an existing item after foreground items already exist.
        test.expectWrite()
        plugin.activePane.selectOnly(0)
        plugin.activePane.togglePin()
        test.stage = 613
      } else if (test.stage === 613 && test.wrote) {
        var pinned = test.findItem(plugin.activePane.activeBoard, "board-item-1")
        test.check(pinned && pinned.parent.objectName === "background-world", "pinned item renders in background")
        test.check(test.boardData(plugin.activePane.currentBoard).items[0].pinned, "pin saved to disk")
        plugin.activePane.markAll()
        test.check(plugin.activePane.markedIds.length === 1, "mark-all skips backgrounds")
        plugin.activePane.clearMarks()
        plugin.activePane.togglePinnedSelection()
        test.check(plugin.activePane.selectedIndex === 0, "background selection reaches pinned item")
        test.expectWrite()
        plugin.activePane.togglePin()
        test.stage = 614
      } else if (test.stage === 614 && test.wrote) {
        test.check(test.findItem(plugin.activePane.activeBoard, "board-item-1").parent.objectName === "foreground-world", "unpin restores foreground")
        plugin.activePane.openBrowser()
        test.stage = 615
      } else if (test.stage === 615 && !plugin.library.busy) {
        plugin.library.ask("folder", "new folder:", "test-folder")
        plugin.library.commitPrompt()
        test.stage = 7
      } else if (test.stage === 7 && !plugin.library.busy && test.pick("test-folder")) {
        plugin.library.enter()
        plugin.library.ask("board", "new board:", "scratch")
        plugin.library.commitPrompt()
        test.stage = 8
      } else if (test.stage === 8 && plugin.activePane.currentBoard === "test-folder/scratch.json" && plugin.activePane.boardLoaded) {
        plugin.activePane.addItem("note", 100, 100)
        test.stage = 9
      } else if (test.stage === 9 && test.boardData(plugin.activePane.currentBoard) && test.boardData(plugin.activePane.currentBoard).items.length === 1) {
        plugin.activePane.openBrowser()
        test.stage = 10
      } else if (test.stage === 10 && !plugin.library.busy && test.pick("test-folder/scratch.json")) {
        plugin.library.ask("rename", "rename to:", "renamed")
        plugin.library.commitPrompt()
        test.stage = 11
      } else if (test.stage === 11 && plugin.activePane.currentBoard === "test-folder/renamed.json") {
        test.check(plugin.activePane.items.count === 1, "rename preserves open model")
        plugin.library.up()
        test.stage = 12
      } else if (test.stage === 12 && !plugin.library.busy && test.pick("test-folder")) {
        plugin.library.deleteCurrent()
        test.check(plugin.library.pendingDelete === "", "open board's folder cannot be deleted")
        plugin.library.ask("rename", "rename to:", "moved-folder")
        plugin.library.commitPrompt()
        test.stage = 13
      } else if (test.stage === 13 && plugin.activePane.currentBoard === "moved-folder/renamed.json") {
        test.check(test.boardData(plugin.activePane.currentBoard).items.length === 1, "folder rename follows open board")
        plugin.activePane.openBoard("board.json")
        plugin.library.hide()
        test.stage = 14
      } else if (test.stage === 14 && plugin.activePane.currentBoard === "board.json" && plugin.activePane.boardLoaded) {
        test.check(plugin.activePane.items.count === 2, "original board survives browser operations")
        plugin.activePane.openBrowser()
        test.stage = 15
      } else if (test.stage === 15 && !plugin.library.busy && test.pick("moved-folder")) {
        plugin.library.deleteCurrent()
        test.check(plugin.library.pendingDelete === "moved-folder", "first delete arms confirmation")
        plugin.library.key({key: Qt.Key_J, text: "j", modifiers: 0})
        test.check(plugin.library.pendingDelete === "", "navigation cancels deletion")
        test.check(test.pick("moved-folder"), "folder still exists")
        plugin.library.deleteCurrent()
        plugin.library.deleteCurrent()
        test.stage = 16
      } else if (test.stage === 16 && !plugin.library.busy && !test.pick("moved-folder")) {
        plugin.library.toggleTrash()
        test.stage = 160
      } else if (test.stage === 160 && plugin.library.rows.length > 0 && !plugin.library.busy) {
        plugin.library.index = 0
        plugin.library.restoreCurrent()
        test.stage = 161
      } else if (test.stage === 161 && !plugin.library.busy && plugin.library.trashEntries.length === 0) {
        test.check(test.boardData("moved-folder/renamed.json").items.length === 1, "trash restore preserves board")
        plugin.library.toggleTrash()
        test.stage = 162
      } else if (test.stage === 162 && !plugin.library.busy && test.pick("moved-folder")) {
        plugin.library.deleteCurrent(); plugin.library.deleteCurrent()
        test.stage = 163
      } else if (test.stage === 163 && !plugin.library.busy && !test.pick("moved-folder")) {
        if (Quickshell.screens.length > 1) {
          var other = Quickshell.screens[0] === plugin.boardScreen ? Quickshell.screens[1] : Quickshell.screens[0]
          plugin.close()
          plugin.boardScreen = other
          plugin.opened = true
          test.switchedAt = test.ticks
          test.stage = 17
        } else test.stage = 18
      } else if (test.stage === 17 && plugin.activePane.activeBoard && test.ticks > test.switchedAt + 5) {
        test.check(plugin.activePane.activeBoard.width === plugin.boardScreen.width, "secondary output layout")
        console.log("MONITOR: " + plugin.boardScreen.name + " " + plugin.boardScreen.width + "x" + plugin.boardScreen.height)
        test.stage = 19
        test.check(plugin.activePane.activeBoard.grabToImage(function(result) {
          test.check(result.saveToFile(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/overlay-secondary.png"), "secondary capture")
          test.stage = 18
        }), "secondary capture scheduled")
      } else if (test.stage === 18) {
        plugin.toggleWindowMode()
        test.switchedAt = test.ticks
        test.stage = 20
      } else if (test.stage === 20 && plugin.activePane.activeBoard && plugin.windowMode && test.ticks > test.switchedAt + 5) {
        test.closedWindow = plugin.activePane.activeBoard.QsWindow.window
        test.closedWindow.visible = false
        test.stage = 21
      } else if (test.stage === 21 && !plugin.opened) {
        test.check(test.hides === 1, "window close notifies scoped facade")
        // The explicit assignment above simulates closing but removes the
        // visibility binding; restore it before testing a subsequent reopen.
        test.closedWindow.visible = Qt.binding(function() { return plugin.opened && plugin.windowMode })
        plugin.open("{}")
        test.stage = 22
      } else if (test.stage === 22 && plugin.activePane.activeBoard) {
        test.newStarted = Date.now()
        plugin.activePane.newBoard()
        test.stage = 23
      } else if (test.stage === 23 && plugin.activePane.currentBoard.indexOf("untitled") === 0 && plugin.activePane.boardLoaded && plugin.activePane.editIndex === 0) {
        console.log("NEW_BOARD_READY_MS: " + (Date.now()-test.newStarted) + " (50ms polling)")
        test.newPath = plugin.activePane.currentBoard
        test.check(plugin.activePane.items.count === 1, "new board starts with one focused note")
        test.key("a")
        test.stage = 24
      } else if (test.stage === 24 && plugin.activePane.items.get(0).itext === "a") {
        plugin.activePane.stopEditing()
        plugin.activePane.pasteText("Pasted thought\nSecond line")
        test.check(plugin.activePane.items.count === 2 && plugin.activePane.items.get(1).itext === "Pasted thought\nSecond line", "multiline paste creates one note")
        // From here to the PNG the board is a fixed shape, because the exported
        // frame is the board's own bounds and the paste above lands at the
        // centre of the *view*: on a wider window the notes end up further
        // apart and the frame grows, so anything measured over the whole frame
        // would be measuring the screen. Two notes in a row with a gap between
        // them, and the connector crossing the gap where nothing else draws.
        test.place(0, 0, 0, 240, 160)
        test.place(1, 400, 0, 300, 200)
        plugin.activePane.addLink(1, 2)
        test.check(plugin.activePane.links.count === 1, "connector for the exported picture")
        test.exchangeApi = test.findItem(plugin, "board-exchange")
        test.exchangeApi.exportJson(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/editable.json")
        test.stage = 25
      } else if (test.stage === 25 && !test.exchangeApi.busy) {
        test.check(test.exchangeApi.error === "", "editable export completes")
        test.exchangeApi.importPath(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/editable.json")
        test.stage = 26
      } else if (test.stage === 26 && plugin.activePane.currentBoard === "editable.json" && plugin.activePane.boardLoaded) {
        test.check(plugin.activePane.items.count === 2 && plugin.activePane.items.get(1).itext === "Pasted thought\nSecond line", "native import preserves contents")
        test.check(plugin.activePane.links.count === 1, "native import preserves connectors")
        plugin.activePane.exportPng(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/export.png")
        test.stage = 27
      } else if (test.stage === 27 && !plugin.activePane.imageBusy) {
        test.check(plugin.activePane.statusText.indexOf("PNG saved") === 0, "PNG export succeeds")
        test.check(plugin.activePane.statusText.indexOf("full board") > 0, "of the whole board: " + plugin.activePane.statusText)
        // The same board, framed around one marked item and drawn on white.
        // Both of the things an export can now be asked to vary, at once.
        plugin.activePane.markedIds = [plugin.activePane.items.get(0).iid]
        plugin.activePane.pngPalette = "light"
        plugin.activePane.exportPng(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/export-light.png")
        test.stage = 271
      } else if (test.stage === 271 && !plugin.activePane.imageBusy) {
        test.check(plugin.activePane.statusText.indexOf("what was marked") > 0,
                   "the line says what it framed: " + plugin.activePane.statusText)
        test.check(plugin.activePane.statusText.indexOf("on white") > 0,
                   "and what it drew it in: " + plugin.activePane.statusText)
        plugin.activePane.markedIds = []
        plugin.activePane.pngPalette = "theme"
        // The round trip that matters: a board bin/omarchyform wrote before
        // the shell started, opened by the shell itself. Reading it back with
        // the same loader proves the format; only this proves the board opens.
        plugin.activePane.openBoard("from-cli.json", false)
        test.stage = 28
      } else if (test.stage === 28 && plugin.activePane.currentBoard === "from-cli.json" && plugin.activePane.boardLoaded) {
        test.check(plugin.activePane.items.count === 2, "a board built from the command line opens")
        test.check(plugin.activePane.items.get(0).itext === "built headlessly", "with what was written into it")
        test.check(!plugin.activePane.damaged, "and is not treated as damaged")
        // A board from outside the library, opened by the path a file manager
        // would hand over. This is the whole of what the file type buys.
        plugin.open('{"action":"open","path":"'
          + Quickshell.env("OMARCHYFORM_TEST_DIR") + '/sent-to-me.omarchyform.json"}')
        test.stage = 29
      } else if (test.stage === 29 && plugin.activePane.currentBoard === "sent-to-me.json" && plugin.activePane.boardLoaded) {
        test.check(plugin.activePane.items.count === 1, "a board handed over by path opens")
        test.check(plugin.activePane.items.get(0).itext === "from somebody else", "with what was in it")
        // Split view, by the keys a person presses, in the window first and
        // then fullscreen: that the keyboard reaches the pane it should is
        // only something a real key can say.
        test.key("v")
        test.stage = 30
      } else if (test.stage === 30 && plugin.layout === "side-by-side") {
        test.check(plugin.activePane === plugin.panes[1], "v puts the keyboard in the new pane")
        test.check(plugin.panes[1].doc === plugin.panes[0].doc, "which shows the same board")
        test.switchedAt = test.ticks
        test.stage = 31
      } else if (test.stage === 31 && plugin.panes[1].activeBoard && test.ticks > test.switchedAt + 5) {
        var left = plugin.panes[0].activeBoard, right = plugin.panes[1].activeBoard
        test.check(plugin.squeezed || (left.visible && right.visible && right.x >= left.width),
                   "the two boards sit side by side: " + left.width + " and " + right.width + " at " + right.x)
        test.key("n")
        test.stage = 32
      } else if (test.stage === 32 && plugin.panes[1].editIndex === 1) {
        test.check(plugin.panes[0].items.count === 2, "a note made in one pane is on the board the other shows")
        test.check(plugin.panes[0].editIndex === -1, "and the other pane is not typing")
        test.key("h")
        test.stage = 33
      } else if (test.stage === 33 && plugin.panes[1].items.get(1).itext === "h") {
        test.key("i")
        test.stage = 34
      } else if (test.stage === 34 && plugin.panes[1].items.get(1).itext === "hi") {
        test.key("Escape")
        test.stage = 35
      } else if (test.stage === 35 && plugin.panes[1].editIndex === -1) {
        test.key("o")
        test.stage = 36
      } else if (test.stage === 36 && plugin.activePane === plugin.panes[0]) {
        test.check(plugin.panes[0].items.get(1).itext === "hi", "the other pane shows what was typed")
        test.key("v", "SHIFT")
        test.stage = 37
      } else if (test.stage === 37 && plugin.layout === "stacked") {
        test.check(plugin.activePane === plugin.panes[0], "turning the split keeps the keyboard where it was")
        test.key("w")
        test.switchedAt = test.ticks
        test.stage = 38
      } else if (test.stage === 38 && !plugin.windowMode && plugin.panes[0].activeBoard
                 && plugin.panes[1].activeBoard && test.ticks > test.switchedAt + 5) {
        test.check(plugin.layout === "stacked", "fullscreen keeps the split")
        var top = plugin.panes[0].activeBoard, bottom = plugin.panes[1].activeBoard
        test.check(plugin.squeezed || (top.visible && bottom.visible && bottom.y >= top.height),
                   "with one board over the other: " + top.height + " and " + bottom.height + " at " + bottom.y)
        test.check(plugin.activePane === plugin.panes[0] && top.activeFocus, "and the keyboard where it was")
        // Keys are sent to a window, and fullscreen is a layer rather than one,
        // so the rest is done back in the window — closed and opened again, the
        // way the stages before give a window the keyboard, which also asks
        // whether the split survives being closed.
        plugin.toggleWindowMode()
        plugin.close()
        test.stage = 381
      } else if (test.stage === 381 && !plugin.panes[0].activeBoard) {
        plugin.open("{}")
        test.switchedAt = test.ticks
        test.stage = 382
      } else if (test.stage === 382 && plugin.windowMode && plugin.panes[0].activeBoard
                 && plugin.panes[1].activeBoard && test.ticks > test.switchedAt + 5) {
        test.check(plugin.layout === "stacked" && plugin.documents.length === 1, "closing and opening keeps the split")
        test.key("o")
        test.stage = 39
      } else if (test.stage === 39 && plugin.activePane === plugin.panes[1]) {
        test.key("b")
        test.stage = 391
      } else if (test.stage === 391 && plugin.library.showing && plugin.library.rows.length > 0) {
        test.check(plugin.panes[1].browsing && !plugin.panes[0].browsing, "the browser opens over the pane that asked")
        test.check(test.pick("from-cli.json"), "the board built from the command line is listed")
        test.key("Return")
        test.stage = 392
      } else if (test.stage === 392 && plugin.panes[1].currentBoard === "from-cli.json" && plugin.panes[1].boardLoaded) {
        test.check(plugin.panes[0].currentBoard === "sent-to-me.json", "opening a board in one pane leaves the other alone")
        test.check(plugin.documents.length === 2, "two boards open")
        // A picture let go on the pane the keyboard is not in: it goes to that
        // pane's board, at that pane's point, through the real copy and the
        // real measuring, and the keyboard stays where it is.
        var other = plugin.panes[0]
        test.dropX = other.toWorldX(120)
        test.dropY = other.toWorldY(90)
        other.dropFiles(["file://" + Quickshell.env("OMARCHYFORM_TEST_DIR") + "/pixels.png"], test.dropX, test.dropY)
        test.stage = 3921
      } else if (test.stage === 3921 && plugin.panes[0].items.count === 3) {
        var placed = plugin.panes[0].items.get(2)
        test.check(placed.kind === "image" && placed.isrc !== "", "the dropped file is a picture on the pane it was dropped on")
        test.check(Math.abs(placed.ix + placed.iw / 2 - test.dropX) < 0.01
                   && Math.abs(placed.iy + placed.ih / 2 - test.dropY) < 0.01, "where it was let go of")
        var beside = plugin.panes[1].items
        for (var b = 0; b < beside.count; b++)
          test.check(beside.get(b).kind !== "image", "and nothing on the board the keyboard is in")
        test.check(plugin.activePane === plugin.panes[1], "which keeps the keyboard")
        test.key("v", "SHIFT")
        test.stage = 393
      } else if (test.stage === 393 && plugin.layout === "single") {
        test.check(plugin.panes[0].currentBoard === "from-cli.json", "closing keeps the pane the keyboard is in")
        test.check(plugin.documents.length === 1, "and closes the board only the other pane was showing")
        var kept = test.boardData("sent-to-me.json")
        test.check(kept !== null && kept.items.length === 3 && kept.items[1].text === "hi",
                   "after saving what was typed into it")
        test.check(kept.items[2].kind === "image", "and the picture dropped on it")
        console.log("OMARCHY_TESTS_PASSED")
        Qt.quit()
      }
    }
  }
}
