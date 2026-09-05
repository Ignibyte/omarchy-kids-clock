import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui

// The big clock. A fullscreen overlay on the menu surface tokens: home's sky
// across the top with the sun or the moon on its arc, then a card for each
// person with their own small sky, what they are probably doing, and
// whether it is a good time to call. Left and right move the sun an hour;
// 0 comes back to now; Escape closes.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "ignibyte.kids-clock"
  readonly property var service: shell && typeof shell.serviceFor === "function" ? shell.serviceFor(pluginId) : null

  property bool opened: false

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding

  // Every colour derives from the theme: the sun is the accent, the moon is
  // the foreground, the skies are the foreground or a darkened background at
  // low alpha. Nothing here is a fixed hex.
  readonly property color sunColor: Color.accent
  readonly property color moonColor: foreground
  readonly property color daySky: Util.alpha(foreground, 0.07)
  readonly property color nightSky: Util.alpha(Qt.darker(background, 1.6), 0.55)
  readonly property color horizon: Util.alpha(foreground, 0.35)
  readonly property color quiet: Util.alpha(foreground, 0.62)
  readonly property color goodDot: Color.accent
  readonly property color busyDot: Util.alpha(foreground, 0.45)
  readonly property color asleepDot: Util.alpha(foreground, 0.2)

  property int cardWidth: Math.min(Style.space(980), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)

  readonly property var home: service ? service.home : null
  readonly property var rows: service ? service.rows : []
  readonly property string scrubWords: service ? service.scrubWords : ""
  readonly property bool scrubbing: service ? service.scrubMinutes !== 0 : false

  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.service) root.service.resetScrub()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // The sun or the moon travels a half ellipse from the left horizon to the
  // right; `t` is 0 at rising and 1 at setting.
  component Sky: Item {
    id: sky
    property bool isDay: true
    property real t: 0.5
    property real bodySize: Style.space(40)
    readonly property real horizonY: height * 0.86
    readonly property real radiusX: width / 2 - bodySize
    readonly property real radiusY: horizonY - bodySize * 0.9
    readonly property real angle: Math.PI * (1 - Math.max(0, Math.min(1, t)))
    readonly property real bodyX: width / 2 + radiusX * Math.cos(angle)
    readonly property real bodyY: horizonY - radiusY * Math.sin(angle)

    Rectangle {
      anchors.fill: parent
      radius: root.cornerRadius
      color: sky.isDay ? root.daySky : root.nightSky
      Behavior on color { ColorAnimation { duration: 500 } }
    }

    Shape {
      anchors.fill: parent
      antialiasing: true
      layer.enabled: true
      layer.samples: 4
      ShapePath {
        strokeColor: root.horizon
        strokeWidth: Math.max(1, Style.space(1))
        fillColor: "transparent"
        strokeStyle: ShapePath.DashLine
        dashPattern: [3, 4]
        startX: sky.width / 2 - sky.radiusX
        startY: sky.horizonY
        PathArc {
          x: sky.width / 2 + sky.radiusX
          y: sky.horizonY
          radiusX: sky.radiusX
          radiusY: sky.radiusY
          direction: PathArc.Clockwise
        }
      }
      ShapePath {
        strokeColor: root.horizon
        strokeWidth: Math.max(1, Style.space(2))
        fillColor: "transparent"
        startX: Style.space(6)
        startY: sky.horizonY
        PathLine { x: sky.width - Style.space(6); y: sky.horizonY }
      }
    }

    Item {
      id: body
      width: sky.bodySize
      height: sky.bodySize
      x: sky.bodyX - width / 2
      y: sky.bodyY - height / 2
      Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
      Behavior on y { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

      // The sun: a full accent disc.
      Rectangle {
        visible: sky.isDay
        anchors.fill: parent
        radius: width / 2
        color: root.sunColor
      }

      // The moon: a crescent. The outer edge is the left half of the disc,
      // the inner edge a shallower arc back up, so the fill between them is
      // the lit sliver and the sky shows through the rest.
      Shape {
        visible: !sky.isDay
        anchors.fill: parent
        antialiasing: true
        layer.enabled: true
        layer.samples: 4
        ShapePath {
          fillColor: root.moonColor
          strokeWidth: 0
          strokeColor: "transparent"
          startX: body.width * 0.5
          startY: 0
          PathArc {
            x: body.width * 0.5
            y: body.height
            radiusX: body.width / 2
            radiusY: body.height / 2
            direction: PathArc.Counterclockwise
          }
          PathArc {
            x: body.width * 0.5
            y: 0
            radiusX: body.width * 0.62
            radiusY: body.height * 0.62
            direction: PathArc.Clockwise
          }
        }
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "kids-clock"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.scrubbing && root.service) root.service.resetScrub()
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Right) {
            if (root.service) root.service.scrub(event.modifiers & Qt.ShiftModifier ? 15 : 60)
            event.accepted = true
          } else if (event.key === Qt.Key_Left) {
            if (root.service) root.service.scrub(event.modifiers & Qt.ShiftModifier ? -15 : -60)
            event.accepted = true
          } else if (event.key === Qt.Key_0 || event.key === Qt.Key_Home || event.key === Qt.Key_Space) {
            if (root.service) root.service.resetScrub()
            event.accepted = true
          }
        }
      }

      Item {
        id: content
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        readonly property int gap: Style.spacing.lg
        readonly property int homeSkyHeight: Math.round(root.cardHeight * 0.26)
        readonly property int peopleHeight: height - homeHeader.height - homeSkyHeight - hint.height - gap * 3

        // Home: the sentence, the digits when the band allows them, and the sky.
        // Anchors rather than a Row: the digits sit on the right at their own
        // width and the sentence wraps into whatever is left.
        Item {
          id: homeHeader
          width: parent.width
          height: Math.max(homeColumn.implicitHeight, homeTime.implicitHeight)

          Text {
            id: homeTime
            anchors.right: parent.right
            anchors.top: parent.top
            textFormat: Text.PlainText
            text: root.home ? root.home.timeText : ""
            visible: text !== ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
          }

          Column {
            id: homeColumn
            anchors.left: parent.left
            anchors.right: homeTime.visible ? homeTime.left : parent.right
            anchors.rightMargin: homeTime.visible ? Style.spacing.lg : 0
            anchors.top: parent.top
            spacing: Style.spacing.xs

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.home ? root.home.sentence : "Finding the sun..."
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              wrapMode: Text.WordWrap
            }
            Text {
              width: parent.width
              visible: root.scrubWords !== ""
              textFormat: Text.PlainText
              text: root.scrubWords + ". Press 0 to come back to now."
              color: root.sunColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              wrapMode: Text.WordWrap
            }
          }
        }

        Sky {
          id: homeSky
          anchors.top: homeHeader.bottom
          anchors.topMargin: content.gap
          width: parent.width
          height: content.homeSkyHeight
          isDay: root.home ? root.home.isDay : true
          t: root.home ? root.home.t : 0.5
          bodySize: Style.space(56)
        }

        // One card per person, side by side.
        Row {
          id: peopleRow
          anchors.top: homeSky.bottom
          anchors.topMargin: content.gap
          width: parent.width
          height: content.peopleHeight
          spacing: Style.spacing.lg
          readonly property int count: Math.max(1, root.rows.length)
          readonly property real cardW: (width - spacing * (count - 1)) / count

          Repeater {
            model: root.rows

            Rectangle {
              required property var modelData
              width: peopleRow.cardW
              height: peopleRow.height
              radius: root.cornerRadius
              color: Util.alpha(root.foreground, 0.04)
              border.width: Math.max(1, Style.space(1))
              border.color: Util.alpha(root.foreground, 0.12)

              Column {
                anchors.fill: parent
                anchors.margins: Style.spacing.lg
                spacing: Style.spacing.sm

                Row {
                  width: parent.width
                  spacing: Style.spacing.sm
                  Text {
                    width: parent.width - stateDot.width - Style.spacing.sm
                    textFormat: Text.PlainText
                    text: modelData.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                    font.bold: true
                    elide: Text.ElideRight
                  }
                  Rectangle {
                    id: stateDot
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(14)
                    height: width
                    radius: width / 2
                    color: modelData.call === "good" ? root.goodDot : (modelData.call === "busy" ? root.busyDot : root.asleepDot)
                    Behavior on color { ColorAnimation { duration: 400 } }
                  }
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: modelData.city + (modelData.timeText !== "" ? "  ·  " + modelData.timeText : "")
                    + (modelData.dayLabel !== "" && modelData.dayLabel !== "today" ? "  ·  " + modelData.dayLabel : "")
                  color: root.quiet
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  elide: Text.ElideRight
                }

                Sky {
                  width: parent.width
                  height: Math.max(Style.space(80), Math.round(peopleRow.height * 0.34))
                  isDay: modelData.isDay
                  t: modelData.t
                  bodySize: Style.space(30)
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: modelData.ready ? (modelData.awake ? "Awake" : "Asleep") : "..."
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: modelData.sentence
                  color: root.quiet
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                  maximumLineCount: 3
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  visible: modelData.ready
                  textFormat: Text.PlainText
                  text: modelData.callWords + (modelData.offsetWords !== "" ? "  ·  " + modelData.offsetWords : "")
                  color: modelData.call === "good" ? root.sunColor : root.quiet
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: modelData.call === "good"
                  elide: Text.ElideRight
                }
              }
            }
          }
        }

        Text {
          id: hint
          anchors.bottom: parent.bottom
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: "←  →  move the sun     0  now     Esc  close"
          color: Util.alpha(root.foreground, 0.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
