import QtQuick

// One line to type into: the board's find field, the board browser's field and
// the command list's query.
//
// A TextEdit held to one line rather than a TextInput, because of what Qt
// 6.12.0's TextInput does whenever the clipboard changes. While it is editable,
// QQuickTextInput::q_canPasteChanged asks the clipboard for its whole text
// (QMimeData::text()) to decide whether a paste would be empty, with nobody
// pasting. On Wayland that text is read from whichever client owns the
// clipboard for as long as it keeps sending, so an owner that never stops could
// stall the shell or fill its memory just by changing the clipboard while a
// field was open. TextEdit only asks which formats are on offer. Qt went back
// to that check for TextInput after 6.12.0; tests/clipboard.js holds every
// field here to zero reads either way.
//
// Staying on one line is this item's job: Return, Enter and Tab never reach the
// text, and a paste goes to the owner, which reads it through the clipboard
// helper's 1 MiB limit (BoardExchange.pasteInto) without its newlines.
TextEdit {
  id: field
  textFormat: TextEdit.PlainText
  wrapMode: TextEdit.NoWrap
  selectByMouse: true

  // The owner puts this in a clipping parent as wide as the field should look.
  // A line longer than that scrolls inside it, so the caret stays in view.
  width: Math.max(implicitWidth, parent ? parent.width : 0)
  x: Math.min(0, (parent ? parent.width : 0) - cursorRectangle.x - cursorRectangle.width)

  // What BoardExchange.pasteInto reads. The owner says when a paste may land;
  // the limit is the one TextInput's maximumLength gave these fields.
  property bool takesPaste: false
  readonly property int pasteLimit: 32767
  readonly property bool pasteLines: false

  // Every key goes to the owner first. A paste is asked for rather than taken,
  // and whatever would break the line goes nowhere.
  signal keyPressed(var event)
  signal pasteRequested()

  Keys.onPressed: function (event) {
    if (event.matches(StandardKey.Paste)) {
      event.accepted = true
      field.pasteRequested()
      return
    }
    field.keyPressed(event)
    if (!event.accepted && [Qt.Key_Return, Qt.Key_Enter, Qt.Key_Tab, Qt.Key_Backtab].indexOf(event.key) >= 0)
      event.accepted = true
  }

  // The middle button pastes the primary selection, which Qt would read whole.
  // Taken here, and nothing is done with it.
  MouseArea {
    objectName: field.objectName + "-middle"
    anchors.fill: parent
    acceptedButtons: Qt.MiddleButton
  }
}
