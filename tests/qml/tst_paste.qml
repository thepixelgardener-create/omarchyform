import QtQuick
import Quickshell
import Quickshell.Io

// Exercise the real Image status handler on a mounted board. The runner stubs
// only wl-paste, so the user's clipboard and board library stay untouched.
ShellRoot {
  id: test
  property int stage: 0
  property int ticks: 0
  function check(ok, message) {
    if (!ok) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  Omarchyform { id: plugin }
  FileView { id: disk; blockLoading: true; blockAllReads: true }
  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      test.check(++test.ticks < 200, "paste completed at stage " + test.stage)
      if (test.stage === 0 && plugin.boardLoaded) {
        plugin.windowMode = true
        plugin.open("{}")
        test.stage = 1
      } else if (test.stage === 1 && plugin.activeBoard) {
        plugin.pasteClipboard()
        test.stage = 2
      } else if (test.stage === 2 && plugin.items.count === 1) {
        test.check(plugin.items.get(0).kind === "image", "paste creates an image")
        test.check(plugin.imageQueue.length === 0, "image probe completes")
        test.check(plugin.items.get(0).iw === 60 && plugin.items.get(0).ih === 60,
                   "uses decoded dimensions with minimum size")
        plugin.pasteClipboard()
        test.stage = 3
      } else if (test.stage === 3 && plugin.items.count === 2) {
        test.check(plugin.items.get(0).isrc !== plugin.items.get(1).isrc, "repeat paste has its own file")
        plugin.undo()
        test.check(plugin.items.count === 1, "undo removes one paste")
        plugin.redo()
        test.check(plugin.items.count === 2, "redo restores paste")
        plugin.flushSave()
        test.stage = 4
      } else if (test.stage === 4 && plugin.boardState === "Saved locally") {
        disk.path = plugin.boardsDir + "/" + plugin.currentBoard
        disk.reload()
        disk.waitForJob()
        var saved = JSON.parse(disk.text())
        test.check(saved.items.length === 2 && saved.items[0].kind === "image", "pasted images persist")
        console.log("OMARCHY_TESTS_PASSED")
        Qt.quit()
      }
    }
  }
}
