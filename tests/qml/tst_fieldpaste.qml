import QtQuick
import Quickshell
import Quickshell.Io
import "../.."

// Pasting into a field being typed in, through the real exchange and the real
// clipboard helper, with `wl-paste` replaced by a stub that serves whatever
// the step asks for — including a clipboard owner that never stops sending.
// Qt's own paste would read that owner until the shell ran out of memory; the
// fields hand their paste keys to the exchange instead, and this is what the
// exchange does with them.
ShellRoot {
  id: test
  property string dir: Quickshell.env("OMARCHYFORM_TEST_DIR")
  property int step: -1
  function check(condition, message) {
    if (!condition) { console.error("FAIL: " + message); Qt.quit(); throw new Error(message) }
  }

  // What the stub serves for each step: its mode on the first line and the
  // text after it, in a file of the step's own. The stub reads the newest. A
  // file per step because a write that changes nothing is never reported saved.
  FileView { id: served; printErrors: false; atomicWrites: true }

  // A pane, as far as a paste needs one: the board it shows, where it says
  // what went wrong, and the note a canvas paste would make — which a paste
  // meant for a field must never turn into.
  component Pane: QtObject {
    property string currentBoard: "board.json"
    property bool canEdit: true
    property var reports: []
    property int notesMade: 0
    function report(message, kind) { reports = reports.concat([kind + ": " + message]) }
    function pasteText(text) { notesMade++ }
    function fileCommand(action, args) { return ["bash", test.dir + "/BoardFiles.sh", action].concat(args) }
  }
  Pane { id: asker }
  Pane { id: other }
  property var current: asker

  BoardExchange { id: exchange; ctl: test.current }

  // A note's editor and a line field, carrying what BoardExchange reads off
  // the real ones: whether they still take a paste, how long they may get,
  // and whether line breaks survive.
  TextEdit {
    id: note
    textFormat: TextEdit.PlainText
    property bool takesPaste: true
    readonly property int pasteLimit: 1048576
    readonly property bool pasteLines: true
  }
  TextInput {
    id: line
    maximumLength: 12
    property bool takesPaste: true
    readonly property int pasteLimit: line.maximumLength
    readonly property bool pasteLines: false
  }
  Component {
    id: doomed
    TextInput {
      property bool takesPaste: true
      readonly property int pasteLimit: 100
      readonly property bool pasteLines: false
    }
  }

  // Each step: how the stub answers, what to do, and what must be true once
  // the clipboard has answered.
  property var steps: [
    { mode: "text", text: "there\nfriend",
      act: function () {
        note.text = "hello world"
        note.select(6, 11)
        return exchange.pasteInto(asker, note)
      },
      then: function () {
        test.check(note.text === "hello there\nfriend", "replaces the selection, line breaks and all: " + JSON.stringify(note.text))
        test.check(note.cursorPosition === note.text.length, "caret after what was pasted")
        test.check(asker.reports.length === 0, "nothing to report: " + asker.reports)
      } },
    { mode: "text", text: "a\nb",
      act: function () { line.text = "x"; line.cursorPosition = 1; return exchange.pasteInto(asker, line) },
      then: function () { test.check(line.text === "xa b", "a line field gets a space for the break: " + line.text) } },
    // The owner that never stops: the helper reads one byte past 1 MiB, stops,
    // and refuses the lot. Reported to the pane that asked, though the
    // exchange has moved on to another pane meanwhile.
    { mode: "endless",
      act: function () {
        note.text = "kept"
        var asked = exchange.pasteInto(asker, note)
        test.current = other
        return asked
      },
      then: function () {
        test.check(note.text === "kept", "nothing of an endless clipboard lands")
        test.check(asker.reports.join() === "paste: Clipboard text exceeds 1 MiB", "told to the pane that asked: " + asker.reports)
        test.check(other.reports.length === 0, "not to the one the exchange works for now: " + other.reports)
        test.current = asker
      } },
    { mode: "text", text: "much too long for it",
      act: function () { line.text = "ab"; return exchange.pasteInto(asker, line) },
      then: function () {
        test.check(line.text === "ab", "a paste that does not fit is refused whole: " + line.text)
        test.check(asker.reports.join() === "paste: Too long to paste here", "and says so: " + asker.reports)
      } },
    // The field stopped taking text before the clipboard answered: typing
    // ended, the panel closed, the board changed under the note.
    { mode: "text", text: "late",
      act: function () {
        note.text = "before"
        var asked = exchange.pasteInto(asker, note)
        note.takesPaste = false
        return asked
      },
      then: function () {
        test.check(note.text === "before", "a late answer is not taken: " + note.text)
        test.check(asker.reports.join() === "paste: Stopped typing before the clipboard answered; paste again", "and says so: " + asker.reports)
        note.takesPaste = true
      } },
    // The field is gone altogether. A paste meant for it is still a paste
    // meant for a field, and must not become a note on the board instead.
    { mode: "text", text: "orphan",
      act: function () {
        var field = doomed.createObject(test)
        var asked = exchange.pasteInto(asker, field)
        field.destroy()
        return asked
      },
      then: function () {
        test.check(asker.notesMade === 0, "a field's paste never becomes a note")
        test.check(asker.reports.join() === "paste: Stopped typing before the clipboard answered; paste again", "and says so: " + asker.reports)
      } },
    { mode: "fail",
      act: function () { note.text = "same"; return exchange.pasteInto(asker, note) },
      then: function () {
        test.check(note.text === "same", "a clipboard with no text changes nothing")
        test.check(asker.reports.join() === "paste: Clipboard has no available text", "and says so: " + asker.reports)
      } },
    { mode: "text", text: "never asked",
      act: function () {
        note.readOnly = true
        var asked = exchange.pasteInto(asker, note)
        note.readOnly = false
        test.check(!asked, "a read-only field does not ask")
        return false
      },
      then: function () {} }
  ]

  // Writes what the stub should serve, then acts once it has landed.
  function begin() {
    test.step++
    if (test.step === test.steps.length) {
      test.check(asker.notesMade === 0 && other.notesMade === 0, "no step made a note")
      console.log("FIELDPASTE_TESTS_PASSED")
      Qt.quit()
      return
    }
    var s = test.steps[test.step]
    asker.reports = []
    other.reports = []
    // Cleared and deferred: a write in the same turn as the path goes to the
    // path the view still holds.
    served.path = ""
    served.path = test.dir + "/clip-" + ("0" + test.step).slice(-2)
    Qt.callLater(function () { served.setText(s.mode + "\n" + (s.text || "")) })
  }
  Connections { target: served; function onSaved() { test.act() } }
  function act() {
    var s = test.steps[test.step]
    if (!s.act()) { s.then(); Qt.callLater(test.begin); return }
    test.check(exchange.pasteForField, "a field's paste is under way")
    waiting.restart()
  }
  // A paste for a field ends when the exchange lets go of it.
  Timer {
    id: waiting
    interval: 20
    repeat: true
    property int ticks: 0
    onTriggered: {
      test.check(++ticks < 500, "the clipboard answered within ten seconds (step " + test.step + ")")
      if (exchange.pasteForField) return
      stop()
      ticks = 0
      test.steps[test.step].then()
      Qt.callLater(test.begin)
    }
  }
  Component.onCompleted: Qt.callLater(test.begin)
}
