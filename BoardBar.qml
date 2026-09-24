import QtQuick
import qs.Commons
import qs.Ui

// Bar presence for Omarchyform: the only way to find the board without
// already knowing its keybinding. A click opens it through the shell, the
// same route the keybinding takes, so both ends stay in step.
//
// Deliberately does not expose open(), close() and opened: the bar routes a
// `shell summon` to any widget carrying all three, which would send a summon
// aimed at the board back into this icon instead of the overlay.
BarWidget {
  id: root
  moduleName: "thepixelgardener.omarchyform"

  readonly property string pluginId: "thepixelgardener.omarchyform"

  readonly property bool boardOpen: root.bar && root.bar.shell
    && typeof root.bar.shell.isPluginOpen === "function"
    && root.bar.shell.isPluginOpen(root.pluginId)

  // Settings live on the bar entry, so they travel to the board as the summon
  // payload. The board keeps them, so opening from the keyboard later gets the
  // same configuration rather than falling back to defaults.
  function payload() {
    return JSON.stringify({
      settings: {
        autosaveMs: root.setting("autosaveMs", 700),
        step: root.setting("step", 40),
        showGrid: root.setting("showGrid", true),
        startWindowed: root.setting("startWindowed", false)
      }
    })
  }

  function toggleBoard() {
    if (root.bar && root.bar.shell) root.bar.shell.toggle(root.pluginId, root.payload())
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // An outline sticky note. It carries the same stroke weight as the stock
    // bar icons, where the filled version sits heavier than its neighbours; a
    // grid glyph was the first choice and read as a spreadsheet.
    text: ""
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    // Accent rather than the default urgent: an open board is a state, not a
    // problem.
    active: root.boardOpen
    activeColor: Color.accent
    tooltipText: root.boardOpen ? "Omarchyform — open" : "Omarchyform"
    onPressed: root.toggleBoard()
  }
}
