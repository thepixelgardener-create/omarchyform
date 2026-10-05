import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
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
    target: plugin
    function onSavingChanged() {
      if (plugin.saving) test.writing = true
      else if (test.writing) { test.writing = false; test.wrote = true }
    }
  }
  property int ticks: 0
  property int hides: 0
  property int switchedAt: 0
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
    plugin.items.setProperty(index, "ix", x)
    plugin.items.setProperty(index, "iy", y)
    plugin.items.setProperty(index, "iw", w)
    plugin.items.setProperty(index, "ih", h)
  }

  // Painting order is the order the delegates sit in under their parent: the
  // last one is drawn over the ones before it. Nothing exposes that as a
  // property, so it is read off the scene.
  function drawnAfter(later, earlier) {
    var a = test.findItem(plugin.activeBoard, later)
    var b = test.findItem(plugin.activeBoard, earlier)
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
      if (test.stage === 0 && plugin.boardLoaded) {
        test.check(plugin.theme.fontBody === Style.font.body, "body font uses Style")
        test.check(plugin.theme.canvasBackground === Color.background, "background uses Color")
        plugin.windowMode = true
        plugin.open("{}")
        test.stage = 1
      } else if (test.stage === 1 && plugin.activeBoard) {
        test.check(plugin.activeBoard.width > 0, "window surface mounted")
        plugin.addRelative("note")
        plugin.items.setProperty(0, "itext", "Omarchy compatibility test")
        plugin.stopEditing()
        plugin.addItem("ellipse", 420, 200)
        plugin.addLink(1, 2)
        test.check(plugin.items.count === 2 && plugin.links.count === 1, "items and connector")
        plugin.undo()
        test.check(plugin.links.count === 0, "undo connector")
        plugin.redo()
        test.check(plugin.links.count === 1, "redo connector")
        plugin.selectOnly(0)
        plugin.nudgeSelected(1, 0)
        plugin.recolorItem()
        plugin.fitToItems()
        plugin.openBrowser()
        test.stage = 2
      } else if (test.stage === 2 && plugin.library.showing) {
        plugin.library.key({key: Qt.Key_Slash, text: "/", modifiers: 0})
        test.check(plugin.library.searching, "browser search starts")
        plugin.library.key({key: Qt.Key_Escape, text: "", modifiers: 0})
        test.check(!plugin.library.searching, "browser search escapes")
        plugin.library.hide()
        plugin.editSelected()
        plugin.items.setProperty(0, "itext", "hide flushes pending typing")
        plugin.scheduleSave()
        plugin.helpVisible = true
        plugin.close()
        test.check(!plugin.opened, "host close hides plugin")
        test.check(plugin.editIndex === -1 && !plugin.helpVisible, "host close clears transient modes")
        test.stage = 3
      } else if (test.stage === 3 && !plugin.activeBoard) {
        plugin.open("{}")
        test.stage = 4
      } else if (test.stage === 4 && plugin.activeBoard) {
        test.check(plugin.items.count === 2, "reopen preserves document")
        test.stage = 41
        test.switchedAt = test.ticks
      } else if (test.stage === 41 && test.ticks > test.switchedAt + 5) {
        test.key("n")
        test.stage = 42
      } else if (test.stage === 42 && plugin.items.count === 3 && plugin.editIndex === 2) {
        test.key("a")
        test.stage = 43
      } else if (test.stage === 43 && plugin.items.get(2).itext === "a") {
        var note = test.findItem(plugin.activeBoard, "board-item-" + plugin.items.get(2).iid)
        var editor = test.findItem(note, "note-editor")
        editor.selectAll()
        test.key("p", "CTRL")
        test.stage = 431
      } else if (test.stage === 431 && plugin.paletteVisible) {
        test.check(plugin.paletteScope === "typing", "Ctrl+P opens text commands")
        test.check(plugin.editIndex === 2, "formatting keeps editing active")
        plugin.setPaletteQuery("bold")
        test.switchedAt = test.ticks
        test.stage = 432
      } else if (test.stage === 432 && test.ticks > test.switchedAt + 3) {
        test.key("Return")
        test.stage = 433
      } else if (test.stage === 433 && !plugin.paletteVisible) {
        test.check(plugin.items.get(2).itext === "*a*", "format command uses the selected text")
        test.check(plugin.textEditor.activeFocus, "format command restores editor focus")
        test.key("p", "CTRL")
        test.stage = 434
      } else if (test.stage === 434 && plugin.paletteVisible) {
        test.key("Escape")
        test.stage = 435
      } else if (test.stage === 435 && !plugin.paletteVisible) {
        test.check(plugin.editIndex === 2 && plugin.textEditor.activeFocus, "Escape returns to typing")
        test.check(plugin.items.get(2).itext === "*a*", "cancel leaves text unchanged")
        test.key("Escape")
        test.stage = 44
      } else if (test.stage === 44 && plugin.editIndex === -1) {
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
        plugin.selectOnly(2)
        plugin.removeItem(2)
        plugin.fitToItems()
        // `d` took whatever was under the cursor, one key away from s, c and e.
        // It is not a command any more, and the board has to ignore it rather
        // than fall through to something else.
        plugin.selectOnly(1)
        test.key("d")
        test.switchedAt = test.ticks
        test.stage = 465
      } else if (test.stage === 465 && test.ticks > test.switchedAt + 3) {
        test.check(plugin.items.count === 2, "d no longer deletes")
        test.key("F1")
        test.stage = 461
      } else if (test.stage === 461 && plugin.helpVisible) {
        // A key that deletes on the board, so the check still means something:
        // the help panel has to swallow it rather than let it through.
        test.key("Delete")
        test.switchedAt = test.ticks
        test.stage = 462
      } else if (test.stage === 462 && test.ticks > test.switchedAt + 3) {
        test.check(plugin.items.count === 2, "help keys cannot delete underlying notes")
        test.stage = 464
        test.check(plugin.activeBoard.grabToImage(function(result) {
          test.check(result.saveToFile(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/help.png"), "help capture")
          test.key("Escape")
          test.stage = 463
        }), "help capture scheduled")
      } else if (test.stage === 463 && !plugin.helpVisible) {
        test.stage = 40
        test.check(plugin.activeBoard.grabToImage(function(result) {
          test.check(result.saveToFile(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/window.png"), "window capture")
          // Mutate only the isolated shell singleton, not the user's theme.
          Color.foreground = "#00ff00"
          Color.accent = "#ff00ff"
          test.switchedAt = test.ticks
          test.stage = 47
        }), "window capture scheduled")
      } else if (test.stage === 47 && test.ticks > test.switchedAt + 5) {
        test.check(plugin.theme.foreground === Color.foreground, "theme binding updates")
        test.stage = 48
        test.check(plugin.activeBoard.grabToImage(function(result) {
          test.check(result.saveToFile(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/window-themed.png"), "theme capture")
          plugin.toggleWindowMode()
          test.switchedAt = test.ticks
          test.stage = 5
        }), "theme capture scheduled")
      } else if (test.stage === 5 && plugin.activeBoard && !plugin.windowMode && test.ticks > test.switchedAt + 5) {
        test.check(plugin.boardScreen !== null, "focused output selected")
        test.check(plugin.boardScreen.name === Hyprland.focusedMonitor.name, "overlay uses focused monitor")
        console.log("MONITOR: " + plugin.boardScreen.name + " " + plugin.boardScreen.width + "x" + plugin.boardScreen.height)
        test.check(plugin.activeBoard.width === plugin.boardScreen.width, "overlay fills focused output: " + plugin.activeBoard.width + " vs " + plugin.boardScreen.width)
        test.stage = 50
        test.check(plugin.activeBoard.grabToImage(function(result) {
          test.check(result.saveToFile(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/overlay.png"), "overlay capture")
          test.stage = 6
        }), "overlay capture scheduled")
      } else if (test.stage === 6) {
        // Which item is drawn over which, in the scene rather than in the
        // model: the two notes are put on top of each other, and the order
        // they are drawn in is the order their delegates sit in.
        plugin.items.setProperty(1, "ix", plugin.items.get(0).ix + 20)
        plugin.items.setProperty(1, "iy", plugin.items.get(0).iy + 20)
        plugin.selectOnly(0)
        test.check(test.drawnAfter("board-item-2", "board-item-1"), "the later item starts on top")
        test.expectWrite()
        plugin.layerTargets("front")
        test.stage = 610
      } else if (test.stage === 610 && test.wrote) {
        test.check(test.drawnAfter("board-item-1", "board-item-2"),
                   "bringing one forward draws it over the other")
        test.check(test.boardData(plugin.currentBoard).items[1].id === 1,
                   "and the file says so too, which is what reopening reads")
        test.expectWrite()
        plugin.undo()
        test.stage = 611
      } else if (test.stage === 611 && test.wrote) {
        test.check(test.drawnAfter("board-item-2", "board-item-1"), "undo puts the order back")
        test.stage = 612
      } else if (test.stage === 612) {
        // Pin an existing item after foreground items already exist.
        test.expectWrite()
        plugin.selectOnly(0)
        plugin.togglePin()
        test.stage = 613
      } else if (test.stage === 613 && test.wrote) {
        var pinned = test.findItem(plugin.activeBoard, "board-item-1")
        test.check(pinned && pinned.parent.objectName === "background-world", "pinned item renders in background")
        test.check(test.boardData(plugin.currentBoard).items[0].pinned, "pin saved to disk")
        plugin.markAll()
        test.check(plugin.markedIds.length === 1, "mark-all skips backgrounds")
        plugin.clearMarks()
        plugin.togglePinnedSelection()
        test.check(plugin.selectedIndex === 0, "background selection reaches pinned item")
        test.expectWrite()
        plugin.togglePin()
        test.stage = 614
      } else if (test.stage === 614 && test.wrote) {
        test.check(test.findItem(plugin.activeBoard, "board-item-1").parent.objectName === "foreground-world", "unpin restores foreground")
        plugin.openBrowser()
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
      } else if (test.stage === 8 && plugin.currentBoard === "test-folder/scratch.json" && plugin.boardLoaded) {
        plugin.addItem("note", 100, 100)
        test.stage = 9
      } else if (test.stage === 9 && test.boardData(plugin.currentBoard) && test.boardData(plugin.currentBoard).items.length === 1) {
        plugin.openBrowser()
        test.stage = 10
      } else if (test.stage === 10 && !plugin.library.busy && test.pick("test-folder/scratch.json")) {
        plugin.library.ask("rename", "rename to:", "renamed")
        plugin.library.commitPrompt()
        test.stage = 11
      } else if (test.stage === 11 && plugin.currentBoard === "test-folder/renamed.json") {
        test.check(plugin.items.count === 1, "rename preserves open model")
        plugin.library.up()
        test.stage = 12
      } else if (test.stage === 12 && !plugin.library.busy && test.pick("test-folder")) {
        plugin.library.deleteCurrent()
        test.check(plugin.library.pendingDelete === "", "open board's folder cannot be deleted")
        plugin.library.ask("rename", "rename to:", "moved-folder")
        plugin.library.commitPrompt()
        test.stage = 13
      } else if (test.stage === 13 && plugin.currentBoard === "moved-folder/renamed.json") {
        test.check(test.boardData(plugin.currentBoard).items.length === 1, "folder rename follows open board")
        plugin.openBoard("board.json")
        plugin.library.hide()
        test.stage = 14
      } else if (test.stage === 14 && plugin.currentBoard === "board.json" && plugin.boardLoaded) {
        test.check(plugin.items.count === 2, "original board survives browser operations")
        plugin.openBrowser()
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
      } else if (test.stage === 17 && plugin.activeBoard && test.ticks > test.switchedAt + 5) {
        test.check(plugin.activeBoard.width === plugin.boardScreen.width, "secondary output layout")
        console.log("MONITOR: " + plugin.boardScreen.name + " " + plugin.boardScreen.width + "x" + plugin.boardScreen.height)
        test.stage = 19
        test.check(plugin.activeBoard.grabToImage(function(result) {
          test.check(result.saveToFile(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/overlay-secondary.png"), "secondary capture")
          test.stage = 18
        }), "secondary capture scheduled")
      } else if (test.stage === 18) {
        plugin.toggleWindowMode()
        test.switchedAt = test.ticks
        test.stage = 20
      } else if (test.stage === 20 && plugin.activeBoard && plugin.windowMode && test.ticks > test.switchedAt + 5) {
        test.closedWindow = plugin.activeBoard.QsWindow.window
        test.closedWindow.visible = false
        test.stage = 21
      } else if (test.stage === 21 && !plugin.opened) {
        test.check(test.hides === 1, "window close notifies scoped facade")
        // The explicit assignment above simulates closing but removes the
        // visibility binding; restore it before testing a subsequent reopen.
        test.closedWindow.visible = Qt.binding(function() { return plugin.opened && plugin.windowMode })
        plugin.open("{}")
        test.stage = 22
      } else if (test.stage === 22 && plugin.activeBoard) {
        test.newStarted = Date.now()
        plugin.newBoard()
        test.stage = 23
      } else if (test.stage === 23 && plugin.currentBoard.indexOf("untitled") === 0 && plugin.boardLoaded && plugin.editIndex === 0) {
        console.log("NEW_BOARD_READY_MS: " + (Date.now()-test.newStarted) + " (50ms polling)")
        test.newPath = plugin.currentBoard
        test.check(plugin.items.count === 1, "new board starts with one focused note")
        test.key("a")
        test.stage = 24
      } else if (test.stage === 24 && plugin.items.get(0).itext === "a") {
        plugin.stopEditing()
        plugin.pasteText("Pasted thought\nSecond line")
        test.check(plugin.items.count === 2 && plugin.items.get(1).itext === "Pasted thought\nSecond line", "multiline paste creates one note")
        // From here to the PNG the board is a fixed shape, because the exported
        // frame is the board's own bounds and the paste above lands at the
        // centre of the *view*: on a wider window the notes end up further
        // apart and the frame grows, so anything measured over the whole frame
        // would be measuring the screen. Two notes in a row with a gap between
        // them, and the connector crossing the gap where nothing else draws.
        test.place(0, 0, 0, 240, 160)
        test.place(1, 400, 0, 300, 200)
        plugin.addLink(1, 2)
        test.check(plugin.links.count === 1, "connector for the exported picture")
        test.exchangeApi = test.findItem(plugin, "board-exchange")
        test.exchangeApi.exportJson(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/editable.json")
        test.stage = 25
      } else if (test.stage === 25 && !test.exchangeApi.busy) {
        test.check(test.exchangeApi.error === "", "editable export completes")
        test.exchangeApi.importPath(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/editable.json")
        test.stage = 26
      } else if (test.stage === 26 && plugin.currentBoard === "editable.json" && plugin.boardLoaded) {
        test.check(plugin.items.count === 2 && plugin.items.get(1).itext === "Pasted thought\nSecond line", "native import preserves contents")
        test.check(plugin.links.count === 1, "native import preserves connectors")
        plugin.exportPng(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/export.png")
        test.stage = 27
      } else if (test.stage === 27 && !plugin.imageBusy) {
        test.check(plugin.statusText.indexOf("PNG saved") === 0, "PNG export succeeds")
        test.check(plugin.statusText.indexOf("full board") > 0, "of the whole board: " + plugin.statusText)
        // The same board, framed around one marked item and drawn on white.
        // Both of the things an export can now be asked to vary, at once.
        plugin.markedIds = [plugin.items.get(0).iid]
        plugin.pngPalette = "light"
        plugin.exportPng(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/export-light.png")
        test.stage = 271
      } else if (test.stage === 271 && !plugin.imageBusy) {
        test.check(plugin.statusText.indexOf("what was marked") > 0,
                   "the line says what it framed: " + plugin.statusText)
        test.check(plugin.statusText.indexOf("on white") > 0,
                   "and what it drew it in: " + plugin.statusText)
        plugin.markedIds = []
        plugin.pngPalette = "theme"
        // The round trip that matters: a board bin/omarchyform wrote before
        // the shell started, opened by the shell itself. Reading it back with
        // the same loader proves the format; only this proves the board opens.
        plugin.openBoard("from-cli.json", false)
        test.stage = 28
      } else if (test.stage === 28 && plugin.currentBoard === "from-cli.json" && plugin.boardLoaded) {
        test.check(plugin.items.count === 2, "a board built from the command line opens")
        test.check(plugin.items.get(0).itext === "built headlessly", "with what was written into it")
        test.check(!plugin.damaged, "and is not treated as damaged")
        // A board from outside the library, opened by the path a file manager
        // would hand over. This is the whole of what the file type buys.
        plugin.open('{"action":"open","path":"'
          + Quickshell.env("OMARCHYFORM_TEST_DIR") + '/sent-to-me.omarchyform.json"}')
        test.stage = 29
      } else if (test.stage === 29 && plugin.currentBoard === "sent-to-me.json" && plugin.boardLoaded) {
        test.check(plugin.items.count === 1, "a board handed over by path opens")
        test.check(plugin.items.get(0).itext === "from somebody else", "with what was in it")
        console.log("OMARCHY_TESTS_PASSED")
        Qt.quit()
      }
    }
  }
}
