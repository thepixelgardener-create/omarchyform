import QtQuick
import Quickshell
import Quickshell.Io
import "../.."

ShellRoot {
  id: test
  property string dir: Quickshell.env("OMARCHYFORM_TEST_DIR")
  property string path: dir + "/board with ' quotes.json"
  property int stage: 0
  function check(condition, message) {
    if (!condition) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  function read(path) { reader.path = path; reader.reload(); reader.waitForJob(); return reader.text() }
  FileView { id: reader; blockLoading: true; blockAllReads: true; printErrors: false }
  BoardPersistence {
    id: writer
    onCompleted: function(path, text) {
      test.check(path === test.path, "immutable destination: stage " + test.stage + " got " + path + " contents " + text)
      test.check(test.read(path) === text, "saved contents")
      if (test.stage === 0) {
        test.stage = 1
        writer.save(test.path, "second")
      } else if (test.stage === 1) {
        test.check(test.read(path + ".bak") === "first", "previous version backed up")
        test.stage = 2
        writer.save(test.path, "third")
      } else if (test.stage === 2) {
        test.check(test.read(path + ".bak") === "second", "backup advances one version")
        test.stage = 3
        writer.save(test.path + "/child.json", "failed")
      } else if (test.stage === 5) {
        test.check(test.read(path + ".bak") === "third", "retry preserves old version")
        console.log("PERSISTENCE_TESTS_PASSED")
        Qt.quit()
      } else test.check(false, "unexpected successful write")
    }
    onFailed: function(message) {
      test.check(!writer.busy, "failure releases writer")
      if (test.stage === 3) {
        test.check(test.read(test.path) === "third", "failed write leaves board intact")
        test.stage = 4
        // A directory at the backup staging path must fail safely.
        writer.save(test.dir + "/blocked.json", "must not replace original")
      } else if (test.stage === 4) {
        test.check(test.read(test.dir + "/blocked.json") === "original", "backup failure preserves board")
        test.stage = 5
        writer.save(test.path, "retry")
      } else test.check(false, message)
    }
  }
  Component.onCompleted: {
    check(writer.save(path, "first"), "first save accepted")
    check(!writer.save(dir + "/wrong.json", "wrong"), "concurrent save rejected")
  }
}
