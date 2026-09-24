import QtQuick
import QtTest
import "../.."

TestCase {
  id: test
  name: "SmallWindowLayout"
  when: windowShown
  visible: true
  width: 480
  height: 360
  Item {
    id: ctl
    property bool helpVisible: true
    property color canvasBackground: "#101315"
    property color foreground: "#cccccc"
    property color accent: "cyan"
    property string fontFamily: "monospace"
    property int fontBody: 24
    property int fontSubtitle: 24
    property int fontHeading: 28
    property int borderWidth: 1
    property int cornerRadius: 0
    property bool browserVisible: false
    property bool browserSearching: false
    property string browserQuery: ""
    property string browserPrompt: ""
    property string browserInput: ""
    property string trashIndexError: ""
    property string browserMessage: ""
    property string browserDir: ""
    property string currentBoard: "board.json"
    property var browserRows: []
    property int browserIndex: 0
    function sp(n) { return n }
    function closeBrowser() { browserVisible = false }
    function browserKey(event) {}
  }
  Help { id: help; ctl: ctl; anchors.centerIn: parent }
  Browser { id: browser; ctl: ctl; anchors.fill: parent }
  function test_helpFitsAndScrolls() {
    verify(help.width <= test.width - 32)
    verify(help.height <= test.height - 32)
    const content = help.children[0]
    verify(content.contentHeight > content.height)
    help.scroll(100)
    compare(content.contentY, 100)
    help.scroll(10000)
    compare(content.contentY, content.contentHeight - content.height)
  }
  function test_searchModeWithoutQuery() {
    ctl.browserSearching = true
    compare(browser.searching, true)
    ctl.browserSearching = false
    compare(browser.searching, false)
  }
  function test_browserFooterWraps() {
    ctl.browserVisible = true
    const footer = findChild(browser, "browser-footer")
    const panel = findChild(browser, "browser-panel")
    verify(footer !== undefined)
    verify(footer.width <= test.width - 32)
    verify(footer.implicitHeight > ctl.fontBody)
    verify(panel.y + panel.height < footer.y)
  }
}
