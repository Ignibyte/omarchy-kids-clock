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

  // One process for the whole list: fifty zones for the globe come back in
  // one go rather than one `date` at a time.
  function fetchOffsets(zones) {
    if (!zones || zones.length === 0) return
    root.enqueue(Model.offsetsCommand(zones, shownMs / 1000), function(exitCode, text) {
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
      var zone = String(zones[i] || "")
      if (zone === "" || next.indexOf(zone) !== -1) continue
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

  onSourceDirChanged: if (sourceDir !== "") { citiesFile.reload(); landFile.reload(); globeFile.reload(); themeList.running = true }

  // ---- the themes, for the Theme screen: every theme folder with its
  // colours, the one in use, and the switch itself through omarchy-theme-set,
  // which re-tints this plugin along with everything else.
  property var themes: []
  property string themeSlug: ""
  readonly property string themeTitle: Model.themeTitle(themeSlug)

  Process {
    id: themeList
    command: ["bash", root.sourceDir + "/bin/list-themes"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.themes = Model.parseThemeLines(text)
    }
  }

  FileView {
    id: themeName
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onLoaded: root.themeSlug = String(text()).trim()
    onFileChanged: reload()
  }

  function applyTheme(slug) {
    var name = String(slug || "").replace(/[^A-Za-z0-9._-]/g, "")
    if (name === "" || themeSetter.running) return false
    themeSetter.command = ["omarchy-theme-set", name]
    themeSetter.running = true
    return true
  }

  Process {
    id: themeSetter
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("kids-clock: omarchy-theme-set exited with", exitCode)
      themeList.running = true
    }
  }

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
