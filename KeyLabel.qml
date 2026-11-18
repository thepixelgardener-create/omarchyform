pragma ComponentBehavior: Bound

import QtQuick
import "BoardStore.js" as Store
import "kit/Theme" as Kit

// A help label as key caps with the words between them: "g then h j k l" is a
// g cap, "then", and four caps. Store.keyLabelParts decides which is which.
// It flows onto a second line when its width is held below what it needs; left
// to itself it is one line, which is what Help measures its key column by.
Flow {
  id: root
  property string label: ""
  readonly property var parts: Store.keyLabelParts(label)
  spacing: Kit.Style.spacing.xxs

  Repeater {
    model: root.parts
    Item {
      id: part
      required property var modelData
      readonly property bool isKey: modelData.key !== undefined
      implicitWidth: isKey ? cap.implicitWidth : Math.ceil(words.implicitWidth)
      implicitHeight: Math.max(cap.implicitHeight, words.implicitHeight)
      width: implicitWidth
      height: implicitHeight
      KeyCap {
        id: cap
        visible: part.isKey
        anchors.verticalCenter: parent.verticalCenter
        key: part.isKey ? part.modelData.key : ""
      }
      Text {
        id: words
        visible: !part.isKey
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: part.isKey ? "" : part.modelData.text
        color: Kit.Color.textDim
        font.family: Kit.Style.font.family
        font.pixelSize: Kit.Style.font.body
      }
    }
  }
}
