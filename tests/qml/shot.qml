import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "BoardStore.js" as Store
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

  FileView {
    id: showcase
    path: Quickshell.env("OMARCHYFORM_TEST_DIR") + "/showcase.json"
  }

  // The session is a child of the controller rather than a property of it.
  function session() {
    for (var i = 0; i < plugin.data.length; i++)
      if (plugin.data[i] && typeof plugin.data[i].failedSave === "function") return plugin.data[i]
    throw new Error("no board session under the controller")
  }

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
        plugin.library.ask("rename", "new name:", "quarterly plan")
      }
    },
    {
      name: "10b-browser-scrolling",
      setup: function () {
        plugin.library.cancelPrompt()
        var rows = []
        for (var i = 1; i <= 30; i++) rows.push({ path: "board-" + i + ".json", dir: false })
        plugin.library.entries = rows
        plugin.library.index = 12
      }
    },
    {
      // At working zoom, where a ring, a grip and an overflow tab are the size
      // a person actually sees them.
      name: "11-working-zoom",
      setup: function () {
        plugin.library.hide()
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
      // A visual fixture: the session is handed the failure a refused write
      // reports, rather than a write being made to fail. That is the real
      // state — "Save failed" in the header, autosave held — and not a flash
      // that only looks like it. The connector the scenes above left being
      // aimed stays aimed, because a failed save has to outrank it on the line.
      name: "12-failed-save",
      setup: function () {
        shots.session().failedSave("Could not write the board")
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
        shots.session().saveError = ""
        plugin.linkingFrom = -1
        plugin.statusText = ""
        plugin.selectedIndex = -1
        plugin.markedIds = []
        plugin.restore(Store.readFile(showcase.text()))
        plugin.stopEditing()
        plugin.selectedIndex = -1
        plugin.fitToItems()
        // Fit the complete example beneath the chrome, including on tall displays.
        var available = plugin.viewH - plugin.activeBoard.canvasTop - 48
        plugin.zoom = Math.min(1, (plugin.viewW - 96) / 1020, available / 725)
        plugin.camX = (plugin.viewW - 1020 * plugin.zoom) / 2
        plugin.camY = plugin.activeBoard.canvasTop + 24
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
    plugin.library.hide()
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

    // Pinned last, once every item exists. Pinning moves a delegate from the
    // foreground to the background, and adding items after that asks the
    // repeater to stack a new one behind one that is no longer its sibling —
    // which it says so about, in the terminal of whoever is driving the board.
    plugin.selectOnly(0)
    plugin.togglePin()

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

  // Where a held run has got to. Held open, this process has no deadline of
  // its own, so the only thing that ends it is the board being dismissed —
  // and the first version of this never ended at all, because hiding a window
  // is not the same as closing a board.
  //
  //   preparing  taking the pictures
  //   ready      the board is up and being driven by hand
  //   closing    it was dismissed; waiting for what it was writing
  //   finished   everything is on disk, exit 0
  //   failed     a write failed or would not finish, exit 1
  property string phase: "preparing"
  property int readyAt: 0
  property int closingSince: 0
  // Five seconds at fifty milliseconds a tick. Long enough for an atomic write
  // and its backup, short enough that a stuck one is reported rather than sat
  // through: a run that hangs is a temporary directory nobody cleans up.
  readonly property int writeGrace: 100

  function finish(how, why) {
    shots.phase = how
    if (how === "finished") {
      console.log("SHOTS_HELD_DONE")
      Qt.quit()
    } else {
      console.error("SHOTS_HELD_FAILED — " + why)
      Qt.exit(1)
    }
  }

  // Ticks to wait before dismissing the board without being asked, so the
  // lifecycle above can be tested without a hand on the keyboard. Only set by
  // tests/shots.js when it is checking itself; unset, a held run waits for a
  // person, which is the whole point of it.
  readonly property int dismissAfter: parseInt(Quickshell.env("OMARCHYFORM_SHOT_DISMISS") || "0", 10)

  // Set alongside the dismissal, to check that a write that cannot finish is
  // reported rather than sat through. The boards directory is taken away from
  // the board while it is open, so the flush that closing does has somewhere
  // it cannot write to — the same shape as a full disk or a directory someone
  // moved, which is not a thing a suite can arrange any other way.
  readonly property bool failTheWrite: Quickshell.env("OMARCHYFORM_SHOT_FAILWRITE") === "1"
  Process { id: breakWrites }

  // Ticks to wait before switching between fullscreen and windowed, so the
  // check that a held run survives it does not need a hand either. One surface
  // goes and another arrives; the board is never closed, and neither is this.
  readonly property int toggleAfter: parseInt(Quickshell.env("OMARCHYFORM_SHOT_TOGGLE") || "0", 10)
  property bool toggled: false

  function held() {
    if (shots.phase === "ready" && shots.toggleAfter > 0 && !shots.toggled
        && shots.ticks - shots.readyAt > shots.toggleAfter) {
      shots.toggled = true
      plugin.toggleWindowMode()
      console.log("SHOTS_HELD_TOGGLED to " + (plugin.windowMode ? "windowed" : "fullscreen"))
    }
    if (shots.phase === "ready" && shots.dismissAfter > 0
        && shots.ticks - shots.readyAt > shots.dismissAfter) {
      if (shots.failTheWrite) {
        breakWrites.command = ["chmod", "500", plugin.boardsDir]
        breakWrites.running = true
        plugin.items.setProperty(1, "itext", "something to fail to save")
      }
      console.log("SHOTS_HELD_DISMISSING")
      plugin.dismiss()
    }
    if (shots.phase === "ready") {
      // The controller's own answer, not any one window's. close() refuses
      // while an image export is running, and switching between fullscreen and
      // windowed takes one surface down and puts another up without the board
      // ever being closed — watching a window would end the run on both.
      if (!plugin.opened) {
        shots.phase = "closing"
        shots.closingSince = shots.ticks
      }
      return
    }
    if (shots.phase !== "closing") return
    // Closing flushes; a board that could not be written is the one thing a
    // held run must not exit quietly on, because the point of it is the board.
    if (plugin.saveError !== "") {
      shots.finish("failed", "the board could not be written: " + plugin.saveError)
      return
    }
    if (plugin.saving || plugin.pendingBoard !== null || plugin.exchangeBusy || plugin.imageBusy) {
      if (shots.ticks - shots.closingSince > shots.writeGrace)
        shots.finish("failed", "something was still being written five seconds after closing")
      return
    }
    shots.finish("finished", "")
  }

  function advance() {
    shots.scene += 1
    if (shots.scene >= shots.scenes.length) {
      console.log("SHOTS_DONE")
      if (shots.hold) {
        shots.buildHeldBoard()
        shots.phase = "ready"
        shots.readyAt = shots.ticks
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
      if (!result.saveToFile(shots.dir + "/" + shots.scenes[shots.scene].name + ".png")) {
        shots.finish("failed", "could not save screenshot " + shots.scenes[shots.scene].name)
        return
      }
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
      // The clock does not run out on a board being driven by hand: from here
      // the run ends when the board is dismissed, or when what it was writing
      // will not finish.
      if (shots.hold && shots.scene >= shots.scenes.length) { shots.held(); return }
      if (shots.ticks > 900) {
        console.error("SHOTS_TIMEOUT at scene " + shots.scene)
        Qt.exit(1)
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
