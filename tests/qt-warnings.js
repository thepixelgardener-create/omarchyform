// What the Qt Quick suites may print without failing. Everything else the
// engine warns about fails the run: a binding that assigns undefined, an item
// stacked where it cannot be, a property that is not there. Such a line used
// to scroll past a green result, and the same line is in the shell's log on a
// desktop.
const EXPECTED = [
  // Qt's own files, which are not ours to quiet: Qt 6.4's SignalSpy writes a
  // global on every use.
  /qrc:\/qt-project\.org\//,
  // The pictures the export and missing-picture tests leave out on purpose.
  // A load that fails reports when it fails, which can be a test later than
  // the one that asked, so they are named here rather than in each test.
  /: Cannot open: file:\/\/\S*\/(gone|late)\.png$/,
  // An item that follows a background: the repeater cannot stand it after one
  // living in the other layer, and says so. Nothing drawn changes, and making
  // it quiet cost a quarter more time switching a large board; tests/qt/
  // tst_pan.qml, test_eachItemSitsInItsLayerInBoardOrder, has the account.
  /QQuickItem::stack(After|Before): Cannot stack Node_QMLTYPE_\d+\(/,
]

// The lines of a qmltestrunner run that are warnings nobody expected.
function unexpectedWarnings(output) {
  return output.split('\n').filter(line => /^Q(WARN|CRITICAL|SYSTEM|FATAL)\b/.test(line)
    && !EXPECTED.some(known => known.test(line.trimEnd())))
}

module.exports = { unexpectedWarnings }
