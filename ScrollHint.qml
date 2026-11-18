pragma ComponentBehavior: Bound

import QtQuick
import "kit/Theme" as Kit

// There is more than fits. A slim rule down the inside edge of a panel: as long
// a fraction of the track as what you can see is of the whole, and as far down
// it as you have already gone. It appears only when something is out of sight,
// so a panel that fits keeps its clean edge.
//
// Deliberately not a scrollbar you can drag. These panels are driven from the
// keyboard, and a thumb that invites a grab it does not answer is worse than no
// thumb at all. The wheel and a drag on the panel itself still work, as before.
// It wears the kit's scrollbar all the same: its track, its thumb colour, its
// thickness and its corners, so it reads as the one beside a kit ScrollArea.
Item {
  id: hint
  required property Flickable view

  // How much is out of sight. One pixel of slack, so a rounding error in a
  // panel that fits exactly does not put a rule down the side of it.
  readonly property real hidden: Math.max(0, hint.view.contentHeight - hint.view.height)
  readonly property real progress: hint.hidden > 0
    ? Math.min(1, Math.max(0, hint.view.contentY / hint.hidden))
    : 0

  visible: hint.hidden > 1
  width: Kit.Style.spacing.scrollbarThickness

  // Square by default, like everything else here: Omarchy rounds nothing
  // unless the theme says to, and a small part at most min(4, radius).
  readonly property int rounding: Math.min(4, Kit.Style.cornerRadius)

  Rectangle {
    anchors.fill: parent
    radius: hint.rounding
    color: Kit.Color.track
  }

  Rectangle {
    width: parent.width
    // Never shorter than a thumb the eye can find: a very long list would
    // otherwise wear a dot, which says there is more but not how much more.
    height: Math.max(Kit.Style.space(24),
                     hint.height * Math.min(1, hint.view.height / Math.max(1, hint.view.contentHeight)))
    y: (hint.height - height) * hint.progress
    radius: hint.rounding
    // The kit's thumb, not the accent, which is kept for the row the cursor
    // is on. A mark that says how much more there is does not need to compete
    // with the thing being chosen.
    color: Kit.Style.normalBorderColor
  }
}
