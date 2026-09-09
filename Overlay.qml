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
  // Times on Earth: one screen with two ways of looking, the globe on every
  // band and the flat map on the band that reads maps.
  property bool showEarth: false
  property string earthMode: "globe"
  readonly property bool showMap: showEarth && earthMode === "map"
  readonly property bool showGlobe: showEarth && earthMode === "globe"
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
  // The spots the flat map draws as plain dots: everything that is not home
  // or one of the people, since those already have a named marker there.
  readonly property var mapSpots: {
    var out = []
    if (!showMap) return out
    for (var i = 0; i < spots.length; i++) {
      if (spots[i].kind === "home" || spots[i].kind === "person") continue
      out.push({ at: i, lat: spots[i].lat, lon: spots[i].lon })
    }
    return out
  }
  readonly property var pickedOffset: !picked || !clock ? null
    : (picked.kind === "home" ? { offsetSeconds: clock.homeOffsetSeconds } : (clock.offsets ? clock.offsets[picked.zone] : null))
  readonly property var pickedView: picked && clock
    ? Model.spotView(picked, pickedOffset, shownMs, home, clock.routine, rules, clock.hourFormat)
    : null

  // Opened before the city list or the home zone has loaded, the globe has
  // no home to centre on; when home turns up it goes there and picks it.
  onSpotsChanged: {
    // The list fills in after the city file and the home zone land, which is
    // usually after the screen is already open, so this is where both views
    // ask for the offsets they are about to need.
    if (showEarth && spots.length > 0) askForSpotZones()
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

  function openEarth(mode) {
    if (playing) return
    showPeople = false
    showMe = false
    earthMode = String(mode) === "map" && hasMap ? "map" : "globe"
    showEarth = true
    if (earthMode === "globe") settleGlobe()
    else askForSpotZones()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function setEarthMode(mode) {
    var next = String(mode) === "map" && hasMap ? "map" : "globe"
    if (next === earthMode) return
    earthMode = next
    if (next === "globe") settleGlobe()
    else askForSpotZones()
  }

  // The flat map can be asked about the same places as the globe, so it needs
  // their offsets too.
  function askForSpotZones() {
    if (clock && typeof clock.requestZones === "function") clock.requestZones(spotZones())
  }

  function settleGlobe() {
    globeDragging = true
    centreGlobeOnHome()
    globeDragging = false
    pickedSpot = spots.length > 0 ? 0 : -1
    if (clock && typeof clock.requestZones === "function") clock.requestZones(spotZones())
  }

  function closeEarth() {
    showEarth = false
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

  // ---- Me: what home is called and where it is. Its own screen, because it
  // is the one place on the clock that is not somebody else.
  property bool showMe: false
  property string meDraft: ""
  readonly property var meMatches: showMe ? Model.searchCities(cities, meDraft, 5) : []
  // Anything typed can be home: home's clock is the computer's clock and
  // never leaves its time zone, so the place is a name. A city from the list
  // does one thing more, which the options say.
  readonly property var meOptions: {
    var out = []
    for (var i = 0; i < meMatches.length; i++)
      out.push({ label: meMatches[i].label, hint: "on the map and the globe", key: meMatches[i].key })
    var typed = meDraft.trim()
    if (typed !== "" && !Model.findCity(cities, typed))
      out.push({ label: "Use \u201c" + typed + "\u201d", hint: "as it is typed", key: typed })
    return out
  }
  readonly property int meIndex0: 0
  property int meIndex: 0
  onMeOptionsChanged: meIndex = 0
  readonly property string meName: clock ? clock.homeName : "home"
  readonly property bool meFromZone: clock ? clock.homeCitySetting === "" : true

  function openMe() {
    if (playing) return
    showEarth = false
    showPeople = false
    meDraft = clock ? clock.homeCitySetting : ""
    meIndex = 0
    showMe = true
    Qt.callLater(function() { meField.forceActiveFocus(); meField.cursorPosition = meField.text.length })
  }

  function closeMe() {
    showMe = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function saveMe(key) {
    persistSettings({ homeCity: String(key || "") })
    closeMe()
  }

  function acceptMe() {
    // An empty field means home goes back to the computer's own time zone,
    // which is where it started; there is no separate button for it.
    if (meDraft.trim() === "") { saveMe(""); return }
    var option = meOptions[meIndex]
    if (option) saveMe(option.key)
  }

  property bool showPeople: false
  property string peopleMode: "list"   // list, name, place, remove
  property int peopleIndex: 1
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
    if (Model.isZone(typed)) out.push({ label: typed, hint: "a time zone", key: typed })
    return out
  }
  onPlaceOptionsChanged: matchIndex = 0
  readonly property var peopleEntries: {
    var out = []
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
  readonly property string editPrompt: peopleMode === "name"
    ? "What do you call them?" : "Where does " + draftName + " live?"
  readonly property string editHint: peopleMode === "name"
    ? "The name the child uses."
    : "Type a few letters and pick the place. If it is not here, try the nearest big city, or a time zone such as America/Phoenix."

  // Save some settings onto the plugin's entry, keeping the rest.
  function persistSettings(values) {
    if (!clock || !values || typeof values !== "object" || Array.isArray(values)) return false
    var entry = { id: pluginId }
    var current = clock.config || {}
    for (var k in current) if (k !== "id") entry[k] = current[k]
    for (var v in values) entry[v] = values[v]
    if (shell && typeof shell.updateEntryInline === "function") {
      var saved = shell.updateEntryInline(pluginId, entry)
      // Show it at once rather than waiting for the shell's copy to catch up;
      // the service drops the entry again as soon as the shell agrees.
      if (saved && typeof clock.noteSaved === "function") clock.noteSaved(entry)
      return saved
    }
    console.warn("kids-clock: the shell cannot save settings here")
    return false
  }

  function openPeople() {
    if (playing) return
    showEarth = false
    showMe = false
    peopleMode = "list"
    pending = null
    peopleIndex = 0
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

  function backToList() {
    peopleMode = "list"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function editBack() {
    if (peopleMode === "place") { peopleMode = "name"; focusEditField() }
    else backToList()
  }

  function savePlace(whereKey) {
    if (!clock) return
    persistSettings({ people: Model.addPerson(clock.peopleText, draftName, whereKey) })
    backToList()
    Qt.callLater(function() { peopleIndex = Math.max(0, storedPeople.length - 1) })
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
    if (index === storedPeople.length) beginAdd()
  }

  // The person waiting to be removed is held by name and place, not by the
  // row they were on. A row index moves under the list as it shrinks, and
  // once it slid onto "Add someone" the confirm quietly did nothing; that is
  // what made the last person impossible to remove.
  property var pending: null

  function askRemoveAt(index) {
    if (index < 0 || index >= storedPeople.length) return
    peopleIndex = index
    pending = storedPeople[index]
    peopleMode = "remove"
  }

  function askRemove() { askRemoveAt(peopleIndex) }

  function cancelRemove() {
    pending = null
    peopleMode = "list"
  }

  function confirmRemove() {
    if (peopleMode !== "remove" || !pending || !clock) return
    var at = Model.indexOfPerson(clock.peopleText, pending.name, pending.where)
    if (at >= 0) persistSettings({ people: Model.removePerson(clock.peopleText, at) })
    pending = null
    peopleMode = "list"
    Qt.callLater(function() { peopleIndex = Math.max(0, Math.min(peopleIndex, storedPeople.length)) })
  }

  // ---- the clock game. Two rounds, and both are about the face alone:
  // Set the clock puts a time in words and asks for the hands, Read the clock
  // sets the hands and asks for the time. No sun, no sky, no morning or
  // afternoon: a dial says none of those, and pretending it did was what made
  // the old round confusing.
  property bool playing: false
  property string gameMode: "set"     // set or read
  property var currentRound: null
  property int hands: 0
  property int chosen: -1
  readonly property var game: playing && currentRound && currentRound.mode === "set"
    ? Model.gameView(currentRound, hands) : null
  readonly property bool solved: {
    if (!playing || !currentRound) return false
    if (currentRound.mode === "read") return chosen >= 0 && currentRound.choices[chosen].right
    return game ? game.solved : false
  }
  readonly property bool wrongPick: playing && currentRound && currentRound.mode === "read"
    && chosen >= 0 && !currentRound.choices[chosen].right
  readonly property string otherMode: gameMode === "set" ? "read" : "set"
  readonly property string otherModeName: gameMode === "set" ? "Read the clock" : "Set the clock"
  // The band's own step: quarter hours while "half past" is still new, five
  // minutes once it is not.
  readonly property int gameStep: rules && rules.gameStep > 0 ? rules.gameStep : 5
  readonly property string stepWords: gameStep === 15 ? "15 minutes" : gameStep + " minutes"

  function beginRound(mode) {
    if (!clock) return
    var previous = currentRound ? currentRound.targetMinutes : null
    gameMode = String(mode) === "read" ? "read" : "set"
    currentRound = Model.gameRound(gameMode, clock.rules, clock.hourFormat, null, previous)
    hands = currentRound.startHands
    chosen = -1
  }

  function startGame(mode) {
    if (!hasFace || !clock) return
    clock.resetScrub()
    showEarth = false
    showPeople = false
    showMe = false
    beginRound(mode || gameMode)
    playing = true
  }

  function switchGameMode() {
    if (playing) beginRound(otherMode)
  }

  function nextRound() { beginRound(gameMode) }

  function turn(deltaMinutes) {
    if (playing && currentRound && currentRound.mode === "set") hands = hands + deltaMinutes
  }

  function pickTime(index) {
    if (!playing || !currentRound || currentRound.mode !== "read") return
    if (solved) return
    chosen = index
  }

  function stopGame() {
    playing = false
    currentRound = null
    chosen = -1
  }


  // The payload may name a view: {"view": "map"}, "game" or "clock".
  function open(payloadJson) {
    root.opened = true
    var payload = null
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = null }
    var view = payload && payload.view ? String(payload.view) : ""
    if (view === "map" || view === "earth" || view === "globe") root.openEarth(view === "map" ? "map" : "globe")
    else if (view === "clock") { root.showEarth = false; root.showPeople = false }
    else if (view === "game") root.startGame()
    else if (view === "people") root.openPeople()
    else if (view === "me") root.openMe()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // Every way out lands on the clock next time: the shell's own hide (the
  // bar chip, a keybinding built on toggle) as much as Escape or Close.
  // What Back means on each screen: one step out, never a jump. Inside the
  // add flow it walks back through the questions before leaving the list.
  function stepBack() {
    if (playing) { stopGame(); return }
    if (showMe) { closeMe(); return }
    if (showPeople) {
      if (peopleMode === "remove") { cancelRemove(); return }
      if (peopleMode === "name" || peopleMode === "place") { editBack(); return }
      closePeople()
      return
    }
    if (showEarth) { closeEarth(); return }
    dismiss()
  }

  function resetViews() {
    root.stopGame()
    root.showEarth = false
    root.showPeople = false
    root.showMe = false
    root.peopleMode = "list"
    root.pending = null
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
    // The well-known cities, as indexes into root.spots so a tap can pick one
    // the same way tapping the globe does.
    property var spots: []
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

    // The cities behind the named markers: small, plain, and tappable.
    Repeater {
      model: map.spots.length
      Item {
        id: spotDot
        required property int index
        readonly property var spot: map.spots[index]
        readonly property bool chosen: root.pickedSpot === spot.at
        readonly property var pos: Model.mapPoint(spot.lon, spot.lat, map.width, map.height)
        x: pos[0]
        y: pos[1]

        Rectangle {
          anchors.centerIn: parent
          width: Style.space(spotDot.chosen ? 14 : 9)
          height: width
          radius: width / 2
          color: spotDot.chosen ? root.sunColor : Util.alpha(root.foreground, 0.55)
          border.width: spotDot.chosen ? Math.max(2, Style.space(2)) : 0
          border.color: root.foreground
          Behavior on width { NumberAnimation { duration: 140 } }
        }

        MouseArea {
          anchors.centerIn: parent
          width: Style.space(28)
          height: width
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.pickSpot(spotDot.spot.at)
        }
      }
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
  //
  // Its height is fixed by the font, never by the words. The sentence gets
  // two lines whether it needs them or not and the banner keeps its line
  // while it is empty, because a header that grows a line when the wording
  // gets longer shoves the sky, the cards and the buttons down with it, and
  // that happens every time the sun moves or the place is renamed.
  component HomeHeader: Item {
    id: header
    readonly property int sentenceHeight: Math.ceil(sentenceMetrics.height * 2)
    readonly property int bannerHeight: Math.ceil(bannerMetrics.height)
    height: Math.max(headerTime.implicitHeight,
      sentenceHeight + Style.spacing.xs + bannerHeight)

    FontMetrics {
      id: sentenceMetrics
      font.family: root.fontFamily
      font.pixelSize: Style.font.displayLarge
    }
    FontMetrics {
      id: bannerMetrics
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
    }

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
        height: header.sentenceHeight
        textFormat: Text.PlainText
        text: root.home ? root.home.sentence : "Finding the sun..."
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.displayLarge
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        verticalAlignment: Text.AlignTop
      }
      Text {
        width: parent.width
        height: header.bannerHeight
        textFormat: Text.PlainText
        text: root.scrubWords === "" ? "" : root.scrubWords + "."
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
        verticalAlignment: Text.AlignTop
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
  // The sun's controls, wherever the sun is shown. Small and beside the
  // thing they move, not down in the navigation.
  component SunRow: Row {
    spacing: Style.spacing.md
    ActionButton { compact: true; text: "←  Earlier"; onClicked: if (root.clock) root.clock.scrub(-60) }
    ActionButton { compact: true; text: "Later  →"; onClicked: if (root.clock) root.clock.scrub(60) }
    ActionButton {
      compact: true
      primary: root.scrubbing
      enabled: root.scrubbing
      text: "Now"
      onClicked: if (root.clock) root.clock.resetScrub()
    }
  }

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
          // The Me screen keeps its own keys on the field itself; here only
          // Escape needs to reach out of it.
          if (root.showMe && !root.playing) {
            if (event.key === Qt.Key_Escape) { root.closeMe(); event.accepted = true }
            return
          }
          if (root.showPeople) {
            if (event.key === Qt.Key_Escape) {
              if (root.peopleMode === "remove") root.cancelRemove()
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
              root.askRemoveAt(root.peopleIndex)
            }
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Escape) {
            if (!root.playing && !root.showEarth && root.scrubbing && root.clock) root.clock.resetScrub()
            else root.stepBack()
            event.accepted = true
          } else if (event.key === Qt.Key_M) {
            if (root.hasMap && !root.playing) {
              if (root.showEarth) root.setEarthMode(root.earthMode === "map" ? "globe" : "map")
              else root.openEarth("map")
            }
            event.accepted = true
          } else if (event.key === Qt.Key_G) {
            if (!root.playing) { if (root.showEarth) root.closeEarth(); else root.openEarth("globe") }
            event.accepted = true
          } else if (event.key === Qt.Key_P) {
            if (!root.playing) root.openPeople()
            event.accepted = true
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Left) {
            var sign = event.key === Qt.Key_Right ? 1 : -1
            if (root.playing) root.turn(sign * (shift ? 1 : root.gameStep))
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
          } else if (event.key === Qt.Key_R) {
            if (root.playing) root.switchGameMode()
            event.accepted = true
          } else if (root.playing && root.currentRound && root.currentRound.mode === "read"
              && event.key >= Qt.Key_1 && event.key <= Qt.Key_4) {
            root.pickTime(event.key - Qt.Key_1)
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
        readonly property int homeSkyHeight: Math.round(root.cardHeight * (root.hasFace ? 0.235 : 0.22))

        // ---- the clock
        Item {
          id: clockView
          visible: !root.playing && !root.showMap && !root.showPeople && !root.showMe && !root.showGlobe
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
            readonly property int skyRoom: clockView.height - homeHeader.height
              - content.gap - sunRow.height - Style.spacing.md
            // How tall the sky and the face are with nobody on the clock.
            // Worked out from the card's own width and the room going spare,
            // never from the sky itself: the face's width is drawn from this,
            // and the face's width sets the sky's width, which would set the
            // sky's height, which would set the face again.
            readonly property int aloneBlock: Math.max(content.homeSkyHeight,
              Math.min(skyRoom, Math.round(width * 0.30)))
            height: homeHeader.height + content.gap
              + (clockView.aloneAtHome ? aloneBlock : content.homeSkyHeight)

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
                  ? Math.min(homeArea.aloneBlock, Math.round(homeArea.width * 0.42))
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
              // than stretching into whatever height is going spare.
              anchors.left: parent.left
              anchors.right: homeFace.visible ? homeFace.left : parent.right
              anchors.rightMargin: homeFace.visible ? content.gap * 2 : 0
              anchors.top: homeHeader.bottom
              anchors.topMargin: content.gap
              height: clockView.aloneAtHome ? homeArea.aloneBlock : content.homeSkyHeight
              isDay: root.home ? root.home.isDay : true
              t: root.home ? root.home.t : 0.5
              bodySize: clockView.aloneAtHome ? Style.space(72) : Style.space(56)
            }
          }

          // Moving the sun belongs to the sky, so the two buttons sit under
          // it rather than in the navigation at the foot of the card.
          // Under the clock, which means under the face when there is one:
          // the buttons move the time, and the face is the time.
          SunRow {
            id: sunRow
            anchors.top: homeArea.bottom
            anchors.topMargin: Style.spacing.md
            x: homeFace.visible
              ? Math.max(0, Math.round(homeArea.x + homeFace.x + homeFace.width / 2 - width / 2))
              : 0
          }

          // One card per person, side by side.
          Row {
            id: peopleRow
            visible: !clockView.aloneAtHome
            anchors.top: sunRow.bottom
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
        // ---- Times on Earth: the globe and the flat map are one place with
        // two ways of looking, and the switch between them, Find home and the
        // sun's own buttons all live up here with what they act on.
        Item {
          id: earthBar
          visible: !root.playing && root.showEarth
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: visible ? Math.max(earthTitle.implicitHeight, earthControls.implicitHeight) : 0

          Text {
            id: earthTitle
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Times on Earth"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
          }

          Flow {
            id: earthControls
            anchors.left: earthTitle.right
            anchors.leftMargin: Style.spacing.xl
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.md
            layoutDirection: Qt.RightToLeft

            SunRow {}
            ActionButton {
              compact: true
              visible: root.hasMap
              primary: root.earthMode === "map"
              text: "Flat map"
              onClicked: root.setEarthMode("map")
            }
            ActionButton {
              compact: true
              visible: root.hasMap
              primary: root.earthMode === "globe"
              text: "Globe"
              onClicked: root.setEarthMode("globe")
            }
          }
        }

        Item {
          id: mapView
          visible: !root.playing && root.showMap && !root.showPeople && !root.showMe
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: earthBar.bottom
          anchors.topMargin: content.gap
          anchors.bottom: parent.bottom
          anchors.bottomMargin: toolbar.height + content.gap

          WorldMap {
            id: worldMap
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width, Math.floor((parent.height - mapPick.height - content.gap) * 2))
            height: Math.round(width / 2)
            land: root.land
            night: root.night
            sun: root.sun
            markers: root.markers
            spots: root.mapSpots
          }

          // What was tapped, said the same way the globe says it.
          Text {
            id: mapPick
            anchors.top: worldMap.bottom
            anchors.topMargin: content.gap
            anchors.left: parent.left
            anchors.right: parent.right
            textFormat: Text.PlainText
            // Short enough for one line: the place, the digits when the band
            // has them, and the time in words. The globe has the room for the
            // whole sentence; the map does not.
            text: !root.pickedView ? "Tap a place to hear the time there."
              : root.pickedView.name
                + (root.pickedView.timeText === "" ? "" : "  ·  " + root.pickedView.timeText)
                + (root.pickedView.dayLabel === "" || root.pickedView.dayLabel === "today"
                  ? "" : "  ·  " + root.pickedView.dayLabel)
                + (root.pickedView.timeWords === "" ? "" : "  ·  " + root.pickedView.timeWords)
            color: root.pickedView ? root.foreground : root.quiet
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            // Two lines whatever it says, so tapping around the map does not
            // shuffle the map itself up and down.
            height: Math.ceil(pickMetrics.height * 2)
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop

            FontMetrics {
              id: pickMetrics
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
          }
        }

        // ---- me: what home is called, and where it is. Its own screen, so
        // the People list is only ever other people.
        Item {
          id: meView
          visible: !root.playing && root.showMe
          anchors.fill: parent
          anchors.bottomMargin: toolbar.height + content.gap

          Text {
            id: meTitle
            width: parent.width
            textFormat: Text.PlainText
            text: "Me"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
          }

          Text {
            id: meNow
            anchors.top: meTitle.bottom
            anchors.topMargin: Style.spacing.xs
            width: parent.width
            textFormat: Text.PlainText
            text: "Right now home is " + root.meName
              + (root.meFromZone ? ", taken from the computer's time zone." : ".")
            color: root.quiet
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            wrapMode: Text.WordWrap
          }

          Column {
            anchors.top: meNow.bottom
            anchors.topMargin: content.gap * 2
            width: parent.width
            spacing: Style.spacing.lg

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Where are we?"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              wrapMode: Text.WordWrap
            }

            Row {
              width: parent.width
              spacing: Style.spacing.lg

              Rectangle {
              width: Math.min(parent.width - meGo.width - Style.spacing.lg, Style.space(560))
              height: Style.space(56)
              radius: root.cornerRadius
              color: Util.alpha(root.foreground, 0.06)
              border.width: Math.max(1, Style.space(2))
              border.color: root.sunColor

              TextInput {
                id: meField
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
                text: root.meDraft
                onTextEdited: root.meDraft = text
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) { root.closeMe(); event.accepted = true }
                  else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.acceptMe(); event.accepted = true }
                  else if (event.key === Qt.Key_Down) {
                    root.meIndex = Math.min(Math.max(0, root.meOptions.length - 1), root.meIndex + 1)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Up) {
                    root.meIndex = Math.max(0, root.meIndex - 1)
                    event.accepted = true
                  }
                }
              }

              Text {
                anchors.fill: meField
                verticalAlignment: Text.AlignVCenter
                visible: meField.text === ""
                textFormat: Text.PlainText
                text: "a town, or whatever we call home"
                color: Util.alpha(root.foreground, 0.66)
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
              }
              }

              ActionButton {
                id: meGo
                anchors.verticalCenter: parent.verticalCenter
                primary: true
                enabled: root.meOptions.length > 0 || root.meDraft.trim() === ""
                text: "Save"
                onClicked: root.acceptMe()
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Type anything: a town, a street, whatever we call the house. The clock here always follows the computer's own time zone, whatever this says; picking a place from the list also puts home on the map and the globe, and gives its sky the right sunrise. Leave it empty to go back to the computer's own place."
              color: root.quiet
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Column {
              width: Math.min(parent.width, Style.space(560))
              spacing: Style.spacing.xs

              Repeater {
                model: root.meOptions

                Rectangle {
                  id: meRow
                  required property var modelData
                  required property int index
                  readonly property bool selected: root.meIndex === index
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
                    onEntered: root.meIndex = meRow.index
                    onClicked: root.saveMe(meRow.modelData.key)
                  }

                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.spacing.xl
                    anchors.right: meHint.left
                    anchors.rightMargin: Style.spacing.lg
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: meRow.modelData.label
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    font.bold: meRow.selected
                    elide: Text.ElideRight
                  }
                  Text {
                    id: meHint
                    anchors.right: parent.right
                    anchors.rightMargin: Style.spacing.xl
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: meRow.modelData.hint
                    color: root.quiet
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }
        }

        // ---- people: the list, or the two questions of the add flow.
        Item {
          id: peopleView
          visible: !root.playing && root.showPeople && !root.showMe
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

            Row {
              width: parent.width
              spacing: Style.spacing.lg

              Rectangle {
              width: Math.min(parent.width - editGo.width - Style.spacing.lg, Style.space(560))
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
                  : "a town or a city"
                color: Util.alpha(root.foreground, 0.66)
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
              }
              }

              ActionButton {
                id: editGo
                anchors.verticalCenter: parent.verticalCenter
                primary: true
                enabled: root.peopleMode === "name"
                  ? root.draftName.trim() !== "" : root.placeOptions.length > 0
                text: root.peopleMode === "name" ? "Next  →" : "Save"
                onClicked: root.editAccept()
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
          visible: !root.playing && root.showGlobe && !root.showPeople && !root.showMe
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: earthBar.bottom
          anchors.topMargin: content.gap
          anchors.bottom: parent.bottom
          anchors.bottomMargin: toolbar.height + content.gap
          // The globe leaves room for what sits under it: the two turn
          // buttons and Find home, which belongs to the globe rather than to
          // the header the flat map shares.
          readonly property int globeSize: Math.max(Style.space(200),
            Math.min(height - spinRow.height - content.gap, Math.round(width * 0.54)))

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
            spacing: Style.spacing.xl
            TurnButton { glyph: "‹"; caption: "turn it"; delta: -40; spins: true }
            ActionButton {
              id: findHome
              anchors.verticalCenter: parent.verticalCenter
              compact: true
              text: "Find home"
              onClicked: root.centreGlobeOnHome()
            }
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

        // ---- the game: the face on the left, the words on the right. Set
        // the clock turns the hands; Read the clock offers four times to
        // choose from. Nothing here knows about the sun.
        Item {
          id: gameArea
          visible: root.playing
          anchors.fill: parent
          anchors.bottomMargin: toolbar.height + content.gap
          readonly property int faceSize: Math.min(height, Math.round(width * 0.46))
          readonly property bool reading: root.currentRound && root.currentRound.mode === "read"

          Face {
            id: gameFace
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: gameArea.faceSize
            height: width
            minutesOfDay: gameArea.reading
              ? (root.currentRound ? root.currentRound.shownMinutes : 0)
              : (root.game ? root.game.minutesOfDay : 0)
            solved: root.solved
          }

          Column {
            id: gameColumn
            anchors.left: gameFace.right
            anchors.leftMargin: content.gap * 3
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.md

            Flow {
              width: parent.width
              spacing: Style.spacing.md
              ActionButton {
                compact: true
                primary: root.gameMode === "set"
                text: "Set the clock"
                onClicked: if (root.gameMode !== "set") root.switchGameMode()
              }
              ActionButton {
                compact: true
                primary: root.gameMode === "read"
                text: "Read the clock"
                onClicked: if (root.gameMode !== "read") root.switchGameMode()
              }
              ActionButton {
                compact: true
                visible: root.gameMode === "set" && !root.solved
                text: "Start again"
                onClicked: if (root.currentRound) root.hands = root.currentRound.startHands
              }
              ActionButton {
                compact: true
                visible: root.solved
                text: "Another one  →"
                onClicked: root.nextRound()
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.currentRound ? root.currentRound.prompt : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
              wrapMode: Text.WordWrap
            }

            // Set the clock: the answer in digits as well as words, so the
            // two ways of saying a time sit together.
            Text {
              width: parent.width
              visible: !gameArea.reading && text !== ""
              textFormat: Text.PlainText
              text: root.currentRound && !gameArea.reading ? root.currentRound.digits : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              font.bold: true
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: !root.currentRound ? ""
                : (root.solved ? root.currentRound.solvedSentence
                  : (root.wrongPick ? "Not that one. Look at the short hand first: which numeral has it just gone past?"
                    : root.currentRound.task))
              color: root.solved ? root.sunColor : root.quiet
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              wrapMode: Text.WordWrap
              Behavior on color { ColorAnimation { duration: 300 } }
            }

            // Set the clock: how far off the hands are, in words.
            Text {
              width: parent.width
              visible: !gameArea.reading && text !== ""
              textFormat: Text.PlainText
              text: !root.game || root.solved ? "" : root.game.hint
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              wrapMode: Text.WordWrap
            }

            Item { width: 1; height: Style.spacing.lg }

            // Set the clock: four buttons that turn the hands.
            Row {
              visible: !gameArea.reading
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.spacing.xl
              TurnButton { glyph: "«"; caption: "an hour"; delta: -60 }
              TurnButton { glyph: "‹"; caption: root.stepWords; delta: -root.gameStep }
              TurnButton { glyph: "›"; caption: root.stepWords; delta: root.gameStep }
              TurnButton { glyph: "»"; caption: "an hour"; delta: 60 }
            }

            // Read the clock: four times to choose between.
            Grid {
              id: choiceGrid
              visible: gameArea.reading
              width: parent.width
              columns: 2
              spacing: Style.spacing.lg
              readonly property real cellW: (width - spacing) / 2

              Repeater {
                model: gameArea.reading && root.currentRound ? root.currentRound.choices.length : 0

                Rectangle {
                  id: choiceTile
                  required property int index
                  readonly property var choice: root.currentRound.choices[index]
                  readonly property bool picked: root.chosen === index
                  readonly property bool correct: picked && choice.right
                  readonly property bool mistaken: picked && !choice.right
                  width: choiceGrid.cellW
                  height: Style.space(76)
                  radius: root.cornerRadius
                  color: correct ? Util.alpha(root.sunColor, 0.22)
                    : (mistaken ? Util.alpha(root.foreground, 0.10) : Util.alpha(root.foreground, 0.05))
                  border.width: Math.max(2, Style.space(2))
                  border.color: correct ? root.sunColor
                    : (mistaken ? Util.alpha(root.foreground, 0.30) : Util.alpha(root.foreground, 0.18))
                  opacity: root.solved && !correct ? 0.4 : 1
                  Behavior on color { ColorAnimation { duration: 160 } }
                  Behavior on opacity { NumberAnimation { duration: 160 } }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pickTime(choiceTile.index)
                  }

                  Column {
                    anchors.centerIn: parent
                    width: parent.width - Style.spacing.xl * 2
                    spacing: Style.spacing.xs

                    Text {
                      width: parent.width
                      horizontalAlignment: Text.AlignHCenter
                      textFormat: Text.PlainText
                      text: choiceTile.choice.words
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.heading
                      font.bold: true
                      elide: Text.ElideRight
                    }
                    Text {
                      width: parent.width
                      horizontalAlignment: Text.AlignHCenter
                      textFormat: Text.PlainText
                      text: choiceTile.choice.digits
                      color: root.quiet
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                    }
                  }
                }
              }
            }
          }
        }


        // ---- the bottom row is navigation and nothing else: where you can
        // go from here, and the way back. What the screen you are on can do
        // lives on that screen, next to the thing it acts on, so a button
        // never means "go somewhere" and "change something" in the same row.
        Item {
          id: toolbar
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Math.max(actions.implicitHeight, closeButton.implicitHeight)

          readonly property bool onClock: !root.playing && !root.showPeople && !root.showMe && !root.showEarth

          Flow {
            id: actions
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            width: parent.width - closeButton.width - Style.spacing.lg
            spacing: Style.spacing.lg

            // Back is always first, and always means one step out.
            ActionButton {
              visible: !toolbar.onClock
              text: "←  Back"
              onClicked: root.stepBack()
            }

            // From the clock: everywhere there is to go.
            ActionButton { visible: toolbar.onClock && root.hasFace; text: "Play"; onClicked: root.startGame() }
            ActionButton { visible: toolbar.onClock; text: "Earth"; onClicked: root.openEarth("globe") }
            ActionButton { visible: toolbar.onClock; text: "People"; onClicked: root.openPeople() }
            ActionButton { visible: toolbar.onClock; text: "Me"; onClicked: root.openMe() }
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
