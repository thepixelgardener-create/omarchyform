import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: test
  property string dir: Quickshell.env("OMARCHYFORM_TEST_DIR")
  property int failures: 0
  function check(value, message) {
    if (!value) { console.error("FAIL: " + message); Qt.exit(1); throw new Error(message) }
  }
  BoardPersistence {
    id: writer
    timeoutMs: 100
    onFailed: function(message) {
      test.failures++
      test.check(!writer.busy, "failed launch releases writer")
      test.check(message.indexOf("Python 3") >= 0, "missing dependency is explained")
      if (test.failures === 1) {
        test.check(writer.save(test.dir + "/board.json", "retry without dependency"), "retry accepted")
      } else if (test.failures === 2) {
        repair.running = true
      } else test.check(false, "only two failed launches")
    }
    onCompleted: function(path, contents) {
      test.check(test.failures === 2, "failed starts complete exactly once")
      test.check(contents === "after repair", "successful retry retains its request")
      reader.path = path
      reader.reload(); reader.waitForJob()
      test.check(reader.text() === contents, "retry writes its content")
      console.log("PROCESSFAILURE_TESTS_PASSED")
      Qt.quit()
    }
  }
  FileView { id: reader; blockLoading: true; blockAllReads: true; printErrors: false }
  Process {
    id: repair
    command: ["/bin/ln", "-s", "/usr/bin/python3", test.dir + "/stubs/python3"]
    onExited: function(code) {
      test.check(code === 0, "repair fixture")
      test.check(writer.save(test.dir + "/board.json", "after repair"), "retry after repair accepted")
    }
  }
  Component.onCompleted: test.check(writer.save(test.dir + "/board.json", "not saved"), "first request accepted")
  Timer { running: true; interval: 5000; onTriggered: test.check(false, "failed launch or recovery hung") }
}
