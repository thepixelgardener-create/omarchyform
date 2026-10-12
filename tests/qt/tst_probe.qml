import QtQuick
import QtTest
import "../.."

// A picture just pasted is measured before it is placed, and is loaded to be
// measured only once the file behind it has been checked, like every picture
// the shell draws. The real Board, against the stand-in controller.
TestCase {
  id: test
  name: "PictureProbe"
  when: windowShown
  visible: true
  width: 400
  height: 300

  PaneStub { id: ctl; viewW: test.width; viewH: test.height }
  Board { id: surface; ctl: ctl; width: test.width; height: test.height }

  function init() {
    ctl.pictureStates = ({})
    ctl.pastedImages = []
  }

  function test_waitsForTheCheck() {
    ctl.pictureStates = { "paste-1.png": "waiting" }
    surface.probeImage("paste-1.png")
    wait(100)
    compare(ctl.pastedImages.length, 0, "nothing is loaded or placed while the file is checked")
    ctl.pictureStates = { "paste-1.png": "" }
    tryVerify(function () { return ctl.pastedImages.length === 1 }, 2000, "checked, it is measured")
    compare(ctl.pastedImages[0][0], "paste-1.png")
    compare(ctl.pastedImages[0][1], 2, "at its own size")
    compare(ctl.pastedImages[0][2], 2)
  }

  function test_refusedIsFinishedUnread() {
    ctl.pictureStates = { "paste-2.png": "waiting" }
    surface.probeImage("paste-2.png")
    ctl.pictureStates = { "paste-2.png": "carries compressed text" }
    tryVerify(function () { return ctl.pastedImages.length === 1 }, 2000)
    compare(JSON.stringify(ctl.pastedImages[0]), JSON.stringify(["paste-2.png", 0, 0]),
            "refused, it is finished as one that could not be read, and never loaded")
  }

  function test_checkedAlreadyGoesStraightThrough() {
    surface.probeImage("paste-3.png")
    tryVerify(function () { return ctl.pastedImages.length === 1 }, 2000)
    compare(ctl.pastedImages[0][1], 2)
  }
}
