import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io

// Real surfaces, state writes and reopenings, in the live runner's private home.
ShellRoot {
  id: test
  property int stage: -2
  property int ticks: 0
  function check(ok, message) {
    if (!ok) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  function openWith(windowed) {
    plugin.open(JSON.stringify({ settings: { startWindowed: windowed } }))
  }
  function surface(windowed) {
    test.check(plugin.opened, "the board stays open at stage " + test.stage)
    test.check(plugin.windowMode === windowed, "the requested mode is shown at stage " + test.stage)
    test.check(plugin.activePane.activeBoard.Window.window.visible, "the surface is visible")
  }
  function saved(windowed, preference) {
    disk.reload()
    disk.waitForJob()
    // The writer is asynchronous: wait for the expected contents, rather
    // than assuming one timer tick was long enough for the write to finish.
    var state = null
    try { state = JSON.parse(disk.text()) } catch (e) { return "" }
    return state && state.windowMode === windowed && state.startWindowed === preference ? disk.text() : ""
  }
  Omarchyform { id: plugin }
  FileView { id: disk; path: plugin.statePath; blockLoading: true; blockAllReads: true; printErrors: false }
  Image { id: exported; visible: false; cache: false }
  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      test.check(++test.ticks < 100, "window mode test completes at stage " + test.stage)
      if (test.stage === -2 && plugin.activePane.boardLoaded) {
        // A fresh keyboard launch has neither saved state nor bar settings.
        plugin.open("{}")
        test.stage = -1
      } else if (test.stage === -1 && plugin.activePane.activeBoard) {
        test.surface(true)
        plugin.close()
        test.stage = 0
      } else if (test.stage === 0 && !plugin.activePane.activeBoard) {
        test.openWith(false)
        test.stage = 1
      } else if (test.stage === 1 && plugin.activePane.activeBoard) {
        test.surface(false)
        if (!test.saved(false, false)) return
        plugin.close()
        test.stage = 2
      } else if (test.stage === 2 && !plugin.activePane.activeBoard) {
        // Issue #57: a previous fullscreen open must not override the changed setting.
        test.openWith(true)
        test.stage = 3
      } else if (test.stage === 3 && plugin.activePane.activeBoard) {
        test.surface(true)
        if (!test.saved(true, true)) return
        plugin.close()
        test.stage = 4
      } else if (test.stage === 4 && !plugin.activePane.activeBoard) {
        test.openWith(true)
        test.stage = 5
      } else if (test.stage === 5 && plugin.activePane.activeBoard) {
        test.surface(true)
        // The same action the board's W key dispatches, through the real pane.
        plugin.activePane.toggleWindowMode()
        test.stage = 6
      } else if (test.stage === 6 && plugin.activePane.activeBoard) {
        test.surface(false)
        if (!test.saved(false, true)) return
        plugin.close()
        test.stage = 7
      } else if (test.stage === 7 && !plugin.activePane.activeBoard) {
        test.openWith(true)
        test.stage = 8
      } else if (test.stage === 8 && plugin.activePane.activeBoard) {
        test.surface(false)
        plugin.activePane.toggleWindowMode()
        test.stage = 9
      } else if (test.stage === 9 && plugin.activePane.activeBoard) {
        test.surface(true)
        if (!test.saved(true, true)) return
        // Changing the preference while already visible exercises synchronous bindings.
        test.openWith(false)
        test.stage = 10
      } else if (test.stage === 10 && plugin.activePane.activeBoard) {
        test.surface(false)
        var state = test.saved(false, false)
        if (!state) return
        plugin.close()
        plugin.applyState(state)
        test.stage = 11
      } else if (test.stage === 11 && !plugin.activePane.activeBoard) {
        plugin.open("{}")
        test.stage = 12
      } else if (test.stage === 12 && plugin.activePane.activeBoard) {
        test.surface(false)
        if (!test.saved(false, false)) return
        plugin.activePane.addItem("note", 0, 0, { text: "export survives a mode request" })
        plugin.activePane.exportPng(Quickshell.env("OMARCHYFORM_TEST_DIR") + "/mode-export.png")
        test.check(plugin.imageBusy, "export started before the surface changes")
        plugin.activePane.toggleWindowMode()
        test.check(!plugin.windowMode, "W keeps the exporting surface alive")
        test.openWith(true)
        test.check(!plugin.windowMode, "bar settings keep the exporting surface alive")
        test.stage = 13
      } else if (test.stage === 13 && !plugin.imageBusy) {
        exported.source = "file://" + Quickshell.env("OMARCHYFORM_TEST_DIR") + "/mode-export.png"
        if (exported.status !== Image.Ready) return
        test.check(plugin.activePane.canEdit, "editing resumes after the export completes")
        test.check(exported.sourceSize.width > 0, "the PNG was published")
        test.openWith(true)
        test.stage = 14
      } else if (test.stage === 14 && plugin.activePane.activeBoard) {
        test.surface(true)
        plugin.close()
        console.log("OMARCHY_TESTS_PASSED")
        Qt.quit()
      }
    }
  }
}
