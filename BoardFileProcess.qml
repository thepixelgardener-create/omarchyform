import QtQuick
import Quickshell.Io

// Requests are private stdin data, not native command arguments. Quickshell
// emits runningChanged but no exited signal when an executable cannot start.
Item {
  id: request
  property var command: []
  property bool running: false
  property alias stdout: worker.stdout
  property alias stderr: worker.stderr
  property bool stdinEnabled: false
  property bool ready: false
  property bool pending: false
  property bool began: false
  property int serial: 0
  property var activeCommand: []
  readonly property bool validRequest: activeCommand.length >= 3 && activeCommand.every(function(value) {
    return typeof value === "string" && value.indexOf("\0") < 0
  })
  signal started()
  signal exited(int exitCode, int exitStatus)
  function write(text) { worker.write(text) }
  function launch() {
    serial++
    pending = true
    began = false
    activeCommand = command.slice()
    worker.stdinEnabled = true
    worker.running = true
  }
  function finish(code, status) {
    if (!pending) return
    pending = false
    running = false
    exited(code, status)
  }
  onRunningChanged: {
    if (!ready) return
    if (running) launch()
    else if (worker.running) worker.running = false
  }
  Component.onCompleted: {
    ready = true
    if (running) launch()
  }
  onStdinEnabledChanged: if (worker.running && !stdinEnabled) worker.stdinEnabled = false
  Process {
    id: worker
    command: request.validRequest
      ? ["python3", request.activeCommand[1].replace(/\.sh$/, ".py")] : ["false"]
    stdinEnabled: true
    onStarted: {
      request.began = true
      if (!request.validRequest) return
      var args = request.activeCommand.slice(3)
      worker.write(request.activeCommand[2] + "\0" + args.length + "\0"
                   + (args.length ? args.join("\0") + "\0" : ""))
      request.started()
      if (!request.stdinEnabled) worker.stdinEnabled = false
    }
    onExited: function(code, status) { request.finish(code, status) }
    onRunningChanged: {
      if (running || !request.pending) return
      var attempt = request.serial
      // Let a real exit arrive first. A failed launch has no such signal.
      Qt.callLater(function() {
        if (request.serial === attempt && request.pending && !request.began && !worker.running)
          request.finish(127, 0)
      })
    }
  }
}
