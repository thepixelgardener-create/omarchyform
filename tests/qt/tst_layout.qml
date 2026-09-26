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
    // The header is a bar and takes the theme's bar colours. Distinct from the
    // canvas here on purpose: these stand for tokens a theme may set to
    // something of their own.
    property color barBackground: "#161b22"
    property color barForeground: "#e6e6e6"
    property color accent: "cyan"
    property string fontFamily: "monospace"
    property int fontBody: 24
    property int fontSubtitle: 24
    property int fontHeading: 28
    property int borderWidth: 1
    property int cornerRadius: 0
    property bool browserVisible: false
    property bool menuVisible: false
    property int menuIndex: 0
    function toggleMenu() { menuVisible = !menuVisible }
    function runMenu(index) { menuVisible = false }
    property bool browserSearching: false
    property string browserQuery: ""
    property string browserPrompt: ""
    property string browserInput: ""
    property string trashIndexError: ""
    property string browserMessage: ""
    property string browserDir: ""
    property string boardTitle: "A long board name that should truncate gracefully"
    property string boardState: "Saved locally"
    property string saveError: ""
    property color urgent: "red"
    property color muted: "gray"
    property real zoom: 1
    function renameBoard() {}
    function resetView() {}
    function fitToItems() {}
    function newBoard() {}
    function openBrowser() {}
    function importBoard() {}
    function exportBoard() {}
    function choosePng() {}
    property string currentBoard: "board.json"
    property var browserRows: []
    property int browserIndex: 0
    property bool browserTrash: false
    function browserEnter() {}
    function sp(n) { return n }
    function closeBrowser() { browserVisible = false }
    function browserKey(event) {}
  }
  Help { id: help; ctl: ctl; anchors.centerIn: parent }
  Browser { id: browser; ctl: ctl; anchors.fill: parent }
  BoardToolbar { id: toolbar; ctl: ctl; width: test.width - 32; height: implicitHeight; visible: false }
  // The header is a bar, so it is painted in the theme's bar colours rather
  // than the canvas ones.
  //
  // Reading them here is worth little as a guard against a stub missing one:
  // a stub short of `barForeground` still passes this on Qt 6.11, with no
  // warning, while the same tree fails on the 6.4 that CI runs. What keeps
  // that from happening is the name check in tests/contract.js, which does not
  // depend on which Qt is doing the reading.
  function test_toolbarTakesTheBarColours() {
    compare(toolbar.color, ctl.barBackground, "the header takes the bar's background")
    verify(toolbar.color !== ctl.canvasBackground, "which is its own colour, not the canvas")
    verify(toolbar.border.color !== ctl.canvasBackground, "and its edge is drawn against it")
  }

  function test_toolbarFitsLargeFonts() {
    verify(toolbar.implicitHeight < test.height - 64)
    verify(toolbar.children[1].width <= toolbar.width)
  }

  function test_toolbarIsSlimUntilTheMenuIsAskedFor() {
    ctl.menuVisible = false
    toolbar.visible = true
    verify(waitForRendering(toolbar))
    const closed = toolbar.implicitHeight
    // One line of chrome at a body font this large, long board name and all.
    verify(closed < ctl.fontSubtitle * 3)

    ctl.menuVisible = true
    verify(waitForRendering(toolbar))
    verify(toolbar.implicitHeight >= closed, "the menu takes room when it is open")
    verify(toolbar.children[1].width <= toolbar.width, "and still fits across")

    // Closing gives the height back rather than leaving a gap behind.
    ctl.menuVisible = false
    verify(waitForRendering(toolbar))
    compare(toolbar.implicitHeight, closed)
    toolbar.visible = false
  }
  function test_helpFitsAndScrolls() {
    verify(help.width <= test.width - 32)
    verify(help.height <= test.height - 32)
    const content = scroller(help)
    verify(content.contentHeight > content.height)
    help.scroll(100)
    compare(content.contentY, 100)
    help.scroll(10000)
    compare(content.contentY, content.contentHeight - content.height)
  }

  // Board.qml lays a dismiss layer under the panel, so a click on the canvas
  // closes the help. The panel has to keep hold of its own clicks — including
  // the margin ring between its border and the scroller, which used to let one
  // through — without giving up either way of scrolling it. That is the whole
  // reason the swallower sits beneath the Flickable rather than over it.
  Component {
    id: dismissRig
    Item {
      id: rig
      width: 480
      height: 360
      // Spelled out, because a plain `ctl: ctl` inside Help binds the panel's
      // own property to itself rather than to the stub out here.
      property var stub: ctl
      property int dismissals: 0
      property alias panel: panel
      MouseArea {
        anchors.fill: parent
        onClicked: rig.dismissals++
      }
      Help { id: panel; ctl: rig.stub; anchors.centerIn: parent }
    }
  }
  function test_theHelpPanelKeepsItsOwnClicks() {
    const rig = createTemporaryObject(dismissRig, test)
    verify(waitForRendering(rig))
    const panel = rig.panel
    const content = scroller(panel)

    mouseClick(panel, panel.width / 2, panel.height / 2)
    compare(rig.dismissals, 0, "a click in the middle of the panel")
    mouseClick(panel, 8, 8)
    compare(rig.dismissals, 0, "a click inside the panel's own border")
    mouseClick(rig, 4, 4)
    compare(rig.dismissals, 1, "a click on the canvas outside the panel")

    // Both ways of scrolling it survive the swallower.
    verify(content.contentHeight > content.height)
    content.contentY = 0
    mouseWheel(panel, panel.width / 2, panel.height / 2, 0, -120)
    tryVerify(function () { return content.contentY > 0 }, 1000, "the wheel scrolls it")
    content.contentY = 0
    const cx = panel.width / 2
    mousePress(panel, cx, panel.height - 40)
    mouseMove(panel, cx, panel.height - 80)
    mouseMove(panel, cx, panel.height - 120)
    mouseRelease(panel, cx, panel.height - 120)
    tryVerify(function () { return content.contentY > 0 }, 1000, "dragging scrolls it")
  }
  // A panel with room to spare, for the questions the 480x360 case cannot ask:
  // there the key column is clamped to half the width and the labels are
  // supposed to wrap.
  Component {
    id: roomyHelp
    Item {
      width: 2000
      height: 1200
      property int fs: 24
      property alias help: inner
      Item {
        id: c
        property bool helpVisible: true
        property color canvasBackground: "#101315"
        property color foreground: "#cccccc"
        property color accent: "cyan"
        property string fontFamily: "monospace"
        property int fontBody: parent.fs
        property int fontSubtitle: parent.fs
        property int fontHeading: parent.fs + 4
        property int borderWidth: 1
        property int cornerRadius: 0
        // Spacing scales with the text, the way a theme's Style.space does.
        function sp(n) { return Math.round(n * parent.fs / 12) }
      }
      Help { id: inner; ctl: c; anchors.centerIn: parent }
    }
  }

  // The panel's scroller, found rather than counted to: Help has a click
  // swallower among its children as well, and which of them comes first is
  // none of this test's business.
  function scroller(help) {
    for (let i = 0; i < help.children.length; i++)
      if (help.children[i].contentHeight !== undefined) return help.children[i]
    return null
  }

  function keyRows(help) {
    const found = []
    const stack = [scroller(help).contentItem]
    while (stack.length) {
      const item = stack.pop()
      if (item.keyColumn !== undefined) { found.push(item); continue }
      for (let i = 0; i < item.children.length; i++) stack.push(item.children[i])
    }
    return found
  }

  // The key column is measured with font metrics nowhere in it: metrics run a
  // pixel or two under what a Text of the same string needs, by a margin that
  // grows with the size, so the widest label — the one the column was measured
  // from — wrapped from fontBody 24 up while the panel still had half its width
  // going spare.
  function test_keysDoNotWrapWhenThereIsRoom() {
    for (const size of [12, 14, 18, 24, 28, 32]) {
      const rig = createTemporaryObject(roomyHelp, test, {fs: size})
      verify(waitForRendering(rig.help))
      const rows = keyRows(rig.help)
      verify(rows.length > 0, "the shortcut rows were found")
      for (const row of rows) {
        const key = row.children[0]
        verify(row.keyColumn < row.width * 0.5,
          `at ${size}px the key column is not clamped, so nothing need wrap`)
        compare(key.lineCount, 1,
          `'${key.text}' fits its column on one line at ${size}px`)
      }
      rig.destroy()
    }
  }

  // The clamp exists so a long label cannot leave the descriptions narrower
  // than the keys, which is what it was doing when it counted only the keys.
  function test_narrowPanelDoesNotStarveTheDescriptions() {
    const rows = keyRows(help)
    verify(rows.length > 0)
    for (const row of rows) {
      const key = row.children[0]
      const description = row.children[1]
      verify(description.width > 0, "the description has somewhere to go")
      verify(description.width >= key.width,
        `'${key.text}': the description is not the narrower column`)
      verify(row.height >= Math.max(key.contentHeight, description.contentHeight) - 0.5,
        `'${key.text}': the row is tall enough for whichever side wrapped`)
    }
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
