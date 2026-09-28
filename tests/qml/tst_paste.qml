import QtQuick
import Quickshell
import Quickshell.Io

// Exercise the real Image status handler on a mounted board. The runner stubs
// only wl-paste, so the user's clipboard and board library stay untouched.
ShellRoot {
  id: test
  property int stage: 0
  property int ticks: 0
  property int closedAt: 0
  function check(ok, message) {
    if (!ok) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  Omarchyform { id: plugin }
  FileView { id: disk; blockLoading: true; blockAllReads: true }
  FileView { id: marker; blockLoading: true; blockAllReads: true; atomicWrites: false }
  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      test.check(++test.ticks < 450, "paste completed at stage " + test.stage)
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

        // And what the board does when the clipboard does not answer. The stub
        // refuses while this marker exists, so the failure arrives the way a
        // real one does — a non-zero exit from a subprocess, some time after
        // the keystroke that asked for it.
        marker.path = Quickshell.env("OMARCHYFORM_TEST_DIR") + "/no-clipboard"
        marker.setText("x")
        marker.waitForJob()
        plugin.statusText = ""
        plugin.pasteClipboard()
        test.stage = 5
      } else if (test.stage === 5 && plugin.failureText !== "") {
        test.check(plugin.failureKind === "clipboard",
                   "a clipboard that will not answer is a clipboard failure: " + plugin.failureKind)
        test.check(plugin.items.count === 2, "and nothing was added")
        // It is a failure, not an acknowledgement: it does not go on the line
        // that fades, and a gesture started afterwards does not take it down.
        test.check(plugin.statusText === "", "it did not arrive as a flash")
        plugin.selectOnly(0)
        plugin.toggleLinking()
        test.check(plugin.failureText !== "", "starting a connector leaves it alone")
        plugin.back()
        // Only the same operation working says it recovered.
        plugin.flash("PNG saved · full board, without controls", "png")
        test.check(plugin.failureText !== "", "another operation working says nothing about it")
        plugin.close()
        test.closedAt = test.ticks
        test.stage = 6
      } else if (test.stage === 6 && test.ticks - test.closedAt > 140) {
        test.check(!plugin.opened, "board stayed closed for seven seconds")
        test.check(plugin.failureText !== "", "closed board did not expire the failure")
        plugin.open("{}")
        test.stage = 7
      } else if (test.stage === 7 && plugin.activeBoard) {
        test.check(plugin.failureVisible, "reopening shows the retained failure")
        plugin.flash("Copied", "clipboard")
        test.check(plugin.failureText === "", "the clipboard answering does")
        console.log("OMARCHY_TESTS_PASSED")
        Qt.quit()
      }
    }
  }
}
