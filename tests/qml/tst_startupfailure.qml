import QtQuick
import Quickshell
import Quickshell.Io
import "services" as Host

ShellRoot {
  id: test
  property int stage: 0
  property int ticks: 0
  property string dataDir: Quickshell.env("HOME") + "/.local/share/omarchyform"
  property string originalState: '{"lastBoard":"kept.json","windowMode":true}\n'
  function check(value, message) {
    if (!value) { console.error("FAIL: " + message); Qt.exit(1); throw new Error(message) }
  }
  function read(path) { reader.path = path; reader.reload(); reader.waitForJob(); return reader.text() }
  FileView { id: reader; blockLoading: true; blockAllReads: true; printErrors: false }
  Host.PluginShellApi { id: facade; pluginId: "thepixelgardener.omarchyform" }
  Omarchyform { id: plugin; shell: facade; manifest: ({id: facade.pluginId}) }
  Process {
    id: repair
    command: ["/bin/rm", "--", test.dataDir + "/boards"]
    onExited: function(code) {
      test.check(code === 0, "repair fixture")
      plugin.retryStartup()
      test.stage = 2
    }
  }
  Timer {
    running: true; repeat: true; interval: 40
    onTriggered: {
      test.check(++test.ticks < 200, "startup failure/retry completes")
      if (test.stage === 0 && plugin.startupError !== "") {
        test.check(!plugin.storageReady && !plugin.stateReady, "failed privacy check blocks initialization")
        test.check(plugin.documents.length === 0 && plugin.activePane.doc === null, "no board loaded")
        test.check(plugin.library.trashIndexPath === "", "trash remains unread")
        test.check(plugin.startupError.indexOf("permissions") >= 0, "actionable permission error")
        plugin.applyState(test.originalState)
        plugin.writeState()
        test.check(plugin.documents.length === 0, "early callbacks cannot bypass privacy gate")
        test.check(test.read(test.dataDir + "/state.json") === test.originalState, "state untouched")
        test.check(test.read(test.dataDir + "/boards") === "BLOCKER", "migration never ran")
        test.check(test.read(test.dataDir + "/board.json") === "LEGACY", "legacy file untouched")
        test.stage = 1
        repair.running = true
      } else if (test.stage === 2 && plugin.stateReady && plugin.activePane.canEdit) {
        test.check(plugin.storageReady, "successful retry established privacy")
        test.check(plugin.activePane.currentBoard === "kept.json", "only then was saved state read")
        test.check(test.read(test.dataDir + "/boards/board.json") === "LEGACY", "migration runs after successful retry")
        console.log("STARTUPFAILURE_TESTS_PASSED")
        Qt.quit()
      }
    }
  }
}
