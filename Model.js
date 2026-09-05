// Pure logic for the Sun Clock: where the sun is over a place, what the
// people there are probably doing, and the words a child reads. No Qt in
// here, so `node test/model-test.js` runs it.

var MS_PER_DAY = 86400000
var MS_PER_MINUTE = 60000

// What a fresh install shows before a parent names real people: three
// examples spread around the world, so the clock does something at once.
var DEFAULT_PEOPLE = "Grandma=Phoenix; Cousin Mia=Berlin; Uncle Ken=Tokyo"

var BANDS = {
  explorer:  { maxPeople: 3, digits: false, dayLabel: false, offsets: false, label: "Explorer" },
  tinkerer:  { maxPeople: 4, digits: true,  dayLabel: true,  offsets: false, label: "Tinkerer" },
  navigator: { maxPeople: 6, digits: true,  dayLabel: true,  offsets: true,  label: "Navigator" }
}

function bandRules(band) {
  var key = String(band || "").toLowerCase()
  return BANDS[key] || BANDS.explorer
}

function trim(value) {
  return String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
}

// ---- settings

// The plugin's inline entry in shell.json: a bar widget entry in one of the
// three sections, or a plugins[] entry. Same walk the Stay Awake plugin uses.
function settingsFor(shellConfig, pluginId) {
  var id = String(pluginId || "")
  if (!shellConfig || typeof shellConfig !== "object") return {}
  var bar = shellConfig.bar
  if (bar && typeof bar === "object" && bar.layout && typeof bar.layout === "object") {
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var entries = bar.layout[sections[s]]
      if (!Array.isArray(entries)) continue
      for (var i = 0; i < entries.length; i++) {
        if (entries[i] && String(entries[i].id) === id) return entries[i]
      }
    }
  }
  if (Array.isArray(shellConfig.plugins)) {
    for (var p = 0; p < shellConfig.plugins.length; p++) {
      if (shellConfig.plugins[p] && String(shellConfig.plugins[p].id) === id) return shellConfig.plugins[p]
    }
  }
  return {}
}

function setting(settings, key, fallback) {
  var value = settings ? settings[key] : undefined
  return value === undefined || value === null || value === "" ? fallback : value
}

// "07:30" -> 450 minutes. Anything unreadable falls back.
function parseClock(text, fallbackMinutes) {
  var m = /^\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*$/i.exec(String(text || ""))
  if (!m) return fallbackMinutes
  var hour = parseInt(m[1], 10)
  var minute = m[2] ? parseInt(m[2], 10) : 0
  if (m[3]) {
    var pm = m[3].toLowerCase() === "pm"
    if (hour === 12) hour = pm ? 12 : 0
    else if (pm) hour += 12
  }
  if (hour > 23 || minute > 59) return fallbackMinutes
  return hour * 60 + minute
}

function routineFrom(settings) {
  return {
    wake: parseClock(setting(settings, "wakeTime", ""), 7 * 60),
    schoolStart: parseClock(setting(settings, "schoolStart", ""), 8 * 60 + 30),
    schoolEnd: parseClock(setting(settings, "schoolEnd", ""), 15 * 60),
    dinner: parseClock(setting(settings, "dinnerTime", ""), 18 * 60),
    bed: parseClock(setting(settings, "bedTime", ""), 20 * 60)
  }
}

// ---- places

function normalizeKey(text) {
  return trim(text).toLowerCase().replace(/[\s_-]+/g, " ")
}

// A place by city name, by the zone's last segment ("Los_Angeles"), or by
// full zone id. Returns null when nothing matches.
function findCity(cities, query) {
  var q = normalizeKey(query)
  if (q === "" || !Array.isArray(cities)) return null
  for (var i = 0; i < cities.length; i++) {
    if (normalizeKey(cities[i].name) === q) return cities[i]
  }
  for (var j = 0; j < cities.length; j++) {
    var zone = String(cities[j].zone || "")
    if (normalizeKey(zone) === q) return cities[j]
    var tail = zone.split("/").pop()
    if (normalizeKey(tail) === q) return cities[j]
  }
  return null
}

// "Grandma=Phoenix; Cousin Mia=Europe/Berlin" -> people with a zone and,
// when the city is known, coordinates for the sun. Unknown cities with a
// slash are kept as bare zones (the arc then assumes six to six). Capped by
// the band.
function parsePeople(text, cities, maxPeople) {
  var out = []
  var parts = String(text || "").split(/[;\n]+/)
  for (var i = 0; i < parts.length && out.length < maxPeople; i++) {
    var pair = parts[i].split("=")
    if (pair.length < 2) continue
    var name = trim(pair[0])
    var where = trim(pair.slice(1).join("="))
    if (name === "" || where === "") continue
    var city = findCity(cities, where)
    if (city) {
      out.push({ name: name, city: city.name, zone: city.zone, lat: city.lat, lon: city.lon, known: true })
    } else if (where.indexOf("/") !== -1) {
      out.push({ name: name, city: where.split("/").pop().replace(/_/g, " "), zone: where, lat: null, lon: null, known: false })
    }
  }
  return out
}

