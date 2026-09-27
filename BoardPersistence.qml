import QtQuick
import Quickshell.Io

// One coordinated write at a time. This writer is independent of the file
// being browsed, so a late completion cannot write into a different board —
// and it never replaces a file that has moved since the caller last read it.
Item {
  id: persistence
  property bool busy: false
  property string target: ""
  property string contents: ""
  property string boardRoot: ""
  property string backupRoot: ""
  property string lockPath: ""
  // What the caller believes is on disk. "-" means "whatever is there", which
  // is what an explicit overwrite asks for after someone has been told.
  property string expected: "-"
  property int timeoutMs: 8000
  signal delayed(string message)
  signal completed(string path, string text, string revision)
  signal failed(string message)
  // The file moved underneath this write. Nothing was written, the caller
  // still holds what it meant to write, and the revision that is there now
  // comes back with it.
  signal stale(string path, string revision)

  // backupPath is optional: without one the previous version is kept beside
  // the board, which is what a caller testing this component in isolation
  // expects. The app passes a path outside the boards tree, so a directory
  // people are invited to hand-edit and commit stays free of .bak files.
  property string backupTarget: ""

  function save(path, text, backupPath, allowedRoot, allowedBackupRoot, lock, expectedRevision) {
    if (busy) return false
    boardRoot = allowedRoot || ""
    backupRoot = allowedBackupRoot || ""
    target = path
    contents = text
    backupTarget = backupPath ? backupPath : path + ".bak"
    lockPath = lock ? lock : path + ".lock"
    expected = expectedRevision === undefined || expectedRevision === null ? "-" : expectedRevision
    busy = true
    // The board goes down the pipe rather than through a file of our own: one
    // process does the whole write, and there is no half-written file to leave
    // behind if this one is interrupted.
    commit.stdinEnabled = true
    commit.running = true
    return true
  }

  // A slow operation still owns its immutable arguments. Report the delay,
  // but never permit a retry or board switch to reuse an active writer.
  Timer {
    interval: persistence.timeoutMs
    repeat: false
    running: persistence.busy
    onTriggered: if (persistence.busy) persistence.delayed("Saving is taking longer than expected; waiting for disk")
  }

  function fail(message) {
    busy = false
    failed(message)
  }

  Process {
    id: commit
    // Arguments are passed separately: filenames never become shell code.
    // The helper takes the lock, checks the revision, keeps the version it is
    // about to replace, and renames the staged file into place.
    command: ["bash", decodeURIComponent(Qt.resolvedUrl("BoardFiles.sh").toString().replace(/^file:\/\//, "")),
      "commit", persistence.target, persistence.backupTarget,
      persistence.lockPath, persistence.expected, persistence.boardRoot, persistence.backupRoot]
    stdinEnabled: true
    stdout: StdioCollector { id: committed; waitForEnd: true }
    // Written once the pipe is actually there, and closed straight after, or
    // the helper waits for an end of file that never comes.
    onStarted: {
      commit.write(persistence.contents)
      commit.stdinEnabled = false
    }
    onExited: function(code) {
      if (code === 7) {
        persistence.busy = false
        persistence.stale(persistence.target, committed.text)
        return
      }
      if (code === 3) { persistence.fail("Board path goes through a symlink; not saved"); return }
      if (code !== 0) { persistence.fail("Could not replace the board; the version on disk is untouched"); return }
      persistence.busy = false
      persistence.completed(persistence.target, persistence.contents, committed.text)
    }
  }
}
