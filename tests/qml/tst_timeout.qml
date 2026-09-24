import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: test
  property string dir: Quickshell.env("OMARCHYFORM_TEST_DIR")
  property bool delayed: false
  property int completions: 0
  function check(value, message) {
    if (!value) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  FileView { id: reader; blockLoading: true; blockAllReads: true; printErrors: false }
  BoardPersistence {
    id: writer
    timeoutMs: 20
    onDelayed: {
      test.delayed = true
      test.check(writer.busy, "slow save retains ownership")
      test.check(!writer.save(test.dir + "/wrong.json", "wrong"), "retry rejected until completion")
    }
    onFailed: function(message) { test.check(false, message) }
    onCompleted: function(path, text) {
      test.check(path === test.dir + "/slow.json", "completion retains original destination")
      test.completions++
      if (test.completions === 1) {
        test.check(test.delayed, "watchdog exercised")
        test.check(text === "first", "slow save retains original contents")
        reader.path = path + ".bak"
        reader.reload(); reader.waitForJob()
        test.check(reader.text() === "previous", "backup completes before replacement")
        test.check(writer.save(path, "second"), "new write accepted after completion")
      } else {
        test.check(text === "second", "subsequent save succeeds")
        console.log("TIMEOUT_TESTS_PASSED")
        Qt.quit()
      }
    }
  }
  Process {
    id: feed
    command: ["sh", "-c", 'sleep 0.2; printf previous > "$1"', "feed", test.dir + "/slow.json"]
  }
  Component.onCompleted: {
    test.check(writer.save(dir + "/slow.json", "first"), "slow save starts")
    feed.running = true
  }
}
