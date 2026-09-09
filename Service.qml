import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The clock's shared state: the people, their zone offsets (found through
// `date`, since QML's JavaScript has no time zone tables), the ticking
// instant, and the scrub offset the child applies with the arrow keys. The
// bar chip and the overlay both read from here.
Item {
  id: root

  // Injected by the shell after construction; never read in onCompleted.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "ignibyte.kids-clock"
  // Where this plugin's own files are. Omarchy up to 4.0.2 stamped the path
  // onto the manifest; 4.0.3 strips it from the copy a third-party plugin is
  // handed, so the fallback asks QML where this very file sits, which is the
  // same directory and needs nothing from the shell.
  readonly property string sourceDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) : Model.dirFromUrl(Qt.resolvedUrl("."))

  // Settings live on the bar widget's inline shell.json entry. Omarchy up to
  // 4.0.2 injected the shell itself, with the whole config on `shellConfig`;
  // 4.0.3 injects a capability-scoped API whose `barConfig` is the bar half of
  // that same config, kept current as shell.json changes. Either shape finds
  // the entry.
  readonly property var liveConfig: !shell ? ({})
    : Model.settingsFor(shell.shellConfig ? shell.shellConfig : shell.barConfig, pluginId)

  // What was last handed to the shell to save. A saved entry has to go out to
  // the shell, into shell.json and back before the shell's copy says it, and
  // until it does, every screen would still be showing the person who has
  // just been removed — and worse, the next save would be built on top of
  // that stale entry and put them back. So the plugin believes its own write
  // until the shell agrees with it.
  property var pendingEntry: null

  function noteSaved(entry) {
    pendingEntry = entry && typeof entry === "object" ? entry : null
    if (pendingEntry) pendingWatchdog.restart()
  }

  onLiveConfigChanged: if (pendingEntry && Model.settingsLanded(liveConfig, pendingEntry)) {
    pendingEntry = null
    pendingWatchdog.stop()
  }

  // A write that never comes back (the shell refused it, the file is not
  // writable) must not leave the screens showing something that was never
  // saved. After a few seconds the plugin goes back to what the shell says.
  Timer {
    id: pendingWatchdog
    interval: 5000
    repeat: false
    onTriggered: {
      if (!root.pendingEntry) return
      console.warn("kids-clock: a saved setting did not come back from the shell; showing what it says instead")
      root.pendingEntry = null
    }
  }

  readonly property var config: pendingEntry ? pendingEntry : liveConfig
  readonly property string band: String(Model.setting(config, "band", "explorer"))
  readonly property var rules: Model.bandRules(band)
  readonly property string hourFormat: String(Model.setting(config, "hourFormat", "12"))
  readonly property var routine: Model.routineFrom(config)
  // The shell.json entry may be the bare id (that is what `omarchy plugin
  // enable` writes), so every default lives here, not only in the manifest.
  // An entry with no people key shows the examples; an empty string, which
  // is what removing everyone leaves behind, shows nobody.
  readonly property string peopleText: config.people === undefined || config.people === null ? Model.DEFAULT_PEOPLE : String(config.people)
  readonly property string homeCitySetting: String(Model.setting(config, "homeCity", ""))

  property var cities: []
  // Natural Earth 1:110m land outlines, rings of [lon, lat, ...], for the map.
  property var land: []
  // Land samples for the globe, flat [lon, lat, ...].
  property var globeDots: []
  readonly property var people: Model.parsePeople(peopleText, cities, rules.maxPeople)

  // Home: the system zone, its offset straight from the JavaScript Date,
  // and coordinates from the city list when the zone or the setting matches.
  property string homeZone: ""
  readonly property int homeOffsetSeconds: -(new Date(nowMs).getTimezoneOffset()) * 60
  // The place the setting names, when the city list knows it. The setting is
  // free text: anything can be typed there, and a hamlet the list has never
  // heard of is still what home is called.
  readonly property var namedCity: Model.findCity(cities, homeCitySetting)
  // Where home sits on the map and the globe, and which sunrise its sky
  // follows: the named city when there is one, otherwise the city that stands
  // for the computer's time zone. The clock itself never leaves that zone.
  readonly property var homeCity: namedCity ? namedCity : Model.findCity(cities, homeZone)
  readonly property string homeName: homeCitySetting !== ""
    ? (namedCity ? namedCity.name : homeCitySetting)
    : (homeCity ? homeCity.name : (homeZone !== "" ? homeZone.split("/").pop().replace(/_/g, " ") : "home"))

  // The instant shown: now, plus whatever the child has scrubbed.
  property double nowMs: Date.now()
  property int scrubMinutes: 0
  readonly property double shownMs: nowMs + scrubMinutes * 60000
  readonly property string scrubWords: Model.scrubWords(scrubMinutes)

  // zone -> { offsetSeconds, abbreviation }
  property var offsets: ({})

  readonly property var home: Model.buildHome(homeName, homeCity ? homeCity.lat : null, homeCity ? homeCity.lon : null,
    homeOffsetSeconds, shownMs, rules, hourFormat)

  readonly property var rows: {
    var out = []
    for (var i = 0; i < people.length; i++) {
      out.push(Model.buildRow(people[i], offsets[people[i].zone], shownMs, home, routine, rules, hourFormat))
    }
    return out
  }

  readonly property string barGlyph: Model.barGlyph(home.isDay)
  readonly property string tooltip: Model.tooltip(rows)

  function scrub(deltaMinutes) {
    var next = scrubMinutes + deltaMinutes
    if (next > 48 * 60) next = 48 * 60
    if (next < -48 * 60) next = -48 * 60
    scrubMinutes = next
  }

  function resetScrub() { scrubMinutes = 0 }

  // ---- zone offsets through `date`, one process at a time. Setting
  // `running` on a Process that is already running is a no-op that loses the
  // command, so the jobs queue and the exit handler starts the next one.
  property var queue: []
  property var currentJob: null

  function enqueue(command, callback) {
    var next = queue.slice()
    next.push({ command: command, callback: callback })
    queue = next
    runNext()
  }

  function runNext() {
    if (process.running || currentJob || queue.length === 0) return
    var next = queue.slice()
    currentJob = next.shift()
    queue = next
    process.command = currentJob.command
    process.running = true
    jobWatchdog.restart()
  }

  // A job that never exits (a process that failed to start, or one stuck
  // behind something that blocks) would hold the queue for good; after half
  // a minute it is dropped and the queue moves on.
  Timer {
    id: jobWatchdog
    interval: 30000
    repeat: false
    onTriggered: {
      if (!root.currentJob) return
      console.warn("kids-clock: a zone lookup did not finish in time; moving on")
      process.running = false
      root.currentJob = null
      root.runNext()
    }
  }

  // One process for the whole list: fifty zones for the globe come back in
  // one go rather than one `date` at a time.
  // Offsets are taken at the real instant, the same one home's offset comes
  // from, so home and the people never sit on different sides of a
  // daylight-saving change while the sun is being moved.
  function fetchOffsets(zones) {
    var wanted = []
    for (var i = 0; i < (zones || []).length; i++) if (Model.isZone(zones[i])) wanted.push(String(zones[i]).trim())
    if (wanted.length === 0) return
    root.enqueue(Model.offsetsCommand(wanted, nowMs / 1000), function(exitCode, text) {
      var parsed = Model.parseOffsetLines(text)
      var updated = Object.assign({}, root.offsets)
      var any = false
      for (var zone in parsed) { updated[zone] = parsed[zone]; any = true }
      if (any) root.offsets = updated
    })
  }

  function refreshOffsets() {
    var zones = []
    for (var i = 0; i < people.length; i++) zones.push(people[i].zone)
    fetchOffsets(zones.concat(extraZones))
  }

  // Zones the globe asks about beyond the people's: fetched once when asked
  // for, then kept fresh with the rest.
  property var extraZones: []

  function requestZones(zones) {
    var next = extraZones.slice()
    var added = []
    for (var i = 0; i < (zones || []).length; i++) {
      var zone = String(zones[i] || "").trim()
      if (!Model.isZone(zone) || next.indexOf(zone) !== -1) continue
      next.push(zone)
      added.push(zone)
    }
    if (added.length === 0) return
    extraZones = next
    fetchOffsets(added)
  }

  onPeopleChanged: refreshOffsets()

  Process {
    id: process
    // waitForEnd makes onExited see the whole output; without it the exit
    // can land before the stream is drained.
    stdout: StdioCollector { id: output; waitForEnd: true }
    onExited: function(exitCode) {
      jobWatchdog.stop()
      var job = root.currentJob
      root.currentJob = null
      if (job && job.callback) job.callback(exitCode, output.text)
      root.runNext()
    }
  }

  // The system zone name, for the home label and the home coordinates.
  Process {
    id: zoneProcess
    command: ["timedatectl", "show", "-p", "Timezone", "--value"]
    running: true
    stdout: StdioCollector {
      onStreamFinished: root.homeZone = String(text).trim()
    }
  }

  FileView {
    id: citiesFile
    path: root.sourceDir === "" ? "" : root.sourceDir + "/data/cities.json"
    printErrors: true
    onLoaded: {
      try { root.cities = JSON.parse(text()) } catch (e) { console.warn("kids-clock: cities.json unreadable:", e) }
    }
  }

  FileView {
    id: landFile
    path: root.sourceDir === "" ? "" : root.sourceDir + "/data/land.json"
    printErrors: true
    onLoaded: {
      try { root.land = JSON.parse(text()) } catch (e) { console.warn("kids-clock: land.json unreadable:", e) }
    }
  }

  FileView {
    id: globeFile
    path: root.sourceDir === "" ? "" : root.sourceDir + "/data/globe.json"
    printErrors: true
    onLoaded: {
      try { root.globeDots = JSON.parse(text()) } catch (e) { console.warn("kids-clock: globe.json unreadable:", e) }
    }
  }

  function loadData() {
    if (sourceDir === "") return
    citiesFile.reload()
    landFile.reload()
    globeFile.reload()
  }

  // The directory is known before the shell injects anything now, so the
  // change handler alone would never fire.
  onSourceDirChanged: loadData()
  Component.onCompleted: loadData()

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  // Offsets move only at daylight-saving changes; five minutes is plenty.
  Timer {
    interval: 5 * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refreshOffsets()
  }
}
