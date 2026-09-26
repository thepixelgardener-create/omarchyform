import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import "services" as Host

ShellRoot {
  id: test
  property int stage: 0
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
    for (var i = 0; i < plugin.browserRows.length; i++) {
      if (plugin.browserRows[i].path === path) { plugin.browserIndex = i; return true }
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
        test.check(plugin.fontBody === Style.font.body, "body font uses Style")
        test.check(plugin.canvasBackground === Color.background, "background uses Color")
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
      } else if (test.stage === 2 && plugin.browserVisible) {
        plugin.browserKey({key: Qt.Key_Slash, text: "/", modifiers: 0})
        test.check(plugin.browserSearching, "browser search starts")
        plugin.browserKey({key: Qt.Key_Escape, text: "", modifiers: 0})
        test.check(!plugin.browserSearching, "browser search escapes")
        plugin.closeBrowser()
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
        test.key("Escape")
        test.stage = 44
      } else if (test.stage === 44 && plugin.editIndex === -1) {
        test.key("b")
        test.stage = 45
      } else if (test.stage === 45 && plugin.browserVisible) {
        test.key("Escape")
        test.stage = 46
      } else if (test.stage === 46 && !plugin.browserVisible) {
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
        test.check(plugin.foreground === Color.foreground, "theme binding updates")
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
        // Pin an existing item after foreground items already exist.
        plugin.selectOnly(0)
        plugin.togglePin()
        test.stage = 60
      } else if (test.stage === 60 && !plugin.saving) {
        var pinned = test.findItem(plugin.activeBoard, "board-item-1")
        test.check(pinned && pinned.parent.objectName === "background-world", "pinned item renders in background")
        test.check(test.boardData(plugin.currentBoard).items[0].pinned, "pin saved to disk")
        plugin.markAll()
        test.check(plugin.markedIds.length === 1, "mark-all skips backgrounds")
        plugin.clearMarks()
        plugin.togglePinnedSelection()
        test.check(plugin.selectedIndex === 0, "background selection reaches pinned item")
        plugin.togglePin()
        test.stage = 61
      } else if (test.stage === 61 && !plugin.saving) {
        test.check(test.findItem(plugin.activeBoard, "board-item-1").parent.objectName === "foreground-world", "unpin restores foreground")
        plugin.openBrowser()
        test.stage = 62
      } else if (test.stage === 62 && !plugin.browserBusy) {
        plugin.prompt("folder", "new folder:", "test-folder")
        plugin.commitPrompt()
        test.stage = 7
      } else if (test.stage === 7 && !plugin.browserBusy && test.pick("test-folder")) {
        plugin.browserEnter()
        plugin.prompt("board", "new board:", "scratch")
        plugin.commitPrompt()
        test.stage = 8
      } else if (test.stage === 8 && plugin.currentBoard === "test-folder/scratch.json" && plugin.boardLoaded) {
        plugin.addItem("note", 100, 100)
        test.stage = 9
      } else if (test.stage === 9 && test.boardData(plugin.currentBoard) && test.boardData(plugin.currentBoard).items.length === 1) {
        plugin.openBrowser()
        test.stage = 10
      } else if (test.stage === 10 && !plugin.browserBusy && test.pick("test-folder/scratch.json")) {
        plugin.prompt("rename", "rename to:", "renamed")
        plugin.commitPrompt()
        test.stage = 11
      } else if (test.stage === 11 && plugin.currentBoard === "test-folder/renamed.json") {
        test.check(plugin.items.count === 1, "rename preserves open model")
        plugin.browserUp()
        test.stage = 12
      } else if (test.stage === 12 && !plugin.browserBusy && test.pick("test-folder")) {
        plugin.deleteCurrent()
        test.check(plugin.pendingDelete === "", "open board's folder cannot be deleted")
        plugin.prompt("rename", "rename to:", "moved-folder")
        plugin.commitPrompt()
        test.stage = 13
      } else if (test.stage === 13 && plugin.currentBoard === "moved-folder/renamed.json") {
        test.check(test.boardData(plugin.currentBoard).items.length === 1, "folder rename follows open board")
        plugin.openBoard("board.json")
        plugin.closeBrowser()
        test.stage = 14
      } else if (test.stage === 14 && plugin.currentBoard === "board.json" && plugin.boardLoaded) {
        test.check(plugin.items.count === 2, "original board survives browser operations")
        plugin.openBrowser()
        test.stage = 15
      } else if (test.stage === 15 && !plugin.browserBusy && test.pick("moved-folder")) {
        plugin.deleteCurrent()
        test.check(plugin.pendingDelete === "moved-folder", "first delete arms confirmation")
        plugin.browserKey({key: Qt.Key_J, text: "j", modifiers: 0})
        test.check(plugin.pendingDelete === "", "navigation cancels deletion")
        test.check(test.pick("moved-folder"), "folder still exists")
        plugin.deleteCurrent()
        plugin.deleteCurrent()
        test.stage = 16
      } else if (test.stage === 16 && !plugin.browserBusy && !test.pick("moved-folder")) {
        plugin.toggleTrash()
        test.stage = 160
      } else if (test.stage === 160 && plugin.browserRows.length > 0 && !plugin.browserBusy) {
        plugin.browserIndex = 0
        plugin.restoreCurrent()
        test.stage = 161
      } else if (test.stage === 161 && !plugin.browserBusy && plugin.trashEntries.length === 0) {
        test.check(test.boardData("moved-folder/renamed.json").items.length === 1, "trash restore preserves board")
        plugin.toggleTrash()
        test.stage = 162
      } else if (test.stage === 162 && !plugin.browserBusy && test.pick("moved-folder")) {
        plugin.deleteCurrent(); plugin.deleteCurrent()
        test.stage = 163
      } else if (test.stage === 163 && !plugin.browserBusy && !test.pick("moved-folder")) {
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
        test.exchangeApi = test.findItem(plugin, "board-exchange")
        test.exchangeApi.exportJson(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/editable.json")
        test.stage = 25
      } else if (test.stage === 25 && !test.exchangeApi.busy) {
        test.check(test.exchangeApi.error === "", "editable export completes")
        test.exchangeApi.importPath(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/editable.json")
        test.stage = 26
      } else if (test.stage === 26 && plugin.currentBoard === "editable.json" && plugin.boardLoaded) {
        test.check(plugin.items.count === 2 && plugin.items.get(1).itext === "Pasted thought\nSecond line", "native import preserves contents")
        plugin.exportPng(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/export.png")
        test.stage = 27
      } else if (test.stage === 27 && !plugin.imageBusy) {
        test.check(plugin.statusText.indexOf("PNG saved") === 0, "PNG export succeeds")
        console.log("OMARCHY_TESTS_PASSED")
        Qt.quit()
      }
    }
  }
}