// ---- time zones, through `date`

// argv for one zone at one instant. The shell runs it through a Process;
// output is "+HH:MM<TAB>ZONE<TAB>weekday(1-7)".
function offsetCommand(zone, epochSeconds) {
  return ["/usr/bin/env", "TZ=" + zone, "/usr/bin/date", "--date=@" + Math.floor(epochSeconds), "+%:z\t%Z\t%u"]
}

// "+05:30" -> 19800, "-0700" -> -25200.
function parseOffset(text) {
  var m = /^([+-])(\d{2}):?(\d{2})/.exec(trim(text))
  if (!m) return null
  var seconds = (parseInt(m[2], 10) * 60 + parseInt(m[3], 10)) * 60
  return m[1] === "-" ? -seconds : seconds
}

function parseOffsetLine(line) {
  var fields = String(line || "").split("\t")
  var offset = parseOffset(fields[0])
  if (offset === null) return null
  return { offsetSeconds: offset, abbreviation: trim(fields[1] || ""), weekday: parseInt(fields[2], 10) || 0 }
}

// Wall clock parts for an instant at a fixed UTC offset.
function localParts(utcMs, offsetSeconds) {
  var shifted = utcMs + offsetSeconds * 1000
  var dayIndex = Math.floor(shifted / MS_PER_DAY)
  var msIntoDay = shifted - dayIndex * MS_PER_DAY
  var minutes = Math.floor(msIntoDay / MS_PER_MINUTE)
  // 1970-01-01 was a Thursday: index 4 with Sunday as 0.
  var weekday = ((dayIndex + 4) % 7 + 7) % 7
  return {
    dayIndex: dayIndex,
    minutesOfDay: minutes,
    hour: Math.floor(minutes / 60),
    minute: minutes % 60,
    weekday: weekday,
    weekend: weekday === 0 || weekday === 6
  }
}

function formatTime(hour, minute, hourFormat) {
  var mm = (minute < 10 ? "0" : "") + minute
  if (String(hourFormat) === "24") return (hour < 10 ? "0" : "") + hour + ":" + mm
  var h = hour % 12
  if (h === 0) h = 12
  return h + ":" + mm + (hour < 12 ? " AM" : " PM")
}

// "yesterday", "today" or "tomorrow" there, relative to the home date.
function dayLabel(homeDayIndex, thereDayIndex) {
  var delta = thereDayIndex - homeDayIndex
  if (delta <= -1) return "yesterday"
  if (delta >= 1) return "tomorrow"
  return "today"
}

// "3 hours ahead", "2½ hours behind", "same time as home".
function offsetWords(offsetSeconds, homeOffsetSeconds) {
  var diff = offsetSeconds - homeOffsetSeconds
  if (diff === 0) return "same time as home"
  var hours = Math.abs(diff) / 3600
  var whole = Math.floor(hours)
  var frac = hours - whole
  var text = frac === 0 ? String(whole) : (frac === 0.5 ? (whole === 0 ? "half an" : whole + "½") : hours.toFixed(2))
  var unit = (hours === 1 || text === "half an") ? " hour" : " hours"
  return text + unit + (diff > 0 ? " ahead" : " behind")
}

// ---- the sun

function toRadians(deg) { return deg * Math.PI / 180 }
function toDegrees(rad) { return rad * 180 / Math.PI }

