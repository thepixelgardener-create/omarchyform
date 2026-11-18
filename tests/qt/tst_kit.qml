import QtQuick
import QtTest
import "../../kit/Ui" as O
import "../../kit/Theme" as Kit

// The Omarchy UI kit as the plugin carries it (kit/, copied by
// tools/vendor-kit.js): every component loads with no shell present, and the
// kit's own resolver follows what Theme.qml feeds its ThemeSource stand-in, the
// way it follows the C++ one in an app. If a copy of the kit ever reaches for a
// name its stand-in does not have, this fails here and not on a desktop.
TestCase {
  id: test
  name: "Kit"
  when: windowShown
  visible: true
  width: 640
  height: 480

  // Two fixture themes, cut down from the kit's fixtures/themes: the palette is
  // what the resolver needs, and shell.toml is optional (it derives the rest).
  readonly property string nord: 'mode = "dark"\naccent = "#81a1c1"\nmuted = "#4c566a"\n'
    + 'background = "#2e3440"\nforeground = "#d8dee9"\ndark_foreground = "#667080"\n'
    + 'red = "#bf616a"\nyellow = "#ebcb8b"\ngreen = "#a3be8c"\n'
  readonly property string latte: 'mode = "light"\naccent = "#1e66f5"\nmuted = "#9ca0b0"\n'
    + 'background = "#eff1f5"\nforeground = "#4c4f69"\ndark_foreground = "#6c6f85"\n'
    + 'red = "#d20f39"\nyellow = "#df8e1d"\ngreen = "#40a02b"\n'

  // What the panels are built from. Each must load and size itself.
  readonly property var parts: ["Toolbar", "ToolbarSeparator", "Tooltip", "ShortcutSheet", "Keycap",
    "KeyCombo", "ListRow", "Dialog", "Toast", "Banner", "SwatchStrip", "Pane", "Card", "ScrollArea",
    "EmptyState", "Heading", "Button", "PanelActionButton", "BorderSurface"]

  Item {
    id: stage
    anchors.fill: parent
  }

  function initTestCase() {
    Kit.ThemeSource.apply({ colorsText: test.nord, shellText: "", userShellText: "", rounding: 0,
                            animations: false, languageText: "en" })
  }

  function test_followsWhatItIsFed() {
    compare(String(Kit.Color.background), "#2e3440")
    compare(String(Kit.Color.foreground), "#d8dee9")
    verify(Kit.Color.dark)
    compare(Kit.Style.cornerRadius, 0)
    var before = Kit.Tokens.revision
    var heard = 0
    function hear() { heard += 1 }
    Kit.Tokens.changed.connect(hear)
    Kit.ThemeSource.apply({ colorsText: test.latte, rounding: 8 })
    Kit.Tokens.changed.disconnect(hear)
    compare(String(Kit.Color.background), "#eff1f5")
    verify(!Kit.Color.dark)
    compare(Kit.Style.cornerRadius, 8)
    compare(Kit.Tokens.revision, before + 1, "one change, announced once")
    compare(heard, 1)
    // The same values again change nothing and announce nothing.
    Kit.ThemeSource.apply({ colorsText: test.latte, rounding: 8 })
    compare(Kit.Tokens.revision, before + 1)
    Kit.ThemeSource.apply({ colorsText: test.nord, rounding: 0 })
  }

  function test_everyPartLoads_data() {
    return test.parts.map(function (name) { return { tag: name, name: name } })
  }
  function test_everyPartLoads(data) {
    var component = Qt.createComponent("../../kit/Ui/" + data.name + ".qml")
    compare(component.status, Component.Ready, component.errorString())
    var item = component.createObject(stage)
    verify(item, data.name + " made nothing")
    item.destroy()
  }

  function test_aKeycapIsAKey() {
    var cap = Qt.createComponent("../../kit/Ui/Keycap.qml").createObject(stage, { key: "z" })
    verify(cap.implicitWidth > 0 && cap.implicitHeight > 0)
    compare(cap.label, "Z", "the kit prints keys as a keyboard does")
    cap.destroy()
  }

  // Ours keeps the case, since h moves and H pushes.
  function test_ourKeyCapKeepsTheCase() {
    var component = Qt.createComponent("../../KeyCap.qml")
    compare(component.status, Component.Ready, component.errorString())
    var lower = component.createObject(stage, { key: "h" })
    var upper = component.createObject(stage, { key: "H" })
    var ctrl = component.createObject(stage, { key: "ctrl" })
    compare(lower.label, "h")
    compare(upper.label, "H")
    compare(ctrl.label, "Ctrl")
    lower.destroy(); upper.destroy(); ctrl.destroy()
  }
}
