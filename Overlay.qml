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
// good time to call. A row of buttons along the bottom does everything:
// Earlier and Later move the sun an hour, Back to now undoes that, Play
// opens the game, Map swaps in the world with its night side on the band
// that reads maps, Globe shows a globe to turn with well-known places to
// tap for the time there, People opens the screen where a parent adds and
// removes the people shown, and Close closes. The keys do the same for anyone
// at a keyboard: arrows, 0, Enter, M, G, P and Escape.
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
  // The big clock takes the keyboard while it is up. A harness, or a kiosk
  // that drives it by pointer alone, can switch that off before opening it.
  property bool takesKeyboard: true

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
  // A near-black background has no darker to go, so on a dark theme day is
  // lifted and night sits a shade above the card; a light theme darkens.
  readonly property bool darkTheme: background.hsvValue < 0.5
  readonly property color daySky: Util.alpha(foreground, darkTheme ? 0.14 : 0.07)
  readonly property color nightSky: darkTheme ? Util.alpha(foreground, 0.06) : Util.alpha(Qt.darker(background, 1.6), 0.55)
  readonly property color horizon: Util.alpha(foreground, 0.35)
  readonly property color quiet: Util.alpha(foreground, 0.75)
  readonly property color dial: Util.alpha(foreground, 0.05)
  readonly property color landColor: Util.alpha(foreground, 0.30)
  readonly property color nightShade: darkTheme ? Util.alpha(background, 0.7) : Util.alpha(Qt.darker(background, 1.8), 0.6)
  readonly property color goodDot: Color.accent
  readonly property color busyDot: Util.alpha(foreground, 0.45)
  readonly property color asleepDot: Util.alpha(foreground, 0.2)

  property int cardWidth: Math.min(Style.space(980), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)

  readonly property var home: clock ? clock.home : null
  readonly property var rows: clock ? clock.rows : []
  // What a card shows for the instant between the list shrinking and the
  // delegate going: nothing, rather than undefined.
  readonly property var emptyRow: ({ name: "", city: "", zone: "", ready: false, isDay: true, t: 0.5, sentence: "",
    call: "good", callWords: "", timeText: "", dayLabel: "", offsetWords: "", awake: false })
  readonly property var emptyEntry: ({ kind: "person", name: "", place: "", time: "" })
  readonly property string scrubWords: clock ? clock.scrubWords : ""
  readonly property bool scrubbing: clock ? clock.scrubMinutes !== 0 : false
  readonly property var rules: clock ? clock.rules : Model.bandRules("explorer")
  readonly property bool hasFace: rules ? rules.face === true : false
  readonly property bool hasMap: rules ? rules.map === true : false

  // ---- the map: the night side and the overhead sun at the shown instant,
  // computed only while the map is up.
  property bool showMap: false
  readonly property double shownMs: clock ? clock.shownMs : Date.now()
  readonly property var land: clock ? clock.land : []
  readonly property var sun: showMap ? Model.subsolarPoint(shownMs) : null
  readonly property var night: showMap ? Model.nightPolygon(shownMs, 2) : []
  readonly property var markers: showMap && clock && home
    ? Model.mapMarkers(home, clock.homeCity ? clock.homeCity.lat : null, clock.homeCity ? clock.homeCity.lon : null, clock.people, rows)
    : []

  // ---- people: the parent's screen. The list is home, everyone stored in
  // the setting (placed or not), and "Add someone". Adding asks two
  // questions, a name and a place found by typing; removing asks once.
  // Everything is saved to the plugin's own entry in shell.json through the
  // shell, the way the built-in panels save theirs.
  // ---- the globe: where it is turned to, and the tapped place.
  property bool showGlobe: false
  property real globeLat: 25
  property real globeLon: -90
  Behavior on globeLon { enabled: !root.globeDragging; NumberAnimation { id: lonSpin; duration: 500; easing.type: Easing.OutCubic } }
  Behavior on globeLat { enabled: !root.globeDragging; NumberAnimation { id: latSpin; duration: 500; easing.type: Easing.OutCubic } }
  property bool globeDragging: false
  property int pickedSpot: -1
  property bool globeAtHome: false
  readonly property var globeDots: clock ? clock.globeDots : []
  readonly property var popular: Model.popularSpots(cities)
  readonly property var spots: clock ? Model.globeSpotList(clock.homeName, clock.homeCity, clock.people, popular) : []
  readonly property var picked: pickedSpot >= 0 && pickedSpot < spots.length ? spots[pickedSpot] : null
  readonly property var pickedOffset: !picked || !clock ? null
    : (picked.kind === "home" ? { offsetSeconds: clock.homeOffsetSeconds } : (clock.offsets ? clock.offsets[picked.zone] : null))
  readonly property var pickedView: picked && clock
    ? Model.spotView(picked, pickedOffset, shownMs, home, clock.routine, rules, clock.hourFormat)
    : null

  // Opened before the city list or the home zone has loaded, the globe has
  // no home to centre on; when home turns up it goes there and picks it.
  onSpotsChanged: {
    if (!showGlobe || globeAtHome || spots.length === 0 || spots[0].kind !== "home") return
    var wasDragging = globeDragging
    globeDragging = true
    centreGlobeOnHome()
    globeDragging = wasDragging
    pickedSpot = 0
    if (clock && typeof clock.requestZones === "function") clock.requestZones(spotZones())
  }

  function spotZones() {
    var zones = []
    for (var i = 0; i < spots.length; i++) zones.push(spots[i].zone)
    return zones
  }

  function centreGlobeOnHome() {
    var homeCity = clock ? clock.homeCity : null
    globeLat = homeCity ? Math.max(-45, Math.min(45, homeCity.lat)) : 25
    globeLon = homeCity ? homeCity.lon : -90
    globeAtHome = !!homeCity
  }

  function openGlobe() {
    if (playing) return
    showMap = false
    showPeople = false
    globeDragging = true
    centreGlobeOnHome()
    globeDragging = false
    pickedSpot = spots.length > 0 ? 0 : -1
    showGlobe = true
    if (clock && typeof clock.requestZones === "function") clock.requestZones(spotZones())
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function closeGlobe() {
    showGlobe = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function spinGlobe(deltaDegrees) { globeLon = globeLon + deltaDegrees }

  function pickSpot(index) { pickedSpot = index }

  function pickSpotNamed(name) {
    for (var i = 0; i < spots.length; i++) {
      if (spots[i].place === name || spots[i].name === name) { pickedSpot = i; return true }
    }
    return false
  }

  property bool showPeople: false
  property string peopleMode: "list"   // list, name, place, remove
  property int peopleIndex: 1
  property string placeFor: "person"   // person or home
  property string draftName: ""
  property string draftWhere: ""
  property int matchIndex: 0
  readonly property int mostPeople: 8
  readonly property var cities: clock ? clock.cities : []
  readonly property var storedPeople: clock ? Model.parsePeopleRaw(clock.peopleText) : []
  readonly property var matches: peopleMode === "place" ? Model.searchCities(cities, draftWhere, 6) : []
  // What Save can do with what has been typed: the cities that match, and
  // then the typed text itself. Home is a label, so anything goes there and
  // the clock stays on the computer's time zone. A person needs a zone the
  // computer knows, so only a written-out zone is offered.
  readonly property var placeOptions: {
    var out = []
    for (var i = 0; i < matches.length; i++)
      out.push({ label: matches[i].label, hint: matches[i].city.zone, key: matches[i].key })
    var typed = draftWhere.trim()
    if (typed === "" || peopleMode !== "place") return out
    if (placeFor === "home") out.push({ label: "Use \u201c" + typed + "\u201d", hint: "as it is typed", key: typed })
    else if (Model.isZone(typed)) out.push({ label: typed, hint: "a time zone", key: typed })
    return out
  }
  onPlaceOptionsChanged: matchIndex = 0
  readonly property var peopleEntries: {
    var out = []
    var homeSet = clock ? clock.homeCitySetting !== "" : false
    out.push({ kind: "home", name: "Home", time: home ? home.timeText : "",
      place: clock ? clock.homeName + (homeSet ? "" : "  ·  from the computer's time zone") : "" })
    for (var i = 0; i < storedPeople.length; i++) {
      var entry = storedPeople[i]
      var city = Model.findCity(cities, entry.where)
      var place = city ? Model.cityLabel(city, cities)
        : (entry.where.indexOf("/") !== -1 ? entry.where.split("/").pop().replace(/_/g, " ") : entry.where + "  ·  not found")
      var time = ""
      for (var r = 0; r < rows.length; r++) {
        if (rows[r].name === entry.name && rows[r].ready) { time = rows[r].timeText; break }
      }
      out.push({ kind: "person", name: entry.name, place: place, time: time })
    }
    var cap = rules ? rules.maxPeople : 3
    out.push({ kind: "add", time: "",
      name: storedPeople.length >= mostPeople ? "That is plenty of people" : "Add someone",
      place: storedPeople.length > cap ? "this face shows the first " + cap : "" })
    return out
  }
  readonly property string editPrompt: peopleMode === "name" ? "What do you call them?"
    : (placeFor === "home" ? "Where are we?" : "Where does " + draftName + " live?")
  readonly property string editHint: peopleMode === "name"
    ? "The name the child uses."
    : (placeFor === "home"
      ? "Type anything: a town, a street, whatever we call the house. Home's clock always follows the computer's own time zone; picking a place from the list also puts home on the map and the globe."
      : "Type a few letters and pick the place. If it is not here, try the nearest big city, or a time zone such as America/Phoenix.")

  // Save some settings onto the plugin's entry, keeping the rest.
  function persistSettings(values) {
    if (!clock || !values || typeof values !== "object" || Array.isArray(values)) return false
    var entry = { id: pluginId }
    var current = clock.config || {}
    for (var k in current) if (k !== "id") entry[k] = current[k]
    for (var v in values) entry[v] = values[v]
    if (shell && typeof shell.updateEntryInline === "function") return shell.updateEntryInline(pluginId, entry)
    console.warn("kids-clock: the shell cannot save settings here")
    return false
  }

  function openPeople() {
    if (playing) return
    showMap = false
    showGlobe = false
    peopleMode = "list"
    peopleIndex = storedPeople.length > 0 ? 1 : 0
    showPeople = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function closePeople() {
    showPeople = false
    peopleMode = "list"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function focusEditField() {
    Qt.callLater(function() { editField.forceActiveFocus(); editField.cursorPosition = editField.text.length })
  }

  function beginAdd() {
    if (storedPeople.length >= mostPeople) return
    placeFor = "person"
    draftName = ""
    draftWhere = ""
    peopleMode = "name"
    focusEditField()
  }

  function acceptName() {
    if (draftName.trim() === "") return
    draftName = draftName.trim()
    draftWhere = ""
    peopleMode = "place"
    focusEditField()
  }

  function beginHome() {
    placeFor = "home"
    draftWhere = ""
    peopleMode = "place"
    focusEditField()
  }

  function backToList() {
    peopleMode = "list"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function editBack() {
    if (peopleMode === "place" && placeFor === "person") { peopleMode = "name"; focusEditField() }
    else backToList()
  }

  function savePlace(whereKey) {
    if (!clock) return
    if (placeFor === "home") persistSettings({ homeCity: whereKey })
    else persistSettings({ people: Model.addPerson(clock.peopleText, draftName, whereKey) })
    backToList()
    Qt.callLater(function() { peopleIndex = placeFor === "home" ? 0 : Math.max(1, storedPeople.length) })
  }

  function pickMatch(index) {
    var option = placeOptions[index]
    if (option) savePlace(option.key)
  }

  function editAccept() {
    if (peopleMode === "name") { acceptName(); return }
    pickMatch(matchIndex)
  }

  // Straight from a name and a place, for a script or a test.
  function addPerson(name, where) {
    if (!clock || typeof name !== "string" || typeof where !== "string") return false
    return persistSettings({ people: Model.addPerson(clock.peopleText, name, where) })
  }

  function activateRow(index) {
    peopleIndex = index
    if (index === 0) beginHome()
    else if (index === peopleEntries.length - 1) beginAdd()
  }

  function askRemove() {
    if (peopleIndex === 0) {
      if (clock && clock.homeCitySetting !== "") persistSettings({ homeCity: "" })
    } else if (peopleIndex >= 1 && peopleIndex <= storedPeople.length) {
      peopleMode = "remove"
    }
  }

  function askRemoveAt(index) {
    peopleIndex = index
    askRemove()
  }

  function confirmRemove() {
    if (peopleMode !== "remove") return
    persistSettings({ people: Model.removePerson(clock.peopleText, peopleIndex - 1) })
    peopleMode = "list"
    Qt.callLater(function() { peopleIndex = Math.min(peopleIndex, Math.max(0, storedPeople.length)) })
  }

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
    if (!playing || !currentRound) return ""
    if (players.length < 2) return currentRound.name
    var player = players[(roundIndex + 1) % players.length]
    return player ? player.person.name : currentRound.name
  }

  // Home shaped like a person, so there is always a clock to play against.
  // The offset is the computer's own, which is the only one home's clock ever
  // runs on; `self` puts the round in the second person.
  readonly property var homePlayer: !clock ? null
    : ({ person: { name: clock.homeName, city: clock.homeName, zone: clock.homeZone,
                   lat: clock.homeCity ? clock.homeCity.lat : null,
                   lon: clock.homeCity ? clock.homeCity.lon : null, self: true },
         offset: { offsetSeconds: clock.homeOffsetSeconds } })

  // Who the game asks about: everyone whose zone offset has arrived, and home
  // alone when nobody has been added yet.
  readonly property var players: {
    var out = []
    if (!clock) return out
    var people = clock.people || []
    for (var i = 0; i < people.length; i++) {
      var info = clock.offsets ? clock.offsets[people[i].zone] : null
      if (info && info.offsetSeconds !== undefined) out.push({ person: people[i], offset: info })
    }
    if (out.length === 0 && homePlayer) out.push(homePlayer)
    return out
  }

  function beginRound(index) {
    var player = players[index]
    if (!player) return
    currentRound = Model.gameRound(player.person, player.offset, clock.nowMs, clock.routine, clock.rules, clock.hourFormat)
    hands = currentRound.startHands
  }

  function startGame() {
    if (!hasFace || !clock || players.length === 0) return
    clock.resetScrub()
    showMap = false
    showGlobe = false
    showPeople = false
    roundIndex = 0
    beginRound(0)
    playing = true
  }

  function nextRound() {
    if (players.length === 0) { stopGame(); return }
    roundIndex = (roundIndex + 1) % players.length
    beginRound(roundIndex)
  }

  function turn(deltaMinutes) {
    if (playing) hands = hands + deltaMinutes
  }

  function stopGame() {
    playing = false
    currentRound = null
  }

  // The payload may name a view: {"view": "map"}, "game" or "clock".
  function open(payloadJson) {
    root.opened = true
    var payload = null
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = null }
    var view = payload && payload.view ? String(payload.view) : ""
    if (view === "map") root.showMap = root.hasMap
    else if (view === "clock") { root.showMap = false; root.showPeople = false }
    else if (view === "game") root.startGame()
    else if (view === "people") root.openPeople()
    else if (view === "globe") root.openGlobe()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // Every way out lands on the clock next time: the shell's own hide (the
  // bar chip, a keybinding built on toggle) as much as Escape or Close.
  function resetViews() {
    root.stopGame()
    root.showMap = false
    root.showPeople = false
    root.showGlobe = false
    root.peopleMode = "list"
    if (root.clock) root.clock.resetScrub()
  }

  function close() {
    root.opened = false
    root.resetViews()
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle(payloadJson) {
    if (root.opened) root.dismiss()
    else root.open(payloadJson || "{}")
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
      Behavior on color { ColorAnimation { duration: 160 } }
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

      Moon {
        visible: !sky.isDay
        anchors.fill: parent
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

  // The moon: a crescent. The outer edge is the left half of the disc, the
  // inner edge a shallower arc back up, so the fill between them is the lit
  // sliver and whatever is behind shows through the rest.
  component Moon: Shape {
    id: moon
    antialiasing: true
    layer.enabled: true
    layer.samples: 4
    ShapePath {
      fillColor: root.moonColor
      strokeWidth: 0
      strokeColor: "transparent"
      startX: moon.width * 0.5
      startY: 0
      PathArc {
        x: moon.width * 0.5
        y: moon.height
        radiusX: moon.width / 2
        radiusY: moon.height / 2
        direction: PathArc.Counterclockwise
      }
      PathArc {
        x: moon.width * 0.5
        y: 0
        radiusX: moon.width * 0.62
        radiusY: moon.height * 0.62
        direction: PathArc.Clockwise
      }
    }
  }

  // The world in plate carrée: the land from Natural Earth, the night side
  // as one shaded polygon that sweeps west as the shown instant moves, a
  // sun where it is overhead, a moon where it is midnight, and a dot for
  // home and for each person with a place.
  component WorldMap: Item {
    id: map
    property var land: []
    property var night: []
    property var sun: null
    property var markers: []
    clip: true
    readonly property string landPath: Model.landPath(land, width, height)
    readonly property string nightPath: Model.pointsPath(night, width, height)
    readonly property var sunPos: sun ? Model.mapPoint(sun.lon, sun.lat, width, height) : [-100, -100]
    readonly property var moonPos: sun ? Model.mapPoint(((sun.lon + 360) % 360) - 180, -sun.lat, width, height) : [-100, -100]

    Rectangle {
      anchors.fill: parent
      radius: root.cornerRadius
      color: root.daySky
    }

    Shape {
      anchors.fill: parent
      antialiasing: true
      layer.enabled: true
      layer.samples: 4
      ShapePath {
        fillColor: root.landColor
        fillRule: ShapePath.OddEvenFill
        strokeWidth: 0
        strokeColor: "transparent"
        PathSvg { path: map.landPath }
      }
    }

    Shape {
      anchors.fill: parent
      antialiasing: true
      layer.enabled: true
      layer.samples: 4
      ShapePath {
        fillColor: root.nightShade
        strokeWidth: 0
        strokeColor: "transparent"
        PathSvg { path: map.nightPath }
      }
    }

    Rectangle {
      visible: !!map.sun
      width: Style.space(18)
      height: width
      radius: width / 2
      color: root.sunColor
      x: map.sunPos[0] - width / 2
      y: map.sunPos[1] - height / 2
      Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
      Behavior on y { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    }

    Moon {
      visible: !!map.sun
      width: Style.space(16)
      height: width
      x: map.moonPos[0] - width / 2
      y: map.moonPos[1] - height / 2
      Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
      Behavior on y { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
    }

    Repeater {
      model: map.markers
      Item {
        id: marker
        required property var modelData
        readonly property var pos: Model.mapPoint(modelData.lon, modelData.lat, map.width, map.height)
        readonly property bool flip: pos[0] + labelBox.width + Style.space(24) > map.width
        x: pos[0]
        y: pos[1]

        Rectangle {
          id: markerDot
          width: Style.space(modelData.home ? 16 : 12)
          height: width
          radius: width / 2
          x: -width / 2
          y: -height / 2
          color: modelData.home ? "transparent" : root.sunColor
          border.width: modelData.home ? Math.max(2, Style.space(3)) : 0
          border.color: root.foreground
        }

        Rectangle {
          id: labelBox
          x: marker.flip ? -width - Style.space(12) : Style.space(12)
          y: -height / 2
          width: labelRow.implicitWidth + Style.space(12)
          height: labelRow.implicitHeight + Style.space(6)
          radius: Math.max(2, root.cornerRadius / 2)
          color: Util.alpha(root.background, 0.72)

          Row {
            id: labelRow
            anchors.centerIn: parent
            spacing: Style.spacing.sm
            Text {
              textFormat: Text.PlainText
              text: marker.modelData.name
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              visible: text !== ""
              textFormat: Text.PlainText
              text: marker.modelData.label
              color: root.quiet
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
            }
          }
        }
      }
    }
  }

  // The home header: the sentence, the digits when the band allows them,
  // and the scrub banner. Anchors rather than a Row: the digits sit on the
  // right at their own width and the sentence wraps into whatever is left.
  component HomeHeader: Item {
    id: header
    height: Math.max(headerColumn.implicitHeight, headerTime.implicitHeight)

    Text {
      id: headerTime
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
      id: headerColumn
      anchors.left: parent.left
      anchors.right: headerTime.visible ? headerTime.left : parent.right
      anchors.rightMargin: headerTime.visible ? Style.spacing.lg : 0
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
        text: root.scrubWords + "."
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        wrapMode: Text.WordWrap
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
    property bool spins: false
    spacing: Style.spacing.xs

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Style.space(60)
      height: width
      radius: width / 2
      color: turnPress.pressed ? Style.pressedFillFor(root.foreground, root.sunColor)
        : (turnPress.containsMouse ? Style.hoverFillFor(root.foreground, root.sunColor) : Util.alpha(root.foreground, 0.07))
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
        onClicked: turnButton.spins ? root.spinGlobe(turnButton.delta) : root.turn(turnButton.delta)
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: turnButton.caption
      color: root.quiet
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  // The globe: an orthographic view drawn as dots, the night shaded, the sun
  // where it is overhead, and a marker for home, each person and the popular
  // places. Dragging turns it; tapping a marker picks that place.
  component Globe: Item {
    id: globe
    property real lat0: 0
    property real lon0: 0
    property var dots: []
    property var spots: []
    property int picked: -1
    signal spotPicked(int index)
    signal turned(real dLat, real dLon)
    signal dragChanged(bool dragging)
    readonly property real r: Math.min(width, height) / 2 - Style.space(8)
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property string dotsPath: Model.globeDotsPath(dots, lat0, lon0, r, cx, cy, Math.max(2, r * 0.017))
    readonly property string nightPath: Model.globeNightPath(root.shownMs, lat0, lon0, r, cx, cy, 48)
    readonly property var basis: Model.globeBasis(lat0, lon0)
    readonly property var sunSpot: {
      var sun = Model.subsolarPoint(root.shownMs)
      return Model.globeProject(sun.lat, sun.lon, Model.globeBasis(lat0, lon0), r, cx, cy)
    }

    Rectangle {
      x: globe.cx - globe.r
      y: globe.cy - globe.r
      width: globe.r * 2
      height: width
      radius: width / 2
      color: root.daySky
      border.width: Math.max(1, Style.space(1))
      border.color: Util.alpha(root.foreground, 0.2)
    }

    Shape {
      anchors.fill: parent
      antialiasing: true
      layer.enabled: true
      layer.samples: 4
      ShapePath {
        fillColor: root.landColor
        strokeWidth: 0
        strokeColor: "transparent"
        PathSvg { path: globe.dotsPath }
      }
    }

    Shape {
      anchors.fill: parent
      antialiasing: true
      layer.enabled: true
      layer.samples: 4
      ShapePath {
        fillColor: root.nightShade
        strokeWidth: 0
        strokeColor: "transparent"
        PathSvg { path: globe.nightPath }
      }
    }

    Rectangle {
      visible: globe.sunSpot.depth > 0
      width: Style.space(26 + 14 * Math.max(0, globe.sunSpot.depth))
      height: width
      radius: width / 2
      color: Util.alpha(root.sunColor, 0.25)
      x: globe.sunSpot.x - width / 2
      y: globe.sunSpot.y - height / 2
    }

    Rectangle {
      visible: globe.sunSpot.depth > 0
      width: Style.space(12 + 8 * Math.max(0, globe.sunSpot.depth))
      height: width
      radius: width / 2
      color: root.sunColor
      x: globe.sunSpot.x - width / 2
      y: globe.sunSpot.y - height / 2
    }

    MouseArea {
      id: dragArea
      anchors.fill: parent
      cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
      property real lastX: 0
      property real lastY: 0
      onPressed: function(mouse) { lastX = mouse.x; lastY = mouse.y }
      onPressedChanged: globe.dragChanged(pressed)
      onPositionChanged: function(mouse) {
        if (!pressed) return
        var perPixel = 60 / Math.max(1, globe.r)
        globe.turned((mouse.y - lastY) * perPixel, -(mouse.x - lastX) * perPixel)
        lastX = mouse.x
        lastY = mouse.y
      }
    }

    // One delegate per place for the life of the view: it projects itself
    // as the globe turns, hides round the back, and stacks by depth, so a
    // spin never tears the markers down or drops a hover.
    Repeater {
      model: globe.spots.length

      Item {
        id: marker
        required property int index
        readonly property var spot: globe.spots[index] || ({ kind: "spot", name: "", place: "", lat: 0, lon: 0 })
        readonly property var at: Model.globeProject(spot.lat, spot.lon, globe.basis, globe.r, globe.cx, globe.cy)
        readonly property real depth: at.depth
        visible: depth > 0.04
        z: depth
        readonly property bool isPicked: globe.picked === index
        readonly property bool named: spot.kind !== "spot"
        readonly property real dotSize: Style.space((spot.kind === "spot" ? 9 : 12) + 5 * Math.max(0, depth) + (isPicked ? 4 : 0))
        readonly property bool flip: at.x > globe.width * 0.62
        x: at.x
        y: at.y

        Rectangle {
          visible: marker.isPicked
          width: marker.dotSize + Style.space(12)
          height: width
          radius: width / 2
          x: -width / 2
          y: -height / 2
          color: "transparent"
          border.width: Math.max(2, Style.space(2))
          border.color: root.sunColor
        }

        Rectangle {
          width: marker.dotSize
          height: width
          radius: width / 2
          x: -width / 2
          y: -height / 2
          color: marker.spot.kind === "home" ? "transparent" : (marker.spot.kind === "person" ? root.sunColor : Util.alpha(root.foreground, 0.85))
          border.width: marker.spot.kind === "home" ? Math.max(2, Style.space(3)) : 0
          border.color: root.foreground
        }

        MouseArea {
          id: markerArea
          anchors.centerIn: parent
          width: Math.max(marker.dotSize, Style.space(40))
          height: width
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: globe.spotPicked(marker.index)
        }

        Rectangle {
          visible: marker.named || marker.isPicked || markerArea.containsMouse
          x: marker.flip ? -width - Style.space(10) : Style.space(10)
          y: -height / 2
          width: markerLabel.implicitWidth + Style.space(12)
          height: markerLabel.implicitHeight + Style.space(6)
          radius: Math.max(2, root.cornerRadius / 2)
          color: Util.alpha(root.background, 0.78)
          Text {
            id: markerLabel
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: marker.spot.kind === "person" ? marker.spot.name : marker.spot.place
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: marker.named || marker.isPicked
          }
        }
      }
    }
  }

  // A kit button with room for small hands: the shell's own Button on the
  // menu tokens, so hover, press and the emphasised state follow the theme.
  // `primary` paints the one thing to press next in the kit's selected state.
  component ActionButton: Button {
    property bool primary: false
    property bool compact: false
    bordered: true
    selected: primary
    foreground: root.foreground
    fontFamily: root.fontFamily
    fontSize: compact ? Style.font.body : Style.font.title
    horizontalPadding: compact ? Style.spacing.xl : Style.space(18)
    verticalPadding: compact ? Style.spacing.md : Style.space(10)
    opacity: enabled ? 1 : 0.4
    Behavior on opacity { NumberAnimation { duration: 120 } }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "kids-clock"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.takesKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
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
          if (root.showPeople) {
            if (event.key === Qt.Key_Escape) {
              if (root.peopleMode === "remove") root.peopleMode = "list"
              else root.closePeople()
            } else if (event.key === Qt.Key_P && root.peopleMode === "list") {
              root.closePeople()
            } else if (event.key === Qt.Key_Down && root.peopleMode === "list") {
              root.peopleIndex = Math.min(root.peopleEntries.length - 1, root.peopleIndex + 1)
            } else if (event.key === Qt.Key_Up && root.peopleMode === "list") {
              root.peopleIndex = Math.max(0, root.peopleIndex - 1)
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              if (root.peopleMode === "remove") root.confirmRemove()
              else root.activateRow(root.peopleIndex)
            } else if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && root.peopleMode === "list") {
              root.askRemove()
            }
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Escape) {
            if (root.playing) root.stopGame()
            else if (root.scrubbing && root.clock) root.clock.resetScrub()
            else if (root.showGlobe) root.closeGlobe()
            else if (root.showMap) root.showMap = false
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_M) {
            if (root.hasMap && !root.playing) { root.showGlobe = false; root.showMap = !root.showMap }
            event.accepted = true
          } else if (event.key === Qt.Key_G) {
            if (!root.playing) { if (root.showGlobe) root.closeGlobe(); else root.openGlobe() }
            event.accepted = true
          } else if (event.key === Qt.Key_P) {
            if (!root.playing) root.openPeople()
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
            } else if (toolbar.onClock) {
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
        readonly property int homeSkyHeight: Math.round(root.cardHeight * (root.hasFace ? 0.27 : 0.25))

        // ---- the clock
        Item {
          id: clockView
          visible: !root.playing && !root.showMap && !root.showPeople && !root.showGlobe
          anchors.fill: parent
          anchors.bottomMargin: toolbar.height + content.gap

          // Nobody added yet, or nobody's offset back: there are no cards to
          // put under home, so home takes the whole card instead of sitting
          // in a strip with a blank half beneath it.
          readonly property bool aloneAtHome: root.rows.length === 0

          // Home: the sentence, the digits when the band allows them, the
          // sky, and on the bands that read digits an analog face at the
          // right spanning the header and the sky.
          Item {
            id: homeArea
            width: parent.width
            height: clockView.aloneAtHome
              ? Math.max(homeHeader.height + content.gap + content.homeSkyHeight,
                         clockView.height - invite.height - content.gap)
              : homeHeader.height + content.gap + content.homeSkyHeight

            Face {
              id: homeFace
              visible: root.hasFace
              anchors.right: parent.right
              // Alone, the sentence and the digits keep the full width and
              // the face is a square under them, as big as the room allows.
              anchors.top: clockView.aloneAtHome ? homeHeader.bottom : parent.top
              anchors.topMargin: clockView.aloneAtHome ? content.gap : 0
              anchors.bottom: parent.bottom
              // A fixed width, so the header's wrap does not feed the face
              // which feeds the header's width which feeds its wrap.
              width: !visible ? 0
                : (clockView.aloneAtHome
                  ? Math.min(height, Math.round(homeArea.width * 0.42))
                  : content.homeSkyHeight + content.gap + Math.round(Style.font.displayLarge * 1.3))
              minutesOfDay: root.home ? root.home.minutesOfDay : 0

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.startGame()
              }
            }

            HomeHeader {
              id: homeHeader
              anchors.left: parent.left
              anchors.right: homeFace.visible && !clockView.aloneAtHome ? homeFace.left : parent.right
              anchors.rightMargin: homeFace.visible && !clockView.aloneAtHome ? content.gap * 2 : 0
              anchors.top: parent.top
            }

            Sky {
              id: homeSky
              // The sun's path is a dome, so the sky keeps its shape rather
              // than stretching into whatever height is going spare; alone it
              // sits centred in the room under the sentence, beside the face.
              readonly property int room: homeArea.height - homeHeader.height - content.gap
              anchors.left: parent.left
              anchors.right: homeFace.visible ? homeFace.left : parent.right
              anchors.rightMargin: homeFace.visible ? content.gap * 2 : 0
              anchors.top: clockView.aloneAtHome ? undefined : homeHeader.bottom
              anchors.topMargin: clockView.aloneAtHome ? 0 : content.gap
              y: clockView.aloneAtHome
                ? homeHeader.height + content.gap + Math.round((room - height) / 2) : 0
              height: clockView.aloneAtHome
                ? Math.max(content.homeSkyHeight, Math.min(room, Math.round(width * 0.52)))
                : content.homeSkyHeight
              isDay: root.home ? root.home.isDay : true
              t: root.home ? root.home.t : 0.5
              bodySize: clockView.aloneAtHome ? Style.space(72) : Style.space(56)
            }
          }

          // What to do about the empty half of the clock, on the clock rather
          // than in a menu: the sun still moves with Earlier and Later, and
          // People is where the rest of the family comes from.
          Text {
            id: invite
            visible: clockView.aloneAtHome
            height: visible ? implicitHeight : 0
            anchors.bottom: parent.bottom
            width: parent.width
            textFormat: Text.PlainText
            text: root.hasFace
              ? "Only your clock so far. Earlier and Later move the sun, Play sets the hands, and People adds someone whose day appears beside yours."
              : "Only your sky so far. Earlier and Later move the sun, and People adds someone whose day appears beside yours."
            color: root.quiet
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            wrapMode: Text.WordWrap
          }

          // One card per person, side by side.
          Row {
            id: peopleRow
            visible: !clockView.aloneAtHome
            anchors.top: homeArea.bottom
            anchors.topMargin: content.gap
            anchors.bottom: parent.bottom
            width: parent.width
            spacing: Style.spacing.lg
            readonly property int count: Math.max(1, root.rows.length)
            readonly property real cardW: (width - spacing * (count - 1)) / count

            Repeater {
              model: root.rows.length

              Rectangle {
                id: personCard
                required property int index
                readonly property var row: root.rows[index] || root.emptyRow
                // Five or six cards on the navigator band leave 150 px each:
                // the type steps down, the separators shrink, and the call
                // words and the offset take a line each, so nothing is
                // elided to nonsense.
                // Three cards have room for everything; four lose the day
                // label from the place line and split the call words from
                // the offset; five or six also step the type down.
                readonly property int squeeze: peopleRow.count >= 5 ? 2 : (peopleRow.count === 4 ? 1 : 0)
                readonly property bool dense: squeeze === 2
                readonly property string dot: squeeze === 2 ? " " : (squeeze === 1 ? " · " : "  ·  ")
                width: peopleRow.cardW
                height: peopleRow.height
                radius: root.cornerRadius
                clip: true
                color: Util.alpha(root.foreground, 0.04)
                border.width: Math.max(1, Style.space(1))
                border.color: Util.alpha(root.foreground, 0.12)

                Column {
                  id: cardColumn
                  anchors.fill: parent
                  anchors.margins: Style.spacing.lg
                  spacing: Style.spacing.sm

                  Row {
                    id: cardHead
                    width: parent.width
                    spacing: Style.spacing.sm
                    Text {
                      width: parent.width - stateDot.width - Style.spacing.sm
                      textFormat: Text.PlainText
                      text: personCard.row.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: personCard.dense ? Style.font.heading : Style.font.display
                      font.bold: true
                      elide: Text.ElideRight
                    }
                    Rectangle {
                      id: stateDot
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(14)
                      height: width
                      radius: width / 2
                      color: personCard.row.call === "good" ? root.goodDot : (personCard.row.call === "busy" ? root.busyDot : root.asleepDot)
                      Behavior on color { ColorAnimation { duration: 160 } }
                    }
                  }

                  Text {
                    id: cardPlace
                    width: parent.width
                    textFormat: Text.PlainText
                    text: personCard.row.city + (personCard.row.timeText !== "" ? personCard.dot + personCard.row.timeText : "")
                      + (personCard.squeeze === 0 && personCard.row.dayLabel !== "" && personCard.row.dayLabel !== "today" ? personCard.dot + personCard.row.dayLabel : "")
                    color: root.quiet
                    font.family: root.fontFamily
                    font.pixelSize: personCard.dense ? Style.font.body : Style.font.title
                    elide: Text.ElideRight
                  }

                  // The sky takes whatever the words leave, so the last line
                  // never runs under the card's edge.
                  Sky {
                    width: parent.width
                    height: Math.max(Style.space(56), cardColumn.height - cardHead.height - cardPlace.height - cardState.height
                      - cardSentence.height - cardColumn.spacing * 4
                      - (cardCall.visible ? cardCall.height + cardColumn.spacing : 0)
                      - (cardOffset.visible ? cardOffset.height + cardColumn.spacing : 0))
                    isDay: personCard.row.isDay
                    t: personCard.row.t
                    bodySize: Style.space(30)
                  }

                  Text {
                    id: cardState
                    width: parent.width
                    textFormat: Text.PlainText
                    text: personCard.row.ready ? (personCard.row.awake ? "Awake" : "Asleep") : "..."
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: personCard.dense ? Style.font.heading : Style.font.display
                  }

                  Text {
                    id: cardSentence
                    width: parent.width
                    textFormat: Text.PlainText
                    text: personCard.row.sentence
                    color: root.quiet
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                  }

                  Text {
                    id: cardCall
                    width: parent.width
                    visible: personCard.row.ready
                    textFormat: Text.PlainText
                    text: personCard.row.callWords + (personCard.squeeze === 0 && personCard.row.offsetWords !== "" ? personCard.dot + personCard.row.offsetWords : "")
                    color: personCard.row.call === "good" ? root.sunColor : root.quiet
                    font.family: root.fontFamily
                    font.pixelSize: personCard.dense ? Style.font.body : Style.font.title
                    font.bold: personCard.row.call === "good"
                    elide: Text.ElideRight
                  }

                  Text {
                    id: cardOffset
                    width: parent.width
                    visible: personCard.squeeze > 0 && personCard.row.ready && personCard.row.offsetWords !== ""
                    textFormat: Text.PlainText
                    text: personCard.row.offsetWords
                    color: root.quiet
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                }
              }
            }
          }
        }

        // ---- the map: the header, the world, and a line that says what
        // the shading means.
        Item {
          id: mapView
          visible: !root.playing && root.showMap && !root.showPeople && !root.showGlobe
          anchors.fill: parent
          anchors.bottomMargin: toolbar.height + content.gap

          HomeHeader {
            id: mapHeader
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
          }

          WorldMap {
            id: worldMap
            anchors.top: mapHeader.bottom
            anchors.topMargin: content.gap
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width, Math.floor((parent.height - mapHeader.height - mapCaption.height - content.gap * 2) * 2))
            height: Math.round(width / 2)
            land: root.land
            night: root.night
            sun: root.sun
            markers: root.markers
          }

          Text {
            id: mapCaption
            anchors.top: worldMap.bottom
            anchors.topMargin: content.gap
            width: parent.width
            textFormat: Text.PlainText
            text: "The shaded part of the world is having its night. The sun is straight overhead at the little sun, and under the moon it is the middle of the night. Earlier and later move them."
            color: root.quiet
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }
        }

        // ---- people: the list, or the two questions of the add flow.
        Item {
          id: peopleView
          visible: !root.playing && root.showPeople
          anchors.fill: parent
          anchors.bottomMargin: toolbar.height + content.gap

          Text {
            id: peopleTitle
            width: parent.width
            textFormat: Text.PlainText
            text: "People"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
          }

          Text {
            id: peopleSubtitle
            anchors.top: peopleTitle.bottom
            anchors.topMargin: Style.spacing.xs
            width: parent.width
            textFormat: Text.PlainText
            text: "Who the clock shows, and where they live. The names stay on this computer."
            color: root.quiet
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            wrapMode: Text.WordWrap
          }

          Column {
            id: peopleList
            visible: root.peopleMode === "list" || root.peopleMode === "remove"
            anchors.top: peopleSubtitle.bottom
            anchors.topMargin: content.gap * 2
            anchors.bottom: parent.bottom
            width: parent.width
            spacing: Style.spacing.xs
            clip: true

            Repeater {
              model: root.peopleEntries.length

              Rectangle {
                id: personRow
                required property int index
                readonly property var modelData: root.peopleEntries[index] || root.emptyEntry
                readonly property bool selected: root.peopleIndex === index
                readonly property bool confirming: selected && root.peopleMode === "remove"
                readonly property bool isPerson: modelData.kind === "person"
                width: peopleList.width
                height: Style.space(40)
                radius: root.cornerRadius
                color: selected ? Color.menu.selectedBackground : Util.alpha(root.foreground, 0.04)
                border.width: Math.max(1, Style.space(1))
                border.color: selected ? Util.alpha(root.sunColor, 0.8) : Util.alpha(root.foreground, 0.10)
                Behavior on color { ColorAnimation { duration: 120 } }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: if (root.peopleMode === "list") root.peopleIndex = personRow.index
                  onClicked: root.activateRow(personRow.index)
                }

                Item {
                  id: rowMarker
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.xl
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(18)
                  height: width

                  Rectangle {
                    anchors.centerIn: parent
                    visible: personRow.modelData.kind !== "add"
                    width: Style.space(personRow.modelData.kind === "home" ? 16 : 12)
                    height: width
                    radius: width / 2
                    color: personRow.modelData.kind === "home" ? "transparent" : root.sunColor
                    border.width: personRow.modelData.kind === "home" ? Math.max(2, Style.space(3)) : 0
                    border.color: root.foreground
                  }
                  Text {
                    anchors.centerIn: parent
                    visible: personRow.modelData.kind === "add"
                    textFormat: Text.PlainText
                    text: "+"
                    color: root.sunColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                    font.bold: true
                  }
                }

                Row {
                  id: rowWords
                  anchors.left: rowMarker.right
                  anchors.leftMargin: Style.spacing.xl
                  anchors.right: rowRight.left
                  anchors.rightMargin: Style.spacing.lg
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.lg

                  Text {
                    id: rowName
                    textFormat: Text.PlainText
                    text: personRow.confirming ? "Remove " + personRow.modelData.name + "?" : personRow.modelData.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    font.bold: true
                  }
                  Text {
                    width: Math.max(0, rowWords.width - rowName.width - rowWords.spacing)
                    textFormat: Text.PlainText
                    text: personRow.modelData.place
                    color: personRow.confirming ? root.foreground : root.quiet
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    elide: Text.ElideRight
                  }
                }

                Row {
                  id: rowRight
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.xl
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.xxl

                  Text {
                    visible: text !== "" && !personRow.confirming
                    textFormat: Text.PlainText
                    text: personRow.modelData.time
                    color: root.quiet
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                  }
                  ActionButton {
                    visible: personRow.isPerson && !personRow.confirming
                    anchors.verticalCenter: parent.verticalCenter
                    compact: true
                    text: "Remove"
                    onClicked: root.askRemoveAt(personRow.index)
                  }
                  ActionButton {
                    visible: personRow.confirming
                    anchors.verticalCenter: parent.verticalCenter
                    compact: true
                    primary: true
                    text: "Yes, remove"
                    onClicked: root.confirmRemove()
                  }
                  ActionButton {
                    visible: personRow.confirming
                    anchors.verticalCenter: parent.verticalCenter
                    compact: true
                    text: "No"
                    onClicked: root.peopleMode = "list"
                  }
                }
              }
            }
          }

          Column {
            id: editPane
            visible: root.peopleMode === "name" || root.peopleMode === "place"
            anchors.top: peopleSubtitle.bottom
            anchors.topMargin: content.gap * 3
            width: parent.width
            spacing: Style.spacing.lg

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.editPrompt
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: Math.min(parent.width, Style.space(560))
              height: Style.space(56)
              radius: root.cornerRadius
              color: Util.alpha(root.foreground, 0.06)
              border.width: Math.max(1, Style.space(2))
              border.color: root.sunColor

              TextInput {
                id: editField
                anchors.fill: parent
                anchors.leftMargin: Style.spacing.xl
                anchors.rightMargin: Style.spacing.xl
                verticalAlignment: TextInput.AlignVCenter
                color: root.foreground
                selectionColor: Util.alpha(root.sunColor, 0.5)
                selectedTextColor: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
                selectByMouse: true
                maximumLength: 64
                clip: true
                text: root.peopleMode === "name" ? root.draftName : root.draftWhere
                onTextEdited: {
                  if (root.peopleMode === "name") root.draftName = text
                  else root.draftWhere = text
                }
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    root.editBack()
                    event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.editAccept()
                    event.accepted = true
                  } else if (root.peopleMode === "place" && event.key === Qt.Key_Down) {
                    root.matchIndex = Math.min(Math.max(0, root.placeOptions.length - 1), root.matchIndex + 1)
                    event.accepted = true
                  } else if (root.peopleMode === "place" && event.key === Qt.Key_Up) {
                    root.matchIndex = Math.max(0, root.matchIndex - 1)
                    event.accepted = true
                  }
                }
              }

              Text {
                anchors.fill: editField
                verticalAlignment: Text.AlignVCenter
                visible: editField.text === ""
                textFormat: Text.PlainText
                text: root.peopleMode === "name" ? "Grandma, Nana, Uncle Ken..."
                  : (root.placeFor === "home" ? "a town, or whatever we call home" : "a town or a city")
                color: Util.alpha(root.foreground, 0.66)
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.editHint
              color: root.quiet
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Column {
              width: Math.min(parent.width, Style.space(560))
              spacing: Style.spacing.xs
              visible: root.peopleMode === "place"

              Repeater {
                model: root.placeOptions

                Rectangle {
                  id: matchRow
                  required property var modelData
                  required property int index
                  readonly property bool selected: root.matchIndex === index
                  width: parent.width
                  height: Style.space(40)
                  radius: root.cornerRadius
                  color: selected ? Color.menu.selectedBackground : Util.alpha(root.foreground, 0.04)
                  border.width: Math.max(1, Style.space(1))
                  border.color: selected ? Util.alpha(root.sunColor, 0.8) : Util.alpha(root.foreground, 0.10)

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onEntered: root.matchIndex = matchRow.index
                    onClicked: root.pickMatch(matchRow.index)
                  }

                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.spacing.xl
                    anchors.right: matchZone.left
                    anchors.rightMargin: Style.spacing.lg
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: matchRow.modelData.label
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    font.bold: matchRow.selected
                    elide: Text.ElideRight
                  }
                  Text {
                    id: matchZone
                    anchors.right: parent.right
                    anchors.rightMargin: Style.spacing.xl
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: matchRow.modelData.hint
                    color: root.quiet
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              Text {
                visible: root.peopleMode === "place" && root.draftWhere.length >= 2 && root.placeOptions.length === 0
                width: parent.width
                textFormat: Text.PlainText
                text: "Nothing called that here yet. Try the nearest big city, or a time zone such as America/Phoenix."
                color: root.quiet
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
              }
            }
          }
        }

        // ---- the globe: the sphere on the left with two buttons to turn it,
        // and on the right what the tapped place says.
        Item {
          id: globeView
          visible: !root.playing && root.showGlobe && !root.showPeople
          anchors.fill: parent
          anchors.bottomMargin: toolbar.height + content.gap
          readonly property int globeSize: Math.max(Style.space(200), Math.min(height - spinRow.height - content.gap, Math.round(width * 0.54)))

          Globe {
            id: theGlobe
            anchors.left: parent.left
            anchors.top: parent.top
            width: globeView.globeSize
            height: width
            lat0: root.globeLat
            lon0: root.globeLon
            dots: root.globeDots
            spots: root.spots
            picked: root.pickedSpot
            onSpotPicked: function(index) { root.pickSpot(index) }
            onDragChanged: function(dragging) {
              if (dragging) { lonSpin.stop(); latSpin.stop() }
              root.globeDragging = dragging
            }
            onTurned: function(dLat, dLon) {
              root.globeLat = Math.max(-75, Math.min(75, root.globeLat + dLat))
              root.globeLon = root.globeLon + dLon
            }
          }

          Row {
            id: spinRow
            anchors.horizontalCenter: theGlobe.horizontalCenter
            anchors.top: theGlobe.bottom
            anchors.topMargin: Style.spacing.sm
            spacing: Style.spacing.xxl * 2
            TurnButton { glyph: "‹"; caption: "turn it"; delta: -40; spins: true }
            TurnButton { glyph: "›"; caption: "turn it"; delta: 40; spins: true }
          }

          Column {
            id: spotColumn
            anchors.left: theGlobe.right
            anchors.leftMargin: content.gap * 2
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Style.spacing.md

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.pickedView
                ? root.pickedView.name + (root.pickedView.where !== "" ? ", " + root.pickedView.where : "")
                : "Tap a dot on the globe."
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              visible: text !== ""
              textFormat: Text.PlainText
              text: root.pickedView && root.pickedView.timeText !== ""
                ? root.pickedView.timeText + (root.pickedView.dayLabel !== "" && root.pickedView.dayLabel !== "today" ? "  ·  " + root.pickedView.dayLabel : "")
                : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              font.bold: true
            }

            Text {
              width: parent.width
              visible: text !== ""
              textFormat: Text.PlainText
              text: root.pickedView ? root.pickedView.timeWords : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              wrapMode: Text.WordWrap
            }

            Sky {
              width: parent.width
              height: Math.round(globeView.height * 0.30)
              isDay: root.pickedView ? root.pickedView.isDay : true
              t: root.pickedView ? root.pickedView.t : 0.5
              bodySize: Style.space(40)
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.pickedView
                ? root.pickedView.sentence
                : "The shaded side is having its night, and the little sun is where it is straight overhead. Drag the globe, or turn it with the buttons under it."
              color: root.pickedView ? root.foreground : root.quiet
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              visible: text !== ""
              textFormat: Text.PlainText
              text: root.pickedView ? root.pickedView.offsetWords : ""
              color: root.quiet
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
          }
        }

        // ---- the game: the face on the left, the words and the sky on the
        // right, and four big buttons that turn the hands.
        Item {
          id: gameArea
          visible: root.playing
          anchors.fill: parent
          anchors.bottomMargin: toolbar.height + content.gap
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
              text: root.currentRound ? root.currentRound.title + " in " + root.currentRound.city : ""
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
              visible: text !== ""
              textFormat: Text.PlainText
              text: !root.game || root.solved ? "" : root.game.hint
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

        // ---- the buttons: what can be done from here on the left, Close on
        // the right. Only the buttons that mean something now are shown, and
        // the row wraps rather than run under Close if a theme's font is wide.
        Item {
          id: toolbar
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Math.max(actions.implicitHeight, closeButton.implicitHeight)

          readonly property bool onClock: !root.playing && !root.showPeople && !root.showGlobe && !root.showMap
          readonly property bool onMap: !root.playing && !root.showPeople && !root.showGlobe && root.showMap
          readonly property bool onGlobe: !root.playing && !root.showPeople && root.showGlobe
          readonly property bool onWorld: onClock || onMap || onGlobe
          readonly property bool onList: root.showPeople && (root.peopleMode === "list" || root.peopleMode === "remove")
          readonly property bool editing: root.showPeople && (root.peopleMode === "name" || root.peopleMode === "place")

          Flow {
            id: actions
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            width: parent.width - closeButton.width - Style.spacing.lg
            spacing: Style.spacing.lg

            // The clock, the map and the globe share the sun.
            ActionButton { visible: toolbar.onWorld; text: "←  Earlier"; onClicked: if (root.clock) root.clock.scrub(-60) }
            ActionButton { visible: toolbar.onWorld; text: "Later  →"; onClicked: if (root.clock) root.clock.scrub(60) }
            ActionButton { visible: toolbar.onWorld && root.scrubbing; primary: true; text: "Back to now"; onClicked: if (root.clock) root.clock.resetScrub() }
            ActionButton { visible: toolbar.onClock && root.hasFace; text: "Play"; onClicked: root.startGame() }
            ActionButton { visible: toolbar.onClock && root.hasMap; text: "Map"; onClicked: { root.showGlobe = false; root.showMap = true } }
            ActionButton { visible: toolbar.onClock || toolbar.onMap; text: "Globe"; onClicked: root.openGlobe() }
            ActionButton { visible: toolbar.onClock || toolbar.onMap; text: "People"; onClicked: root.openPeople() }
            ActionButton { visible: toolbar.onGlobe; text: "Find home"; onClicked: root.centreGlobeOnHome() }
            ActionButton { visible: toolbar.onMap; text: "Clock"; onClicked: root.showMap = false }
            ActionButton { visible: toolbar.onGlobe; text: "Clock"; onClicked: root.closeGlobe() }

            // The People screen.
            ActionButton { visible: toolbar.onList; text: "←  Clock"; onClicked: root.closePeople() }
            ActionButton { visible: toolbar.editing; text: "←  Back"; onClicked: root.editBack() }
            ActionButton {
              visible: root.showPeople && root.peopleMode === "name"
              primary: true
              enabled: root.draftName.trim() !== ""
              text: "Next  →"
              onClicked: root.editAccept()
            }
            ActionButton {
              visible: root.showPeople && root.peopleMode === "place"
              primary: true
              enabled: root.placeOptions.length > 0
              text: "Save"
              onClicked: root.editAccept()
            }

            // The game.
            ActionButton { visible: root.playing; text: "←  Clock"; onClicked: root.stopGame() }
            ActionButton { visible: root.playing; text: "Start again"; onClicked: if (root.currentRound) root.hands = root.currentRound.startHands }
            ActionButton {
              visible: root.playing && root.solved
              primary: true
              text: root.currentRound && root.nextName === root.currentRound.name ? "Play again" : root.nextName + " next  →"
              onClicked: root.nextRound()
            }
          }

          ActionButton {
            id: closeButton
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: "Close"
            onClicked: root.dismiss()
          }
        }
      }
    }
  }
}
