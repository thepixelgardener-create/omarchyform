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

  function save(path, text) {
    if (busy) return false
    target = path
    contents = text
    busy = true
    backup.running = true
    return true
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
      'if [ -e "$1" ] || [ -L "$1" ]; then cp -T -- "$1" "$1.bak.tmp" && mv -fT -- "$1.bak.tmp" "$1.bak"; fi',
      "omarchyform-backup", persistence.target]
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
