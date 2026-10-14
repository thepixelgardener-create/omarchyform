import QtQuick
import Quickshell
import Quickshell.Io
import "../.."

Scope {
  id: test
  property string dir: Quickshell.env("OMARCHYFORM_TEST_DIR")
  property var cases: ["many", "repeated", "one-over", "boundary", "recovery", "metadata", "after-metadata", "malformed", "nested", "absent-src"]
  property int at: 0
  property bool started: false
  property bool failed: false
  property string published: ""
  property string message: ""
  function check(ok, message) {
    if (!ok) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  FileView { id: reader; blockLoading: true; blockAllReads: true; printErrors: false }
  function read(path) { reader.path = ""; reader.path = path; reader.reload(); reader.waitForJob(); return reader.text() }
  QtObject {
    id: ctl
    readonly property string dataDir: test.dir + "/data"
    readonly property string imagesDir: dataDir + "/images"
    readonly property string boardsDir: dataDir + "/boards"
    function fileCommand(op, args) { return ["bash", test.dir + "/BoardFiles.sh", op].concat(args) }
  }
  BoardExchange {
    id: exchange
    ctl: ctl
    onCreated: function(path, first) { test.published = path }
    onFailed: function(message, kind) {
      test.check(exchange.busy, "failure delivered before releasing owner")
      test.check(kind === "board", "refusal identifies the operation")
      test.failed = true
      test.message = message
    }
  }
  Timer {
    interval: 10
    running: true
    repeat: true
    onTriggered: {
      if (!test.started) {
        test.started = true
        exchange.importPath(test.dir + "/" + test.cases[test.at] + ".omarchyform.json")
      } else if (!exchange.busy) {
        var name = test.cases[test.at]
        if (test.at < 3 || name === "metadata" || name === "malformed") {
          test.check(test.failed, name + " must fail before publication")
          var expected = name === "metadata" ? "32 MiB" : name === "malformed" ? "invalid fields" : "40 megapixels in total"
          test.check(test.message.indexOf(expected) >= 0, test.message)
          test.check(test.published === "", "no created signal for " + name)
          test.check(test.read(ctl.boardsDir + "/" + name + ".json") === "", "no saved board for " + name)
        } else {
          test.check(!test.failed && test.published === name + ".json", name + " must import")
          test.check(test.read(ctl.boardsDir + "/" + test.published) !== "", "saved board after successful check")
          if (name === "nested") {
            var normalized = test.read(ctl.boardsDir + "/" + test.published)
            test.check(normalized.length < 200 && normalized.indexOf("kept") >= 0, "foreign trees are stripped, while the note survives")
          }
        }
        test.check(test.read(test.dir + "/" + name + ".omarchyform.json") !== "", "source preserved")
        test.at++
        if (test.at === test.cases.length) { console.log("IMAGEBUDGET_TESTS_PASSED"); Qt.quit(); return }
        test.started = false; test.failed = false; test.published = ""; test.message = ""
      }
    }
  }
}
