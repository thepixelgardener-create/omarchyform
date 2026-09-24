import QtQuick
import Quickshell.Io

// One immutable save at a time. This writer is independent of the file being
// browsed, so a late completion cannot write into a different board.
Item {
  id: persistence
  property bool busy: false
  property string target: ""
  property string contents: ""
  property string boardRoot: ""
  property string backupRoot: ""
  property int timeoutMs: 8000
  signal delayed(string message)
  signal completed(string path, string text)
  signal failed(string message)

  // backupPath is optional: without one the previous version is kept beside
  // the board, which is what a caller testing this component in isolation
  // expects. The app passes a path outside the boards tree, so a directory
  // people are invited to hand-edit and commit stays free of .bak files.
  property string backupTarget: ""

  function save(path, text, backupPath, allowedRoot, allowedBackupRoot) {
    if (busy) return false
    boardRoot = allowedRoot || ""
    backupRoot = allowedBackupRoot || ""
    target = path
    contents = text
    backupTarget = backupPath ? backupPath : path + ".bak"
    busy = true
    backup.running = true
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
    id: backup
    // Arguments are passed separately: filenames never become shell code.
    // Publish the backup atomically; a failed copy leaves the old backup intact.
    command: ["bash", decodeURIComponent(Qt.resolvedUrl("BoardFiles.sh").toString().replace(/^file:\/\//, "")),
      "backup", persistence.target, persistence.backupTarget, persistence.boardRoot, persistence.backupRoot]
    onExited: function(code) {
      if (code === 3) { persistence.fail("Board path goes through a symlink; not saved"); return }
      if (code !== 0) { persistence.fail("Backup failed; board was not replaced"); return }
      writer.path = persistence.target
      writer.setText(persistence.contents)
    }
  }

  FileView {
    id: writer
    preload: false
    atomicWrites: true
    printErrors: false
    onSaved: {
      persistence.busy = false
      persistence.completed(persistence.target, persistence.contents)
    }
    onSaveFailed: function(error) {
      persistence.fail("Save failed: " + FileViewError.toString(error))
    }
  }
}
