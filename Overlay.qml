import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The big clock. A fullscreen overlay on the menu surface tokens: home's sky
// across the top with the sun or the moon on its arc, an analog face beside
// the digits on the bands that read them, then a card for each person with
// their own small sky, what they are probably doing, and whether it is a
// good time to call. Left and right move the sun an hour; 0 comes back to
// now; Enter opens the set-the-clock game; Escape closes.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "ignibyte.kids-clock"

  // The shell assigns the plugin's own service here when it mounts the
  // overlay. `clock` falls back to a lookup for the moment before that lands.
  property var service: null
  readonly property var clock: service ? service
    : (shell && typeof shell.serviceFor === "function" ? shell.serviceFor(pluginId) : null)

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
  readonly property color dial: Util.alpha(foreground, 0.05)
  readonly property color goodDot: Color.accent
  readonly property color busyDot: Util.alpha(foreground, 0.45)
  readonly property color asleepDot: Util.alpha(foreground, 0.2)

  property int cardWidth: Math.min(Style.space(980), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)

  readonly property var home: clock ? clock.home : null
  readonly property var rows: clock ? clock.rows : []
  readonly property string scrubWords: clock ? clock.scrubWords : ""
  readonly property bool scrubbing: clock ? clock.scrubMinutes !== 0 : false
  readonly property var rules: clock ? clock.rules : Model.bandRules("explorer")
  readonly property bool hasFace: rules ? rules.face === true : false

  // ---- the set-the-clock game. One person at a time: their time is frozen
  // when the round starts, the hands begin at twelve, and the sun under the
  // face follows the hands until it sits in the ring where the real sun is.
  property bool playing: false
  property int roundIndex: 0
  property var currentRound: null
  property int hands: 0
  readonly property var game: playing && currentRound ? Model.gameView(currentRound, hands) : null
  readonly property bool solved: game ? game.solved : false
  readonly property string nextName: {
    if (!playing || !clock || !currentRound) return ""
    var ready = readyPeople()
    if (ready.length < 2) return currentRound.name
    var person = clock.people[ready[(roundIndex + 1) % ready.length]]
    return person ? person.name : currentRound.name
  }

  // Indexes into the service's people whose zone offset has arrived.
  function readyPeople() {
    var out = []
    if (!clock) return out
    var people = clock.people || []
    for (var i = 0; i < people.length; i++) {
      var info = clock.offsets ? clock.offsets[people[i].zone] : null
      if (info && info.offsetSeconds !== undefined) out.push(i)
    }
    return out
  }

  function beginRound(personIndex) {
    var person = clock.people[personIndex]
    currentRound = Model.gameRound(person, clock.offsets[person.zone], clock.nowMs, clock.routine, clock.rules, clock.hourFormat)
    hands = currentRound.startHands
  }

  function startGame() {
    if (!hasFace || !clock) return
    var ready = readyPeople()
    if (ready.length === 0) return
    clock.resetScrub()
    roundIndex = 0
    beginRound(ready[0])
    playing = true
  }

  function nextRound() {
    var ready = readyPeople()
    if (ready.length === 0) { stopGame(); return }
    roundIndex = (roundIndex + 1) % ready.length
    beginRound(ready[roundIndex])
  }

  function turn(deltaMinutes) {
    if (playing) hands = hands + deltaMinutes
  }

  function stopGame() {
    playing = false
    currentRound = null
  }

  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    root.stopGame()
    if (root.clock) root.clock.resetScrub()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // The sun or the moon travels a half ellipse from the left horizon to the
  // right; `t` is 0 at rising and 1 at setting. In the game a dashed ring
  // marks the goal, and fills when the body sits in it.
  component Sky: Item {
    id: sky
    property bool isDay: true
    property real t: 0.5
    property real bodySize: Style.space(40)
    property bool showGoal: false
    property bool goalIsDay: true
    property real goalT: 0.5
    property bool goalHit: false
    readonly property real horizonY: height * 0.86
    readonly property real radiusX: width / 2 - bodySize
    readonly property real radiusY: horizonY - bodySize * 0.9
    readonly property real angle: Math.PI * (1 - Math.max(0, Math.min(1, t)))
    readonly property real bodyX: width / 2 + radiusX * Math.cos(angle)
    readonly property real bodyY: horizonY - radiusY * Math.sin(angle)
    readonly property real goalAngle: Math.PI * (1 - Math.max(0, Math.min(1, goalT)))
    readonly property real goalX: width / 2 + radiusX * Math.cos(goalAngle)
    readonly property real goalY: horizonY - radiusY * Math.sin(goalAngle)

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

    // The goal ring, drawn above the body so the body shows inside it.
    Shape {
      id: goalRing
      visible: sky.showGoal
      readonly property real ringSize: sky.bodySize * 1.6
      readonly property real stroke: Math.max(2, Style.space(3))
      width: ringSize
      height: ringSize
      x: sky.goalX - width / 2
      y: sky.goalY - height / 2
      antialiasing: true
      layer.enabled: true
      layer.samples: 4
      ShapePath {
        strokeColor: sky.goalIsDay ? root.sunColor : root.moonColor
        strokeWidth: goalRing.stroke
        strokeStyle: sky.goalHit ? ShapePath.SolidLine : ShapePath.DashLine
        dashPattern: [3, 3]
        fillColor: sky.goalHit ? Util.alpha(root.sunColor, 0.22) : "transparent"
        PathAngleArc {
          centerX: goalRing.ringSize / 2
          centerY: goalRing.ringSize / 2
          radiusX: goalRing.ringSize / 2 - goalRing.stroke
          radiusY: goalRing.ringSize / 2 - goalRing.stroke
          startAngle: 0
          sweepAngle: 360
        }
      }
    }
  }

  // An analog face: a dial with sixty ticks and twelve numerals, a short
  // geared hour hand and a long minute hand, all plain items bound to the
  // theme so the face re-tints like the rest of the shell.
  component Face: Item {
    id: face
    property int minutesOfDay: 0
    property bool solved: false
    readonly property real r: Math.min(width, height) / 2
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real rim: Math.max(2, Style.space(3))
    readonly property real tickInset: rim + r * 0.03
    readonly property real hourLength: r * 0.52
    readonly property real minuteLength: r * 0.78
    readonly property var angles: Model.handAngles(minutesOfDay)

    Rectangle {
      x: face.cx - face.r
      y: face.cy - face.r
      width: face.r * 2
      height: width
      radius: width / 2
      color: root.dial
      border.width: face.rim
      border.color: face.solved ? root.sunColor : root.horizon
      Behavior on border.color { ColorAnimation { duration: 300 } }
    }

    Repeater {
      model: 60
      Rectangle {
        required property int index
        readonly property bool hourTick: index % 5 === 0
        width: hourTick ? Math.max(2, face.r * 0.03) : Math.max(1, face.r * 0.012)
        height: hourTick ? face.r * 0.09 : face.r * 0.05
        radius: width / 2
        color: Util.alpha(root.foreground, hourTick ? 0.8 : 0.3)
        x: face.cx - width / 2
        y: face.cy - face.r + face.tickInset
        transform: Rotation {
          origin.x: width / 2
          origin.y: face.r - face.tickInset
          angle: index * 6
        }
      }
    }

    Repeater {
      model: 12
      Text {
        required property int index
        readonly property int numeral: index + 1
        readonly property real theta: numeral * Math.PI / 6
        x: face.cx + Math.sin(theta) * face.r * 0.74 - width / 2
        y: face.cy - Math.cos(theta) * face.r * 0.74 - height / 2
        textFormat: Text.PlainText
        text: numeral
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Math.max(Style.font.body, Math.round(face.r * 0.17))
        font.bold: true
      }
    }

    Rectangle {
      id: hourHand
      width: Math.max(4, face.r * 0.08)
      height: face.hourLength + width
      radius: width / 2
      color: root.foreground
      x: face.cx - width / 2
      y: face.cy - face.hourLength
      transform: Rotation {
        origin.x: hourHand.width / 2
        origin.y: face.hourLength
        angle: face.angles.hour
        Behavior on angle { RotationAnimation { direction: RotationAnimation.Shortest; duration: 320; easing.type: Easing.OutCubic } }
      }
    }

    Rectangle {
      id: minuteHand
      width: Math.max(3, face.r * 0.055)
      height: face.minuteLength + width
      radius: width / 2
      color: root.foreground
      x: face.cx - width / 2
      y: face.cy - face.minuteLength
      transform: Rotation {
        origin.x: minuteHand.width / 2
        origin.y: face.minuteLength
        angle: face.angles.minute
        Behavior on angle { RotationAnimation { direction: RotationAnimation.Shortest; duration: 320; easing.type: Easing.OutCubic } }
      }
    }

    Rectangle {
      width: Math.max(6, face.r * 0.11)
      height: width
      radius: width / 2
      color: root.sunColor
      x: face.cx - width / 2
      y: face.cy - height / 2
    }
  }

  // A big round button for turning the hands with the mouse or a finger.
  component TurnButton: Column {
    id: turnButton
    property string glyph: "›"
    property string caption: ""
    property int delta: 5
    spacing: Style.spacing.xs

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Style.space(60)
      height: width
      radius: width / 2
      color: Util.alpha(root.foreground, turnPress.pressed ? 0.18 : (turnPress.containsMouse ? 0.12 : 0.07))
      border.width: Math.max(1, Style.space(1))
      border.color: Util.alpha(root.foreground, 0.2)
      Behavior on color { ColorAnimation { duration: 120 } }

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: turnButton.glyph
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.displayLarge
        font.bold: true
      }

      MouseArea {
        id: turnPress
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.turn(turnButton.delta)
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: turnButton.caption
      color: root.quiet
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
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
          var shift = (event.modifiers & Qt.ShiftModifier) !== 0
          if (event.key === Qt.Key_Escape) {
            if (root.playing) root.stopGame()
            else if (root.scrubbing && root.clock) root.clock.resetScrub()
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Left) {
            var sign = event.key === Qt.Key_Right ? 1 : -1
            if (root.playing) root.turn(sign * (shift ? 1 : 5))
            else if (root.clock) root.clock.scrub(sign * (shift ? 15 : 60))
            event.accepted = true
          } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            if (root.playing) {
              root.turn(event.key === Qt.Key_Up ? 60 : -60)
              event.accepted = true
            }
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.playing) {
              if (root.solved) root.nextRound()
            } else {
              root.startGame()
            }
            event.accepted = true
          } else if (event.key === Qt.Key_0 || event.key === Qt.Key_Home || event.key === Qt.Key_Space) {
            if (root.playing) {
              if (root.solved && event.key === Qt.Key_Space) root.nextRound()
              else if (root.currentRound) root.hands = root.currentRound.startHands
            } else if (root.clock) {
              root.clock.resetScrub()
            }
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
        readonly property int homeSkyHeight: Math.round(root.cardHeight * (root.hasFace ? 0.30 : 0.26))

        // ---- the clock
        Item {
          id: clockView
          visible: !root.playing
          anchors.fill: parent
          anchors.bottomMargin: hint.height + content.gap

          // Home: the sentence, the digits when the band allows them, the
          // sky, and on the bands that read digits an analog face at the
          // right spanning the header and the sky.
          Item {
            id: homeArea
            width: parent.width
            height: homeHeader.height + content.gap + content.homeSkyHeight

            Face {
              id: homeFace
              visible: root.hasFace
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: visible ? height : 0
              minutesOfDay: root.home ? root.home.minutesOfDay : 0

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.startGame()
              }
            }

            // Anchors rather than a Row: the digits sit on the right at
            // their own width and the sentence wraps into whatever is left.
            Item {
              id: homeHeader
              anchors.left: parent.left
              anchors.right: homeFace.visible ? homeFace.left : parent.right
              anchors.rightMargin: homeFace.visible ? content.gap * 2 : 0
              anchors.top: parent.top
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
              anchors.left: parent.left
              anchors.right: homeFace.visible ? homeFace.left : parent.right
              anchors.rightMargin: homeFace.visible ? content.gap * 2 : 0
              height: content.homeSkyHeight
              isDay: root.home ? root.home.isDay : true
              t: root.home ? root.home.t : 0.5
              bodySize: Style.space(56)
            }
          }

          // One card per person, side by side.
          Row {
            id: peopleRow
            anchors.top: homeArea.bottom
            anchors.topMargin: content.gap
            anchors.bottom: parent.bottom
            width: parent.width
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
        }

        // ---- the game: the face on the left, the words and the sky on the
        // right, and four big buttons for anyone not on the keyboard.
        Item {
          id: gameArea
          visible: root.playing
          anchors.fill: parent
          anchors.bottomMargin: hint.height + content.gap
          readonly property int faceSize: Math.min(height, Math.round(width * 0.46))

          Face {
            id: gameFace
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: gameArea.faceSize
            height: width
            minutesOfDay: root.game ? root.game.minutesOfDay : 0
            solved: root.solved
          }

          Column {
            id: gameColumn
            anchors.left: gameFace.right
            anchors.leftMargin: content.gap * 3
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Style.spacing.md

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.currentRound ? root.currentRound.name + "'s clock in " + root.currentRound.city : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.currentRound ? root.currentRound.prompt : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              visible: text !== ""
              textFormat: Text.PlainText
              text: root.currentRound ? root.currentRound.targetDigits : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              font.bold: true
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.currentRound ? (root.solved ? root.currentRound.solvedSentence : root.currentRound.task) : ""
              color: root.solved ? root.sunColor : root.quiet
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              wrapMode: Text.WordWrap
              Behavior on color { ColorAnimation { duration: 300 } }
            }

            Sky {
              id: gameSky
              width: parent.width
              height: Math.round(gameArea.height * 0.36)
              isDay: root.game ? root.game.isDay : true
              t: root.game ? root.game.t : 0.5
              bodySize: Style.space(40)
              showGoal: true
              goalIsDay: root.currentRound ? root.currentRound.goalIsDay : true
              goalT: root.currentRound ? root.currentRound.goalT : 0.5
              goalHit: root.solved
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: !root.game ? ""
                : (root.solved
                  ? (root.nextName === root.currentRound.name ? "Press Enter to play again." : "Press Enter for " + root.nextName + "'s clock.")
                  : root.game.hint)
              color: root.solved ? root.sunColor : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              wrapMode: Text.WordWrap
            }

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.spacing.xl
              TurnButton { glyph: "«"; caption: "an hour"; delta: -60 }
              TurnButton { glyph: "‹"; caption: "5 minutes"; delta: -5 }
              TurnButton { glyph: "›"; caption: "5 minutes"; delta: 5 }
              TurnButton { glyph: "»"; caption: "an hour"; delta: 60 }
            }
          }
        }

        Text {
          id: hint
          anchors.bottom: parent.bottom
          anchors.right: parent.right
          textFormat: Text.PlainText
          text: root.playing
            ? "←  →  five minutes     ↑  ↓  an hour     Enter  next     Esc  back to the clock"
            : (root.hasFace
              ? "←  →  move the sun     Enter  set the clock     0  now     Esc  close"
              : "←  →  move the sun     0  now     Esc  close")
          color: Util.alpha(root.foreground, 0.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
