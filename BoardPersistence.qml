import QtQuick
import Quickshell.Io

// One immutable save at a time. This writer is independent of the file being
// browsed, so a late completion cannot write into a different board.
Item {
  id: persistence
  property bool busy: false
  property string target: ""
  property string contents: ""
  signal completed(string path, string text)
  signal failed(string message)

  // backupPath is optional: without one the previous version is kept beside
  // the board, which is what a caller testing this component in isolation
  // expects. The app passes a path outside the boards tree, so a directory
  // people are invited to hand-edit and commit stays free of .bak files.
  property string backupTarget: ""

  function save(path, text, backupPath) {
    if (busy) return false
    target = path
    contents = text
    backupTarget = backupPath ? backupPath : path + ".bak"
    busy = true
    backup.running = true
    return true
  }

  // A save that never reports back leaves busy stuck, and with it every later
  // save, board switch and the "saving…" line. Nothing should be able to wedge
  // the board that way, whatever the cause.
  Timer {
    id: watchdog
    interval: 8000
    repeat: false
    running: persistence.busy
    onTriggered: if (persistence.busy) persistence.fail("Save did not finish")
  }

  function fail(message) {
    busy = false
    failed(message)
  }

  Process {
    id: backup
    // Arguments are passed separately: filenames never become shell code.
    // Publish the backup atomically; a failed copy leaves the old backup intact.
    command: ["sh", "-c",
      'if [ -e "$1" ] || [ -L "$1" ]; then cp -T -- "$1" "$2.tmp" && mv -fT -- "$2.tmp" "$2"; fi',
      "omarchyform-backup", persistence.target, persistence.backupTarget]
    onExited: function(code) {
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
