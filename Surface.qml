import QtQuick
import QtQuick.Shapes
import "BoardStore.js" as Store

// A card drawn the way the shell draws its own summoned surfaces — the menu,
// its panels, a notification: solid, in the panel colour, inside the theme's
// border for them. That border may be a gradient at an angle, or a different
// width on each side, and then it is a ring painted over the card; a single
// colour at one width is the Rectangle's own border, which costs nothing.
//
// The spec is plain data that Theme.qml read off the shell, so this imports
// nothing from it: the Qt suites draw it against a stub, and a shell without
// the tokens gets the fallback Theme.qml picked. Put it behind a panel's
// content rather than making it the panel — a panel declaring `ctl` or `theme`
// over one of these would be overriding a property, which CI refuses.
Rectangle {
  id: surface
  required property var theme
  property var spec: surface.theme.panelBorder

  color: surface.theme.panelBackground
  radius: surface.theme.cornerRadius

  readonly property var widths: Store.borderWidths(surface.spec)
  readonly property bool flat: Store.flatBorder(surface.spec)
  border.width: surface.flat ? surface.widths.top : 0
  border.color: surface.flat && surface.spec ? surface.spec.color : "transparent"

  Shape {
    id: ring
    anchors.fill: parent
    visible: !surface.flat && surface.width > 0 && surface.height > 0
    readonly property var colors: surface.spec && surface.spec.gradient && surface.spec.gradient.enabled
      ? surface.spec.gradient.colors : [surface.spec ? surface.spec.color : "transparent"]
    readonly property var ends: Store.gradientEndpoints(surface.width, surface.height,
      surface.spec && surface.spec.gradient ? surface.spec.gradient.angle : 0)

    ShapePath {
      fillRule: ShapePath.OddEvenFill
      strokeWidth: -1
      fillGradient: LinearGradient {
        x1: ring.ends.x1
        y1: ring.ends.y1
        x2: ring.ends.x2
        y2: ring.ends.y2
        GradientStop { position: Store.stopPosition(ring.colors, 0); color: Store.stopColor(ring.colors, 0) }
        GradientStop { position: Store.stopPosition(ring.colors, 1); color: Store.stopColor(ring.colors, 1) }
        GradientStop { position: Store.stopPosition(ring.colors, 2); color: Store.stopColor(ring.colors, 2) }
        GradientStop { position: Store.stopPosition(ring.colors, 3); color: Store.stopColor(ring.colors, 3) }
        GradientStop { position: Store.stopPosition(ring.colors, 4); color: Store.stopColor(ring.colors, 4) }
        GradientStop { position: Store.stopPosition(ring.colors, 5); color: Store.stopColor(ring.colors, 5) }
      }
      PathSvg { path: Store.ringPath(surface.width, surface.height, surface.radius, surface.widths) }
    }
  }
}