// Sunrise and sunset (UTC ms) for the local civil day that holds `utcMs`
// at a place, from the standard sunrise equation with -0.833° for
// refraction and the solar disc. `polar` is "day" or "night" when the sun
// never sets or never rises there that day.
function solarTimes(utcMs, lat, lon, offsetSeconds) {
  var localMidnight = Math.floor((utcMs + offsetSeconds * 1000) / MS_PER_DAY) * MS_PER_DAY - offsetSeconds * 1000
  var localNoon = localMidnight + MS_PER_DAY / 2
  var julianNoon = localNoon / MS_PER_DAY + 2440587.5
  var n = Math.round(julianNoon - 2451545.0 + 0.0008)
  var meanSolar = n - lon / 360
  var anomaly = (357.5291 + 0.98560028 * meanSolar) % 360
  var center = 1.9148 * Math.sin(toRadians(anomaly)) + 0.0200 * Math.sin(toRadians(2 * anomaly)) + 0.0003 * Math.sin(toRadians(3 * anomaly))
  var eclipticLon = (anomaly + center + 180 + 102.9372) % 360
  var transit = 2451545.0 + meanSolar + 0.0053 * Math.sin(toRadians(anomaly)) - 0.0069 * Math.sin(toRadians(2 * eclipticLon))
  var declination = Math.asin(Math.sin(toRadians(eclipticLon)) * Math.sin(toRadians(23.4397)))
  var cosHourAngle = (Math.sin(toRadians(-0.833)) - Math.sin(toRadians(lat)) * Math.sin(declination))
    / (Math.cos(toRadians(lat)) * Math.cos(declination))
  var transitMs = (transit - 2440587.5) * MS_PER_DAY
  if (cosHourAngle >= 1) return { sunrise: null, sunset: null, transit: transitMs, polar: "night", dayStart: localMidnight }
  if (cosHourAngle <= -1) return { sunrise: null, sunset: null, transit: transitMs, polar: "day", dayStart: localMidnight }
  var hourAngle = toDegrees(Math.acos(cosHourAngle))
  var halfDay = hourAngle / 360 * MS_PER_DAY
  return { sunrise: transitMs - halfDay, sunset: transitMs + halfDay, transit: transitMs, polar: null, dayStart: localMidnight }
}

// Six-to-six stand-in for a place without coordinates.
function flatSolarTimes(utcMs, offsetSeconds) {
  var localMidnight = Math.floor((utcMs + offsetSeconds * 1000) / MS_PER_DAY) * MS_PER_DAY - offsetSeconds * 1000
  return { sunrise: localMidnight + 6 * 3600000, sunset: localMidnight + 18 * 3600000, transit: localMidnight + 12 * 3600000, polar: null, dayStart: localMidnight }
}

// Where the sun (by day) or the moon (by night) sits on its arc: `t` runs
// from 0 at one horizon to 1 at the other.
function skyPosition(utcMs, times) {
  if (times.polar === "day") return { isDay: true, t: ((utcMs - times.dayStart) / MS_PER_DAY + 1) % 1 }
  if (times.polar === "night") return { isDay: false, t: ((utcMs - times.dayStart) / MS_PER_DAY + 1) % 1 }
  if (utcMs >= times.sunrise && utcMs <= times.sunset) {
    return { isDay: true, t: (utcMs - times.sunrise) / (times.sunset - times.sunrise) }
  }
  if (utcMs < times.sunrise) {
    var previousSunset = times.sunset - MS_PER_DAY
    return { isDay: false, t: (utcMs - previousSunset) / (times.sunrise - previousSunset) }
  }
  var nextSunrise = times.sunrise + MS_PER_DAY
  return { isDay: false, t: (utcMs - times.sunset) / (nextSunrise - times.sunset) }
}

// ---- what people are doing

function timeWords(minutesOfDay) {
  var h = minutesOfDay / 60
  if (h < 5) return "the middle of the night"
  if (h < 7) return "early morning"
  if (h < 12) return "morning"
  if (h < 13) return "midday"
  if (h < 17) return "afternoon"
  if (h < 20) return "evening"
  return "night"
}

// The family's routine, projected onto a place. `call` is the answer to
// "can I call?": good, busy or asleep.
function activityAt(minutesOfDay, routine, weekend) {
  var m = minutesOfDay
  if (m < routine.wake || m >= routine.bed) return { key: "asleep", label: "fast asleep", awake: false, call: "asleep" }
  if (m < routine.wake + 45) return { key: "waking", label: "waking up and having breakfast", awake: true, call: "good" }
  if (!weekend && m >= routine.schoolStart && m < routine.schoolEnd) return { key: "school", label: "at school", awake: true, call: "busy" }
  if (m >= routine.dinner && m < routine.dinner + 45) return { key: "dinner", label: "having dinner", awake: true, call: "busy" }
  if (m >= routine.bed - 45) return { key: "bedtime", label: "getting ready for bed", awake: true, call: "good" }
  return { key: "playing", label: weekend ? "playing, it's the weekend" : "out of school and playing", awake: true, call: "good" }
}

function callWords(call) {
  if (call === "asleep") return "Asleep, call later"
  if (call === "busy") return "Probably busy"
  return "Good time to call"
}

function homeSentence(city, minutesOfDay) {
  return "It's " + timeWords(minutesOfDay) + " here in " + city + "."
}

function personSentence(person, minutesOfDay, activity, label) {
  var where = "In " + person.city + " it's " + timeWords(minutesOfDay)
  if (label && label !== "today") where += ", and it's already " + label
  if (label === "yesterday") where = "In " + person.city + " it's " + timeWords(minutesOfDay) + ", and it's still " + label
  return where + ". " + person.name + " is probably " + activity.label + "."
}

