import QtQuick
import Quickshell
import Quickshell.Io
import "../.."

ShellRoot {
  id: test
  property string dir: Quickshell.env("OMARCHYFORM_TEST_DIR")
  property int round: 0
  property string secret: "private-note-秘密 🔒"
  property var samples: [secret + "\n'quoted' $HOME\n\n", "--help", secret.repeat(20000)]
  property string expected: ""
  function check(ok, message) {
    if (!ok) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }
  function read(name) {
    reader.path = ""; reader.path = test.dir + "/" + name
    reader.reload(); reader.waitForJob(); return reader.text()
  }
  FileView { id: reader; blockLoading: true; blockAllReads: true; printErrors: false }
  FileView { id: failure; path: test.dir + "/fail-copy"; printErrors: false }
  Item {
    id: ctl
    property alias items: items
    ListModel { id: items }
    function fileCommand(action, args) {
      if (action === "clipcopy") test.check(args.length === 0, "helper argv contains no note text")
      return ["bash", test.dir + "/BoardFiles.sh", action].concat(args)
    }
  }
  function next() {
    items.clear()
    expected = samples[round % samples.length]
    items.append({kind: "note", itext: expected})
    // The first copy also exercises multiple selected notes.
    if (round === 0) {
      items.append({kind: "note", itext: "second note"})
      expected += "\n\nsecond note"
    }
    exchange.copyItems(round === 0 ? [1, 0] : [0])
    items.setProperty(0, "itext", "edited after copying")
  }
  BoardExchange {
    id: exchange
    ctl: ctl
    onFinished: function(message, kind) {
      test.check(test.round < 3, "clipboard failure must not report success")
      test.check(kind === "copy", "copy success feedback")
      test.check(test.read("copied") === test.expected, "exact clipboard bytes including Unicode and trailing newlines")
      test.check(test.read("copy-argc") === "0", "wl-copy has no text arguments")
      test.check(test.read("copy-argv").indexOf(test.secret) === -1, "process metadata excludes private text")
      test.round++
      if (test.round === 3) failure.setText("fail")
      else Qt.callLater(test.next)
    }
    onFailed: function(message, kind) {
      test.check(test.round === 3 && kind === "copy", "clipboard failure feedback")
      console.log("CLIPBOARD_TESTS_PASSED")
      Qt.quit()
    }
  }
  Connections { target: failure; function onSaved() { test.next() } }
  Component.onCompleted: Qt.callLater(test.next)
}
