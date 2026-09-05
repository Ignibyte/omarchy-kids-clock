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
  readonly property string sourceDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""

  // Settings live on the bar widget's inline shell.json entry.
  readonly property var config: shell && shell.shellConfig ? Model.settingsFor(shell.shellConfig, pluginId) : ({})
  readonly property string band: String(Model.setting(config, "band", "explorer"))
  readonly property var rules: Model.bandRules(band)
  readonly property string hourFormat: String(Model.setting(config, "hourFormat", "12"))
  readonly property var routine: Model.routineFrom(config)
  // The shell.json entry may be the bare id (that is what `omarchy plugin
  // enable` writes), so every default lives here, not only in the manifest.
  readonly property string peopleText: String(Model.setting(config, "people", Model.DEFAULT_PEOPLE))
  readonly property string homeCitySetting: String(Model.setting(config, "homeCity", ""))

  property var cities: []
  // Natural Earth 1:110m land outlines, rings of [lon, lat, ...], for the map.
  property var land: []
  readonly property var people: Model.parsePeople(peopleText, cities, rules.maxPeople)

  // Home: the system zone, its offset straight from the JavaScript Date,
  // and coordinates from the city list when the zone or the setting matches.
  property string homeZone: ""
  readonly property int homeOffsetSeconds: -(new Date(nowMs).getTimezoneOffset()) * 60
  readonly property var homeCity: Model.findCity(cities, homeCitySetting !== "" ? homeCitySetting : homeZone)
  readonly property string homeName: homeCity ? homeCity.name
    : (homeCitySetting !== "" ? homeCitySetting : (homeZone !== "" ? homeZone.split("/").pop().replace(/_/g, " ") : "home"))

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
  }

  function refreshOffsets() {
    var epoch = shownMs / 1000
    for (var i = 0; i < people.length; i++) {
      (function(zone) {
        root.enqueue(Model.offsetCommand(zone, epoch), function(exitCode, text) {
          var parsed = exitCode === 0 ? Model.parseOffsetLine(text) : null
          if (!parsed) return
          var updated = Object.assign({}, root.offsets)
          updated[zone] = parsed
          root.offsets = updated
        })
      })(people[i].zone)
    }
  }

  onPeopleChanged: refreshOffsets()

  Process {
    id: process
    // waitForEnd makes onExited see the whole output; without it the exit
    // can land before the stream is drained.
    stdout: StdioCollector { id: output; waitForEnd: true }
    onExited: function(exitCode) {
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

  onSourceDirChanged: if (sourceDir !== "") { citiesFile.reload(); landFile.reload() }

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
