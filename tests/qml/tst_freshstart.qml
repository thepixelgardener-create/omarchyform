import QtQuick
import Quickshell
import "services" as Host

// A fresh install, before anything has made a folder: the first board opens
// empty and editable. The state is read once the folders exist; read at once,
// it had the board's path checked before its folder was there, and the first
// board opened read-only as "goes through a symlink". Nothing is summoned, so
// no surface is shown.
ShellRoot {
  id: test
  property int ticks: 0
  Host.PluginShellApi { id: facade; pluginId: "thepixelgardener.omarchyform" }
  Omarchyform { id: plugin; shell: facade; manifest: ({ id: facade.pluginId }) }
  Timer {
    interval: 50
    repeat: true
    running: true
    onTriggered: {
      test.ticks++
      var p = plugin.activePane
      if (p.damaged) {
        console.error("FAIL: a fresh install's first board is read-only: " + p.damageReason)
        Qt.exit(1)
      } else if (p.boardLoaded && p.canEdit) {
        console.log("FRESHSTART_TESTS_PASSED")
        Qt.quit()
      } else if (test.ticks > 200) {
        console.error("FAIL: a fresh install's first board never loaded")
        Qt.exit(1)
      }
    }
  }
}
