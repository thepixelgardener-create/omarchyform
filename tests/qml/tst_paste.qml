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
  property double reportedAt: 0
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
      test.check(++test.ticks < 550, "paste completed at stage " + test.stage)
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
        test.check(plugin.failureKind === "paste",
                   "a clipboard with nothing to give is a failure to paste: " + plugin.failureKind)
        test.check(plugin.items.count === 2, "and nothing was added")
        // It is a failure, not an acknowledgement: it went to the line that
        // waits rather than the one that fades, and a gesture started
        // afterwards does not take it down.
        //
        // Asked about this message rather than about the whole line being
        // empty. A flash from something earlier can still be inside its two and
        // a half seconds, which has nothing to do with the claim and made this
        // fail about one run in five.
        test.check(plugin.statusText.indexOf(plugin.failureText) < 0,
                   "the failure did not also arrive as a flash: " + plugin.statusText)
        plugin.selectOnly(0)
        plugin.toggleLinking()
        test.check(plugin.failureText !== "", "starting a connector leaves it alone")
        plugin.back()
        // Only the same operation working says it recovered.
        plugin.flash("PNG saved · full board, without controls", "png")
        test.check(plugin.failureText !== "", "another operation working says nothing about it")
        plugin.close()
        plugin.report("Failure received while closed", "paste")
        test.closedAt = test.ticks
        test.stage = 6
      } else if (test.stage === 6 && test.ticks - test.closedAt > 140) {
        test.check(!plugin.opened, "board stayed closed for seven seconds")
        test.check(plugin.failureText === "Failure received while closed",
                   "reporting while closed did not start the expiry timer")
        plugin.open("{}")
        test.stage = 7
      } else if (test.stage === 7 && plugin.activeBoard) {
        test.check(plugin.failureVisible, "reopening shows the retained failure")
        // Copying out is its own operation: it cannot answer for pasting.
        plugin.flash("Copied", "copy")
        test.check(plugin.failureText !== "", "a copy working says nothing about a paste")
        plugin.flash("Text pasted · enter to edit", "paste")
        test.check(plugin.failureText === "", "the paste answering does")
        plugin.report("First visible failure", "paste")
        test.reportedAt = Date.now()
        test.stage = 8
      } else if (test.stage === 8 && Date.now() - test.reportedAt >= 5000) {
        plugin.report("Second visible failure", "png")
        test.reportedAt = Date.now()
        test.stage = 9
      } else if (test.stage === 9 && Date.now() - test.reportedAt >= 1500) {
        // The first message's six-second deadline has passed. A replacement
        // must still have its own time on screen, not the old timer's remainder.
        test.check(plugin.failureText === "Second visible failure",
                   "a replacement gets a fresh display interval")
        test.stage = 10
      } else if (test.stage === 10 && Date.now() - test.reportedAt >= 6500) {
        test.check(plugin.failureText === "", "the replacement eventually expires")
        console.log("OMARCHY_TESTS_PASSED")
        Qt.quit()
      }
    }
  }
}
