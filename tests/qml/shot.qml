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
      // The overflow marker and the resize grip both want a corner.
      name: "03-overflowing-and-selected",
      setup: function () { plugin.selectOnly(4) }
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
        plugin.extendFind("m")
        plugin.extendFind("a")
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
      name: "09-help",
      setup: function () {
        plugin.cancelArrange()
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
      name: "12-failed-save",
      setup: function () { plugin.flash("Could not write the board — ctrl+s to retry") }
    }
  ]

  function settle(frames) { shots.waitUntil = shots.ticks + frames }

  function advance() {
    shots.scene += 1
    if (shots.scene >= shots.scenes.length) {
      console.log("SHOTS_DONE")
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
