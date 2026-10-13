import QtQuick
import QtTest
import "../.."

// The one-line field the find, browser and command fields are built on. It is
// a TextEdit, which inserts a newline on Return and a tab on Tab, so staying on
// one line is its own job; the security reason it is not a TextInput is in
// LineField.qml, and tests/clipboard.js checks it at the clipboard itself.
TestCase {
  id: test
  name: "LineField"
  when: windowShown
  visible: true
  width: 400
  height: 120

  property var owned: []
  property int pasteAsks: 0

  Item {
    id: view
    width: 120
    height: field.implicitHeight
    clip: true

    LineField {
      id: field
      objectName: "line"
      font.pixelSize: 16
      onPasteRequested: test.pasteAsks++
      // An owner that takes Escape and lets everything else through.
      onKeyPressed: function (event) {
        test.owned.push(event.key)
        if (event.key === Qt.Key_Escape) event.accepted = true
      }
    }
  }

  function init() {
    field.maximumLength = 32767
    field.text = ""
    test.owned = []
    test.pasteAsks = 0
    field.forceActiveFocus()
    tryVerify(function () { return field.activeFocus })
  }

  function test_typingIsText() {
    keyClick("a")
    keyClick("b")
    keyClick(Qt.Key_Backspace)
    keyClick("c")
    compare(field.text, "ac")
    compare(test.owned.length, 4, "the owner heard every key first")
  }

  function test_lengthAndSelectionReplacement() {
    field.maximumLength = 5
    field.text = "abcde"
    field.cursorPosition = 2
    keyClick("X")
    compare(field.text, "abcde", "overflow preserves the suffix")
    field.select(1, 3)
    keyClick("X")
    compare(field.text, "aXde")
    keyClick(Qt.Key_Z, Qt.ControlModifier)
    compare(field.text, "abcde", "ordinary accepted edits retain native undo")
  }

  function test_committedLineSeparators() {
    field.text = "a\r\nb\nc\u2028d\u2029e\tf"
    compare(field.text, "a b c d e f")
  }

  function test_limitDoesNotSplitUnicode() {
    field.maximumLength = 5
    field.text = "abcd"
    field.insert(4, "\uD83D\uDE00")
    compare(field.text, "abcd", "a two-unit character needs two free positions")
  }

  function test_aLineCannotBeBroken_data() {
    return [
      { tag: "return", key: Qt.Key_Return },
      { tag: "enter", key: Qt.Key_Enter },
      { tag: "tab", key: Qt.Key_Tab },
      { tag: "shift+return", key: Qt.Key_Return, modifiers: Qt.ShiftModifier }
    ]
  }
  function test_aLineCannotBeBroken(row) {
    field.text = "one"
    field.cursorPosition = 3
    keyClick(row.key, row.modifiers || Qt.NoModifier)
    compare(field.text, "one", "nothing was inserted")
    verify(test.owned.indexOf(row.key) >= 0, "though the owner was asked first")
  }

  function test_theOwnerChoosesFirst() {
    keyClick(Qt.Key_Escape)
    compare(test.owned[0], Qt.Key_Escape)
    compare(field.text, "")
  }

  function test_pasteKeysAskTheOwner() {
    field.text = "kept"
    keyClick(Qt.Key_V, Qt.ControlModifier)
    keyClick(Qt.Key_Insert, Qt.ShiftModifier)
    compare(test.pasteAsks, 2, "both paste keys ask")
    compare(field.text, "kept", "and the field pastes nothing itself")
    // Only the modifiers reach the owner: a paste is not passed on as a key.
    verify(test.owned.indexOf(Qt.Key_V) < 0 && test.owned.indexOf(Qt.Key_Insert) < 0, String(test.owned))
  }

  function test_pasteRules() {
    verify(!field.pasteLines, "one line")
    compare(field.pasteLimit, 32767)
  }

  function test_middleButtonStopsAtTheGuard() {
    var guard = findChild(field, "line-middle")
    verify(guard !== null)
    mousePress(field, 4, field.height / 2, Qt.MiddleButton)
    verify(guard.pressed)
    mouseRelease(field, 4, field.height / 2, Qt.MiddleButton)
  }

  // Markup typed or set is shown as the characters it is.
  function test_plainText() {
    field.text = "<b>bold</b>"
    compare(field.textFormat, TextEdit.PlainText)
    compare(field.getText(0, field.length), "<b>bold</b>")
  }

  // Longer than its view, the line scrolls so the caret stays inside it.
  function test_theCaretStaysInView() {
    field.text = "a line much longer than the hundred and twenty pixels it has"
    field.cursorPosition = field.length
    verify(field.x < 0, "scrolled")
    var caret = field.mapToItem(view, field.cursorRectangle.x, 0).x
    verify(caret >= 0 && caret <= view.width, "caret at " + caret + " inside 0.." + view.width)
    field.cursorPosition = 0
    compare(field.x, 0, "back at the start")
    field.text = "short"
    compare(field.x, 0)
    verify(field.width >= view.width, "and as wide as its view, so a click anywhere in it lands")
  }
}
