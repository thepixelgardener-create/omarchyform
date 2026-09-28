import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "services" as Host

// Puts the real plugin into each state worth looking at and saves a picture of
// each one. Nothing here asserts: this is for eyes. It exists because the
// states that need judging — what a cursor looks like beside a mark, whether a
// tinted item reads as selected, whether a hint fits on one line — are not
// things a test can tell you, and guessing at them from the source has been
// wrong before.
ShellRoot {
  id: shots
  readonly property string dir: Quickshell.env("OMARCHYFORM_SHOT_DIR")
  property int ticks: 0
  property int waitUntil: 0
  property int scene: -1
  property bool grabbing: false
  property bool grabWanted: false

  // Each scene puts the board in a state and is photographed once it settles.
  // Order matters only in that each one starts from where the last left off.
  readonly property var scenes: [
    { name: "01-empty", setup: function () {} },
    {
      name: "02-one-of-everything",
      setup: function () {
        plugin.addItem("note", 220, 180)
        plugin.items.setProperty(0, "itext", "A thought worth keeping.\nIt runs to a second line.")
        plugin.addItem("rect", 560, 180)
        plugin.items.setProperty(1, "itext", "a box")
        plugin.addItem("ellipse", 840, 180)
        plugin.items.setProperty(2, "itext", "an ellipse")
        plugin.addItem("diamond", 1100, 180)
        plugin.items.setProperty(3, "itext", "a diamond")
        plugin.addItem("note", 220, 460)
        plugin.items.setProperty(4, "itext", "Overflowing: "
          + "a long sentence that keeps going past the bottom edge of the note. ".repeat(4))
        plugin.addItem("note", 560, 460)
        plugin.items.setProperty(5, "itext", "a marked note")
        plugin.addItem("note", 840, 460)
        plugin.items.setProperty(6, "itext", "also marked")
        plugin.addLink(1, 2)
        plugin.addLink(6, 7)
        plugin.stopEditing()
        plugin.selectOnly(0)
        plugin.fitToItems()
      }
    },
    {
      // The header is one line until the menu is asked for.
      name: "02b-menu-open",
      // Walked two along, so the keyboard's place in it is visible.
      setup: function () { plugin.toggleMenu(); plugin.moveMenu(2) }
    },
    {
      // The overflow marker and the resize grip both want a corner.
      name: "03-overflowing-and-selected",
      // The menu closes again first: every later scene wants the slim header.
      setup: function () { plugin.menuVisible = false; plugin.selectOnly(4) }
    },

    {
      // The question the review asked: is the cursor told apart from a mark,
      // whatever the two of them are tinted?
      name: "04-cursor-beside-marks",
      setup: function () {
        plugin.markedIds = [plugin.items.get(5).iid, plugin.items.get(6).iid]
        plugin.selectedIndex = 5
      }
    },
    {
      name: "05-typing",
      setup: function () {
        plugin.markedIds = []
        plugin.selectedIndex = 0
        plugin.editSelected()
      }
    },
    {
      name: "06-backgrounds",
      setup: function () {
        plugin.stopEditing()
        plugin.selectedIndex = 3
        plugin.togglePin()
        plugin.togglePinnedSelection()
      }
    },
    {
      name: "07-finding",
      setup: function () {
        plugin.showPinned = false
        plugin.selectedIndex = 0
        plugin.beginFind()
        plugin.setFindQuery("ma")
      }
    },
    {
      name: "08-arranging",
      setup: function () {
        plugin.endFind()
        plugin.markedIds = [plugin.items.get(5).iid, plugin.items.get(6).iid]
        plugin.selectedIndex = 5
        plugin.beginArrange()
      }
    },
    {
      name: "08b-commands",
      setup: function () {
        plugin.cancelArrange()
        plugin.markedIds = []
        // Nothing selected, so the commands that need something to act on say
        // what they are waiting for rather than looking available.
        plugin.selectedIndex = -1
        plugin.beginPalette()
      }
    },
    {
      name: "08c-commands-narrowed",
      setup: function () {
        plugin.setPaletteQuery("co")
      }
    },
    {
      // What can be done with what is selected: the same panel, opened on the
      // commands that act on it, with the arrangement chord's answers named.
      name: "08d-selection-actions",
      setup: function () {
        plugin.endPalette()
        plugin.selectOnly(5)
        plugin.markedIds = [plugin.items.get(5).iid, plugin.items.get(6).iid]
        plugin.beginSelectionActions()
        plugin.setPaletteQuery("a")
      }
    },
    {
      // Two versions of one board. The panel is what a person is asked, so it
      // is worth looking at in every theme the board is drawn in.
      name: "08e-two-versions",
      setup: function () {
        plugin.endPalette()
        plugin.conflictVisible = true
        plugin.conflictIndex = 1
      }
    },
    {
      name: "09-help",
      setup: function () {
        plugin.conflictVisible = false
        plugin.markedIds = []
        plugin.helpVisible = true
      }
    },
    {
      name: "10-browser",
      setup: function () {
        plugin.helpVisible = false
        plugin.openBrowser()
      }
    },
    {
      // More boards than the panel holds: the one state where the browser
      // wears the scroll mark, and the only way to see whether the mark clears
      // the row under the cursor. The entries are planted rather than written
      // to disk — the isolated HOME has one board in it, and thirty files
      // would say nothing thirty rows do not.
      // Naming a board: the one place the browser shows a text field, with the
      // name it opened on selected so a keystroke replaces it.
      name: "10a-naming",
      setup: function () {
        plugin.prompt("rename", "new name:", "quarterly plan")
      }
    },
    {
      name: "10b-browser-scrolling",
      setup: function () {
        plugin.cancelPrompt()
        var rows = []
        for (var i = 1; i <= 30; i++) rows.push({ path: "board-" + i + ".json", dir: false })
        plugin.browserEntries = rows
        plugin.browserIndex = 12
      }
    },
    {
      // At working zoom, where a ring, a grip and an overflow tab are the size
      // a person actually sees them.
      name: "11-working-zoom",
      setup: function () {
        plugin.closeBrowser()
        plugin.resetView()
        plugin.markedIds = [plugin.items.get(6).iid]
        plugin.selectedIndex = 5
        // Centred by the controller rather than by hand: world units are not
        // screen pixels, and picking camera values by eye went wrong twice.
        // The marked one sits to its right, which is the comparison worth
        // having at the size a person sees it.
        plugin.centerOnSelected()
      }
    },
    {
      // The three things the second x can do, in the one line that promises
      // them. Photographed because the wording is the whole feature: it is
      // read in a hurry, in whatever theme and font size the desktop is set
      // to, and it has to fit on the line without pushing the hints off it.
      //
      // Nothing here is connected yet, so this is the plain case.
      name: "11b-connecting-create",
      setup: function () {
        plugin.markedIds = []
        plugin.fitToItems()
        plugin.selectOnly(4)
        plugin.toggleLinking()
        plugin.selectedIndex = 5
      }
    },
    {
      // A connector already runs the other way between these two, so drawing
      // one now turns that one round rather than adding a second.
      name: "11c-connecting-reverse",
      setup: function () {
        plugin.linkingFrom = -1
        plugin.selectOnly(6)
        plugin.toggleLinking()
        plugin.selectedIndex = 5
      }
    },
    {
      // And one already runs exactly this way, so drawing it again takes it
      // away. The line has to say so before the key is pressed, not after.
      name: "11d-connecting-remove",
      setup: function () {
        plugin.linkingFrom = -1
        plugin.selectOnly(5)
        plugin.toggleLinking()
        plugin.selectedIndex = 6
      }
    },
    {
      // The gesture the scenes above left running has to end first: the line
      // ranks a connector being aimed above a message about something that
      // already happened, so a scene that forgets to cancel photographs the
      // hint rather than the message it is named after.
      name: "12-failed-save",
      setup: function () {
        plugin.linkingFrom = -1
        plugin.repaintLinks()
        plugin.flash("Could not write the board — ctrl+s to retry")
      }
    },
    {
      // The picture in the README. Composed rather than caught in use: it is
      // the first thing a reader sees, so it says what the board is for in the
      // items themselves. It lives here because the last one was arranged by
      // hand and never written down, and so went on showing a header and a
      // hint row that had both since moved.
      name: "13-preview",
      setup: function () {
        plugin.statusText = ""
        plugin.selectedIndex = -1
        plugin.markedIds = []
        plugin.items.clear()
        plugin.links.clear()
        plugin.addItem("note", 240, 200)
        plugin.items.setProperty(0, "itext", "Freeform, but it\nbelongs to the desktop")
        plugin.addItem("rect", 660, 180)
        plugin.items.setProperty(1, "itext", "Keyboard first.\nMouse works too.")
        plugin.addItem("diamond", 1080, 360)
        plugin.items.setProperty(2, "itext", "Many boards,\none key away")
        plugin.addItem("note", 240, 560)
        plugin.items.setProperty(3, "itext", "Notes, boxes,\nellipses, diamonds")
        plugin.addItem("ellipse", 660, 600)
        plugin.items.setProperty(4, "itext", "Connect them")
        plugin.addLink(plugin.items.get(0).iid, plugin.items.get(1).iid)
        plugin.addLink(plugin.items.get(1).iid, plugin.items.get(2).iid)
        plugin.addLink(plugin.items.get(3).iid, plugin.items.get(4).iid)
        plugin.addLink(plugin.items.get(4).iid, plugin.items.get(2).iid)
        plugin.stopEditing()
        plugin.selectedIndex = -1
        plugin.fitToItems()
        // A fit centres the board in the window, which on a tall one leaves a
        // band of nothing under the header. The picture is cropped to the top
        // of the window, so the items are pulled up against the chrome first —
        // measured, because the window is whatever size the compositor gave us.
        var top = Infinity
        for (var i = 0; i < plugin.items.count; i++)
          top = Math.min(top, plugin.items.get(i).iy)
        plugin.camY -= plugin.toScreenY(top) - (plugin.activeBoard.headerHeight + 56)
        plugin.repaintGrid()
        plugin.repaintLinks()
      }
    }
  ]

  // One of each thing docs/pointer-checks.md presses on, because the last scene
  // is composed for the README picture and has no picture and no background in
  // it. Built rather than photographed: nothing here is judged by eye.
  function buildHeldBoard() {
    plugin.endPalette()
    plugin.conflictVisible = false
    plugin.helpVisible = false
    plugin.closeBrowser()
    plugin.cancelArrange()
    plugin.statusText = ""
    plugin.markedIds = []
    plugin.selectedIndex = -1
    plugin.items.clear()
    plugin.links.clear()

    plugin.addItem("rect", 120, 140)
    plugin.items.setProperty(0, "iw", 900)
    plugin.items.setProperty(0, "ih", 620)
    plugin.items.setProperty(0, "itext", "a background")
    plugin.selectOnly(0)
    plugin.togglePin()

    plugin.addItem("note", 240, 260)
    plugin.items.setProperty(1, "itext", "a note to type in")
    plugin.addItem("ellipse", 600, 260)
    plugin.items.setProperty(2, "itext", "a shape")
    plugin.addItem("note", 240, 520)
    plugin.items.setProperty(3, "itext", "another note")
    plugin.addLink(plugin.items.get(1).iid, plugin.items.get(3).iid)

    // The picture the harness wrote into this run's own images directory.
    plugin.addItem("note", 620, 520)
    plugin.items.setProperty(4, "kind", "image")
    plugin.items.setProperty(4, "isrc", "held.png")
    plugin.items.setProperty(4, "itext", "")
    plugin.items.setProperty(4, "iw", 220)
    plugin.items.setProperty(4, "ih", 160)

    plugin.stopEditing()
    plugin.selectedIndex = -1
    plugin.resetView()
    plugin.save(true)
  }

  function settle(frames) { shots.waitUntil = shots.ticks + frames }

  // Set by the harness when it was asked to leave the board up rather than
  // close it. The pictures are still taken; what changes is what happens after
  // the last one — the board stays on screen, on the isolated boards directory
  // this run built, for the pointer checks in docs/pointer-checks.md. There is
  // no way to synthesise a pointer into a real compositor from here, so those
  // are done by hand, and this is what they are done to.
  readonly property bool hold: Quickshell.env("OMARCHYFORM_SHOT_HOLD") === "1"

  function advance() {
    shots.scene += 1
    if (shots.scene >= shots.scenes.length) {
      console.log("SHOTS_DONE")
      if (shots.hold) {
        shots.buildHeldBoard()
        console.log("SHOTS_HOLDING — the board is yours; close it with esc esc")
        return
      }
      Qt.quit()
      return
    }
    shots.scenes[shots.scene].setup()
    shots.grabWanted = true
    // Long enough for a fit, a repaint and any asynchronous image to arrive.
    shots.settle(10)
  }

  function grab() {
    shots.grabbing = true
    shots.grabWanted = false
    plugin.activeBoard.grabToImage(function (result) {
      result.saveToFile(shots.dir + "/" + shots.scenes[shots.scene].name + ".png")
      console.log("SHOT " + shots.scenes[shots.scene].name)
      shots.grabbing = false
      shots.settle(3)
      shots.advance()
    })
  }

  Host.PluginShellApi {
    id: facade
    pluginId: "thepixelgardener.omarchyform"
    _hide: function (id) { plugin.close(); return true }
  }
  Omarchyform { id: plugin; shell: facade; manifest: ({ id: facade.pluginId }) }

  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      shots.ticks++
      // The clock does not run out on a board being driven by hand.
      if (shots.hold && shots.scene >= shots.scenes.length) return
      if (shots.ticks > 900) {
        console.error("SHOTS_TIMEOUT at scene " + shots.scene)
        Qt.quit()
        return
      }
      if (shots.grabbing || shots.ticks < shots.waitUntil) return

      if (shots.scene === -1) {
        // A window rather than the fullscreen overlay: a picture of a board
        // wants an edge around it.
        if (!plugin.boardLoaded) return
        if (!plugin.activeBoard) {
          plugin.windowMode = true
          plugin.open("{}")
          shots.settle(10)
          return
        }
        shots.advance()
      } else if (shots.grabWanted) {
        shots.grab()
      }
    }
  }
}