// Everything a card needs, for one person at one instant.
function buildRow(person, offsetInfo, utcMs, home, routine, rules, hourFormat) {
  var offset = offsetInfo ? offsetInfo.offsetSeconds : null
  if (offset === null || offset === undefined) {
    return { name: person.name, city: person.city, zone: person.zone, ready: false, isDay: true, t: 0.5,
      sentence: person.name + " in " + person.city + ": finding the time there...", call: "good", callWords: "", timeText: "", dayLabel: "", offsetWords: "" }
  }
  var parts = localParts(utcMs, offset)
  var times = person.lat === null || person.lat === undefined
    ? flatSolarTimes(utcMs, offset)
    : solarTimes(utcMs, person.lat, person.lon, offset)
  var sky = skyPosition(utcMs, times)
  var activity = activityAt(parts.minutesOfDay, routine, parts.weekend)
  var label = home ? dayLabel(home.dayIndex, parts.dayIndex) : "today"
  return {
    name: person.name,
    city: person.city,
    zone: person.zone,
    ready: true,
    isDay: sky.isDay,
    t: Math.max(0, Math.min(1, sky.t)),
    activity: activity.key,
    awake: activity.awake,
    call: activity.call,
    callWords: callWords(activity.call),
    sentence: personSentence(person, parts.minutesOfDay, activity, rules.dayLabel ? label : "today"),
    timeText: rules.digits ? formatTime(parts.hour, parts.minute, hourFormat) : "",
    dayLabel: rules.dayLabel ? label : "",
    offsetWords: rules.offsets && home ? offsetWords(offset, home.offsetSeconds) : "",
    abbreviation: offsetInfo.abbreviation || ""
  }
}

function buildHome(city, lat, lon, offsetSeconds, utcMs, rules, hourFormat) {
  var parts = localParts(utcMs, offsetSeconds)
  var times = lat === null || lat === undefined ? flatSolarTimes(utcMs, offsetSeconds) : solarTimes(utcMs, lat, lon, offsetSeconds)
  var sky = skyPosition(utcMs, times)
  return {
    city: city,
    offsetSeconds: offsetSeconds,
    dayIndex: parts.dayIndex,
    minutesOfDay: parts.minutesOfDay,
    isDay: sky.isDay,
    t: Math.max(0, Math.min(1, sky.t)),
    sentence: homeSentence(city, parts.minutesOfDay),
    timeText: rules.digits ? formatTime(parts.hour, parts.minute, hourFormat) : "",
    words: timeWords(parts.minutesOfDay)
  }
}

// The banner while the child moves the sun: "Pretend it's 3 hours later".
function scrubWords(scrubMinutes) {
  if (!scrubMinutes) return ""
  var hours = Math.abs(scrubMinutes) / 60
  var text = hours === Math.floor(hours) ? String(hours) : hours.toFixed(1)
  return "Pretend it's " + text + (hours === 1 ? " hour " : " hours ") + (scrubMinutes > 0 ? "later" : "earlier")
}

function tooltip(rows) {
  var parts = []
  for (var i = 0; i < rows.length; i++) {
    if (!rows[i].ready) continue
    parts.push(rows[i].name + ": " + (rows[i].awake ? rows[i].callWords.toLowerCase() : "asleep"))
  }
  return parts.length ? "Sun Clock · " + parts.join(" · ") : "Sun Clock"
}

// Bar glyphs: the weather plugin's clear-day and clear-night icons, which
// the bar font is known to carry.
var SUN_GLYPH = ""
var MOON_GLYPH = ""

function barGlyph(isDay) {
  return isDay ? SUN_GLYPH : MOON_GLYPH
}

if (typeof module !== "undefined") {
  module.exports = {
    bandRules: bandRules,
    settingsFor: settingsFor,
    setting: setting,
    parseClock: parseClock,
    routineFrom: routineFrom,
    findCity: findCity,
    parsePeople: parsePeople,
    offsetCommand: offsetCommand,
    parseOffset: parseOffset,
    parseOffsetLine: parseOffsetLine,
    localParts: localParts,
    formatTime: formatTime,
    dayLabel: dayLabel,
    offsetWords: offsetWords,
    solarTimes: solarTimes,
    flatSolarTimes: flatSolarTimes,
    skyPosition: skyPosition,
    timeWords: timeWords,
    activityAt: activityAt,
    callWords: callWords,
    personSentence: personSentence,
    homeSentence: homeSentence,
    buildRow: buildRow,
    buildHome: buildHome,
    scrubWords: scrubWords,
    tooltip: tooltip,
    barGlyph: barGlyph,
    DEFAULT_PEOPLE: DEFAULT_PEOPLE,
    SUN_GLYPH: SUN_GLYPH,
    MOON_GLYPH: MOON_GLYPH
  }
}
