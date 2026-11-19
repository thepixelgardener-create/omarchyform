// The verdict on a Qt Quick run's warnings, on lines taken from real runs.
const assert = require('assert/strict')
const { unexpectedWarnings } = require('./qt-warnings')

const quiet = [
  'PASS   : qmltestrunner::CanvasPointer::test_leftDragStillMovesAnItem()',
  'QDEBUG : qmltestrunner::NodeInteraction::test_maximumBoardPreviewsStayLiteral() qml: 5000 hostile plain-text previews: 44 ms',
  'QWARN  : qmltestrunner::SplitView::test_focus() qrc:/qt-project.org/imports/QtTest/SignalSpy.qml:229: Error: Invalid write to global property "qtest_count"',
  'QWARN  : qmltestrunner::NodeInteraction::test_missingImage() file:///repo/Node.qml:166:3: QML Image: Cannot open: file:///nonexistent/gone.png',
  'QWARN  : qmltestrunner::ExportWaitsForPictures::test_standaloneArrowIsInThePng() file:///repo/BoardImage.qml:187:7: QML Instantiator (parent or ancestor of Image): Cannot open: file:///repo/tests/qt/generated/gone.png',
  'QWARN  : qmltestrunner::ExportWaitsForPictures::test_givingUpSaysSoAndSavesNothing() file:///repo/tests/qt/tst_export.qml:71:3: QML Image: Cannot open: file:///repo/tests/qt/generated/late.png',
  'QWARN  : qmltestrunner::CanvasPointer::test_rightButtonIsUnchanged() QQuickItem::stackAfter: Cannot stack Node_QMLTYPE_155(0x1, parent=0x2, geometry=0,0 0x0) after Node_QMLTYPE_155(0x3, name = "board-item-2"), which must be a sibling',
  'QWARN  : qmltestrunner::CanvasPointer::test_eachItemSitsInItsLayerInBoardOrder(a background first) QQuickItem::stackBefore: Cannot stack Node_QMLTYPE_155(0x1, name="board-item-1", parent=0x2, geometry=60,200 100x100, z=3) before QQuickRepeater(0x3), which must be a sibling',
]
const loud = [
  'QWARN  : qmltestrunner::UnknownTestFunc() file:///repo/BoardPalette.qml:32:3: Unable to assign [undefined] to bool',
  // Something other than a board item stacked where it cannot be.
  'QWARN  : qmltestrunner::SplitView::test_focus() QQuickItem::stackAfter: Cannot stack Board_QMLTYPE_12(0x1, parent=0x2, geometry=0,0 0x0) after QQuickRepeater(0x3), which must be a sibling',
  // A picture the tests did not leave out on purpose.
  'QWARN  : qmltestrunner::NodeInteraction::test_picture() file:///repo/Node.qml:166:3: QML Image: Cannot open: file:///repo/tests/qt/generated/slow.png',
  'QCRITICAL: qmltestrunner::SplitView::test_focus() something gave up',
]

assert.deepEqual(unexpectedWarnings(quiet.join('\n')), [], 'expected lines pass')
assert.deepEqual(unexpectedWarnings(quiet.concat(loud).join('\r\n')).map(line => line.trimEnd()), loud,
  'every other warning is reported, whatever the line ending')
console.log('ok — Qt Quick warnings: the expected pass, every other one fails the run')
