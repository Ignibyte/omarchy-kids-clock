// Pure logic for the Sun Clock: where the sun is over a place, what the
// people there are probably doing, and the words a child reads. No Qt in
// here, so `node test/model-test.js` runs it.

var MS_PER_DAY = 86400000
var MS_PER_MINUTE = 60000

// What a fresh install shows before a parent names real people: three
// examples spread around the world, so the clock does something at once.
var DEFAULT_PEOPLE = "Grandma=Phoenix; Cousin Mia=Berlin; Uncle Ken=Tokyo"

// `face` is the analog clock beside the digits; `gameStep` is how finely
// the set-the-clock game rounds a target: quarter hours for the band that
// is learning "half past" and "quarter to", five minutes after that. `map`
// is the world map with the night side, for the band that reads maps.
var BANDS = {
  explorer:  { maxPeople: 3, digits: false, dayLabel: false, offsets: false, face: false, gameStep: 0,  map: false, label: "Explorer" },
  tinkerer:  { maxPeople: 4, digits: true,  dayLabel: true,  offsets: false, face: true,  gameStep: 15, map: false, label: "Tinkerer" },
  navigator: { maxPeople: 6, digits: true,  dayLabel: true,  offsets: true,  face: true,  gameStep: 5,  map: true,  label: "Navigator" }
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

// A place by city name, by "City, Region" or "City, Country" when the name
// is shared, by the zone's last segment ("Los_Angeles"), or by full zone
// id. The list is ordered by size, so a bare shared name means the biggest.
// Returns null when nothing matches.
function findCity(cities, query) {
  var raw = trim(query)
  if (raw === "" || !Array.isArray(cities)) return null
  var comma = raw.indexOf(",")
  var q = normalizeKey(comma === -1 ? raw : raw.slice(0, comma))
  var qualifier = comma === -1 ? "" : normalizeKey(raw.slice(comma + 1))
  var first = null
  for (var i = 0; i < cities.length; i++) {
    if (normalizeKey(cities[i].name) !== q && normalizeKey(cities[i].ascii) !== q) continue
    if (qualifier === "") return cities[i]
    if (normalizeKey(cities[i].region) === qualifier || normalizeKey(cities[i].country) === qualifier) return cities[i]
    if (!first) first = cities[i]
  }
  if (first) return first
  for (var j = 0; j < cities.length; j++) {
    var zone = String(cities[j].zone || "")
    if (normalizeKey(zone) === q) return cities[j]
    var tail = zone.split("/").pop()
    if (normalizeKey(tail) === q) return cities[j]
  }
  return null
}

// What to store for a chosen place: the bare name when it is the only one,
// otherwise "Name, Region" (or "Name, Country") so it comes back as itself.
function cityKey(cities, city) {
  var count = 0
  for (var i = 0; i < cities.length; i++) if (normalizeKey(cities[i].name) === normalizeKey(city.name)) count++
  if (count <= 1) return city.name
  return city.name + ", " + (city.region ? city.region : city.country)
}

// "Name, Country", with the region added when another city in the same
// list shares the name.
function cityLabel(city, cities) {
  var shared = false
  for (var i = 0; i < cities.length; i++) {
    if (cities[i] !== city && normalizeKey(cities[i].name) === normalizeKey(city.name)) { shared = true; break }
  }
  var parts = [city.name]
  if (shared && city.region) parts.push(city.region)
  if (city.country) parts.push(city.country)
  return parts.join(", ")
}

// Places whose name starts with what was typed, then places that contain
// it, each in list order (biggest first); an accented name also answers to
// its plain spelling. Two letters is enough to start.
function searchCities(cities, query, limit) {
  var q = normalizeKey(query)
  var max = limit > 0 ? limit : 6
  var out = []
  if (q.length < 2 || !Array.isArray(cities)) return out
  var starts = [], contains = []
  for (var i = 0; i < cities.length; i++) {
    var name = normalizeKey(cities[i].name)
    var ascii = cities[i].ascii ? normalizeKey(cities[i].ascii) : name
    if (name.indexOf(q) === 0 || ascii.indexOf(q) === 0) starts.push(cities[i])
    else if (name.indexOf(q) !== -1 || ascii.indexOf(q) !== -1) contains.push(cities[i])
  }
  var picked = starts.concat(contains).slice(0, max)
  for (var p = 0; p < picked.length; p++) {
    out.push({ city: picked[p], label: cityLabel(picked[p], picked), key: cityKey(cities, picked[p]) })
  }
  return out
}

// ---- editing the people setting

// Every "Name=Where" pair in the setting, uncapped and unresolved, so the
// People screen can list, remove and re-save entries it cannot place.
function parsePeopleRaw(text) {
  var out = []
  var parts = String(text || "").split(/[;\n]+/)
  for (var i = 0; i < parts.length; i++) {
    var pair = parts[i].split("=")
    if (pair.length < 2) continue
    var name = trim(pair[0])
    var where = trim(pair.slice(1).join("="))
    if (name === "" || where === "") continue
    out.push({ name: name, where: where })
  }
  return out
}

function peopleString(entries) {
  var parts = []
  for (var i = 0; i < entries.length; i++) {
    parts.push(trim(entries[i].name).replace(/[;=]/g, " ") + "=" + trim(entries[i].where).replace(/[;=]/g, " "))
  }
  return parts.join("; ")
}

function addPerson(text, name, where) {
  var entries = parsePeopleRaw(text)
  entries.push({ name: name, where: where })
  return peopleString(entries)
}

function removePerson(text, index) {
  var entries = parsePeopleRaw(text)
  if (index < 0 || index >= entries.length) return peopleString(entries)
  entries.splice(index, 1)
  return peopleString(entries)
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

// argv for many zones at once, through bash: one line per zone,
// "ZONE<TAB>+HH:MM<TAB>ABBR<TAB>weekday(1-7)". The tabs in the date format
// are real tab characters, which date prints as they are.
function offsetsCommand(zones, epochSeconds) {
  var script = "for zone in \"$@\"; do printf '%s\\t' \"$zone\"; TZ=\"$zone\" /usr/bin/date --date=@"
    + Math.floor(epochSeconds) + " '+%:z\t%Z\t%u' || echo; done"
  return ["/usr/bin/bash", "-c", script, "kids-clock"].concat(zones || [])
}

// The lines offsetsCommand prints, as a map from zone to offset info.
function parseOffsetLines(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var tab = lines[i].indexOf("\t")
    if (tab <= 0) continue
    var info = parseOffsetLine(lines[i].slice(tab + 1))
    if (info) out[lines[i].slice(0, tab)] = info
  }
  return out
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
  // The mean longitude rather than anomaly plus a fixed perihelion: the
  // perihelion drifts about 1.7 degrees a century, which by the 2020s put
  // the equinox half a day late.
  var meanLongitude = (280.4665 + 0.98564736 * meanSolar) % 360
  var eclipticLon = (meanLongitude + center) % 360
  var transit = 2451545.0 + meanSolar + 0.0053 * Math.sin(toRadians(anomaly)) - 0.0069 * Math.sin(toRadians(2 * eclipticLon))
  var declination = Math.asin(Math.sin(toRadians(eclipticLon)) * Math.sin(toRadians(23.4397)))
  var cosHourAngle = (Math.sin(toRadians(-0.833)) - Math.sin(toRadians(lat)) * Math.sin(declination))
    / (Math.cos(toRadians(lat)) * Math.cos(declination))
  var transitMs = (transit - 2440587.5) * MS_PER_DAY
  var decDegrees = toDegrees(declination)
  if (cosHourAngle >= 1) return { sunrise: null, sunset: null, transit: transitMs, polar: "night", dayStart: localMidnight, declination: decDegrees }
  if (cosHourAngle <= -1) return { sunrise: null, sunset: null, transit: transitMs, polar: "day", dayStart: localMidnight, declination: decDegrees }
  var hourAngle = toDegrees(Math.acos(cosHourAngle))
  var halfDay = hourAngle / 360 * MS_PER_DAY
  return { sunrise: transitMs - halfDay, sunset: transitMs + halfDay, transit: transitMs, polar: null, dayStart: localMidnight, declination: decDegrees }
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

// ---- the analog face and the set-the-clock game

function mod(n, m) { return ((n % m) + m) % m }

function clamp01(x) { return Math.max(0, Math.min(1, x)) }

// Minutes of day rounded to the nearest step, wrapping at midnight.
function roundMinutes(minutesOfDay, step) {
  var s = step > 0 ? step : 1
  return mod(Math.round(minutesOfDay / s) * s, 1440)
}

// Hand angles in degrees clockwise from twelve. The hour hand is geared to
// the minutes, so at half past it sits halfway to the next numeral.
function handAngles(minutesOfDay) {
  var m = mod(minutesOfDay, 720)
  return { hour: m / 2, minute: (m % 60) * 6 }
}

var HOUR_WORDS = ["twelve", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven"]
var MINUTE_WORDS = { 5: "five", 10: "ten", 20: "twenty", 25: "twenty-five" }

// The face read aloud the way school teaches it: "half past two", "quarter
// to three", "ten past four", "7 minutes to five".
function clockWords(minutesOfDay) {
  var m = mod(minutesOfDay, 1440)
  var hour = HOUR_WORDS[Math.floor(m / 60) % 12]
  var next = HOUR_WORDS[(Math.floor(m / 60) + 1) % 12]
  var minute = m % 60
  if (minute === 0) return hour + " o'clock"
  if (minute === 15) return "quarter past " + hour
  if (minute === 30) return "half past " + hour
  if (minute === 45) return "quarter to " + next
  if (minute < 30) return (MINUTE_WORDS[minute] || minute + " minutes") + " past " + hour
  var to = 60 - minute
  return (MINUTE_WORDS[to] || to + " minutes") + " to " + next
}

// "in the morning", "in the afternoon", "in the evening", "at night".
function dayPartWords(minutesOfDay) {
  var h = mod(minutesOfDay, 1440) / 60
  if (h < 5) return "at night"
  if (h < 12) return "in the morning"
  if (h < 17) return "in the afternoon"
  if (h < 20) return "in the evening"
  return "at night"
}

function solarTimesFor(utcMs, place, offsetSeconds) {
  return place.lat === null || place.lat === undefined
    ? flatSolarTimes(utcMs, offsetSeconds)
    : solarTimes(utcMs, place.lat, place.lon, offsetSeconds)
}

// One round of the game: a person, their time frozen when the round starts
// and rounded to the band's step, and where the hands begin. They start at
// twelve in the same half of the day, like a toy clock reset, so the child
// sets the hour and then the minutes without a trip round the other half.
// The goal is where the sun or the moon sits at the rounded target, so the
// moving body lands exactly in the ring when the hands are right.
function gameRound(person, offsetInfo, frozenMs, routine, rules, hourFormat) {
  var offset = offsetInfo.offsetSeconds
  var parts = localParts(frozenMs, offset)
  var step = rules && rules.gameStep > 0 ? rules.gameStep : 5
  var target = roundMinutes(parts.minutesOfDay, step)
  var start = target < 720 ? 0 : 720
  if (start === target) start = mod(target - 180, 1440)
  var goalMs = frozenMs + (target - parts.minutesOfDay) * MS_PER_MINUTE
  var goal = skyPosition(goalMs, solarTimesFor(goalMs, person, offset))
  var activity = activityAt(target, routine, parts.weekend)
  var words = clockWords(target) + " " + dayPartWords(target)
  return {
    name: person.name,
    city: person.city,
    zone: person.zone,
    lat: person.lat === undefined ? null : person.lat,
    lon: person.lon === undefined ? null : person.lon,
    offsetSeconds: offset,
    frozenMs: frozenMs,
    exactMinutes: parts.minutesOfDay,
    targetMinutes: target,
    startHands: start,
    targetWords: words,
    targetDigits: rules && rules.digits ? formatTime(Math.floor(target / 60), target % 60, hourFormat) : "",
    prompt: "It's about " + words + " in " + person.city + ".",
    task: "Turn the hands until the " + (goal.isDay ? "sun" : "moon") + " sits in the ring.",
    solvedSentence: "That's it! In " + person.city + " it's about " + words + ". " + person.name + " is probably " + activity.label + ".",
    goalIsDay: goal.isDay,
    goalT: clamp01(goal.t)
  }
}

// The face and the sky for the hands as the child has set them. `hands` is
// a running count of minutes, so turning on past midnight keeps the sky
// moving instead of jumping. `delta` is the shortest way to the target in
// minutes, signed; zero is solved. Twelve hours off is the trap the sky
// exists to show: the hands read right and the sky says otherwise.
function gameView(round, hands) {
  var minutes = mod(hands, 1440)
  var instant = round.frozenMs + (hands - round.exactMinutes) * MS_PER_MINUTE
  var sky = skyPosition(instant, solarTimesFor(instant, round, round.offsetSeconds))
  var delta = mod(round.targetMinutes - hands + 720, 1440) - 720
  var hint
  if (delta === 0) hint = "That's it!"
  else if (Math.abs(delta) === 720) hint = "The hands are right, but it's the wrong half of the day. Keep going round."
  else if (Math.abs(delta) <= 30) hint = delta > 0 ? "Nearly. A little further on." : "Nearly. A little back."
  else hint = delta > 0 ? "Turn the hands forward." : "Turn the hands back."
  return {
    minutesOfDay: minutes,
    angles: handAngles(minutes),
    isDay: sky.isDay,
    t: clamp01(sky.t),
    delta: delta,
    solved: delta === 0,
    hint: hint
  }
}

// ---- the map

// Where the sun is straight overhead. The latitude is the declination; the
// longitude follows Greenwich solar noon (the transit at longitude zero) at
// fifteen degrees an hour, east positive.
function subsolarPoint(utcMs) {
  var times = solarTimes(utcMs, 0, 0, 0)
  var lon = ((times.transit - utcMs) / 3600000) * 15
  lon = ((lon + 180) % 360 + 360) % 360 - 180
  return { lat: times.declination, lon: lon }
}

// The night side of the world at an instant, as [lon, lat] pairs: the
// terminator from west to east, then round the dark pole. With the sun
// overhead at declination d, the terminator at hour angle H sits where
// tan(lat) = -cos(H) / tan(d).
function nightPolygon(utcMs, stepDegrees) {
  var step = stepDegrees > 0 ? stepDegrees : 2
  var sun = subsolarPoint(utcMs)
  var dec = Math.abs(sun.lat) < 0.01 ? (sun.lat < 0 ? -0.01 : 0.01) : sun.lat
  var tanDec = Math.tan(toRadians(dec))
  var count = Math.round(360 / step)
  var points = []
  for (var i = 0; i <= count; i++) {
    var lon = -180 + i * step
    var hourAngle = toRadians(lon - sun.lon)
    points.push([lon, toDegrees(Math.atan(-Math.cos(hourAngle) / tanDec))])
  }
  var pole = dec > 0 ? -90 : 90
  points.push([180, pole])
  points.push([-180, pole])
  return points
}

// Plate carrée: longitude straight across, latitude straight down.
function mapPoint(lon, lat, width, height) {
  return [(lon + 180) / 360 * width, (90 - lat) / 180 * height]
}

// An SVG path for rings given as flat [lon, lat, lon, lat, ...] arrays.
function landPath(rings, width, height) {
  var out = []
  for (var r = 0; r < rings.length; r++) {
    var ring = rings[r]
    for (var i = 0; i + 1 < ring.length; i += 2) {
      var p = mapPoint(ring[i], ring[i + 1], width, height)
      out.push((i === 0 ? "M" : "L") + p[0].toFixed(1) + " " + p[1].toFixed(1))
    }
    out.push("Z")
  }
  return out.join("")
}

// The same for one ring of [lon, lat] pairs.
function pointsPath(points, width, height) {
  var out = []
  for (var i = 0; i < points.length; i++) {
    var p = mapPoint(points[i][0], points[i][1], width, height)
    out.push((i === 0 ? "M" : "L") + p[0].toFixed(1) + " " + p[1].toFixed(1))
  }
  return out.length ? out.join("") + "Z" : ""
}

// The dots on the map: home first, then every person with coordinates.
function mapMarkers(home, homeLat, homeLon, people, rows) {
  var out = []
  if (home && homeLat !== null && homeLat !== undefined) {
    out.push({ name: home.city, lat: homeLat, lon: homeLon, label: home.timeText || "", home: true })
  }
  for (var i = 0; i < people.length; i++) {
    if (people[i].lat === null || people[i].lat === undefined) continue
    var row = rows[i]
    out.push({ name: people[i].name, lat: people[i].lat, lon: people[i].lon,
      label: row && row.ready ? row.timeText : "", home: false })
  }
  return out
}


// ---- the globe. An orthographic view of the sphere centred on (lat0, lon0):
// the land as dots, the night as the near half of the terminator closed
// along the rim, and places as markers. A point is on the near side when
// its cosine distance from the centre, `depth`, is positive.

function globeBasis(lat0, lon0) {
  var p0 = toRadians(lat0)
  return { sinP: Math.sin(p0), cosP: Math.cos(p0), l0: toRadians(lon0) }
}

// Where a place lands on the disc, and its depth: 1 at the centre, 0 on the
// rim, negative round the back.
function globeProject(lat, lon, basis, r, cx, cy) {
  var p = toRadians(lat)
  var dl = toRadians(lon) - basis.l0
  var cosP = Math.cos(p), sinP = Math.sin(p), cosDl = Math.cos(dl)
  var depth = basis.sinP * sinP + basis.cosP * cosP * cosDl
  return {
    x: cx + r * cosP * Math.sin(dl),
    y: cy - r * (basis.cosP * sinP - basis.sinP * cosP * cosDl),
    depth: depth,
    visible: depth >= 0
  }
}

// The land as one path of small squares, one per sample on the near side,
// shrinking towards the rim so the sphere reads as round. `dots` is flat
// [lon, lat, ...] like the map's rings.
function globeDotsPath(dots, lat0, lon0, r, cx, cy, size) {
  if (!dots || dots.length < 2 || !(r > 0)) return ""
  var basis = globeBasis(lat0, lon0)
  var parts = []
  for (var i = 0; i + 1 < dots.length; i += 2) {
    var p = globeProject(dots[i + 1], dots[i], basis, r, cx, cy)
    if (p.depth <= 0) continue
    var s = (size * (0.45 + 0.55 * p.depth)).toFixed(1)
    parts.push("M" + (p.x - s / 2).toFixed(1) + " " + (p.y - s / 2).toFixed(1) + "h" + s + "v" + s + "h-" + s + "z")
  }
  return parts.join("")
}

// The night on the globe. The terminator is a great circle, which the view
// sees as an ellipse: the near half of it runs from one rim point to the
// other, bulging away from the sun by the sun's own depth, and the night is
// the region between that arc and the rim on the side away from the sun.
// Sampled into a polygon rather than written as arcs, so no sweep flag has
// to be guessed; with the sun straight ahead the polygon collapses onto the
// rim, and with the sun behind it covers the whole disc.
function globeNightPath(utcMs, lat0, lon0, r, cx, cy, steps) {
  var n = steps > 3 ? steps : 36
  var basis = globeBasis(lat0, lon0)
  var sun = subsolarPoint(utcMs)
  var s = globeProject(sun.lat, sun.lon, basis, 1, 0, 0)
  var sx = s.x, sy = -s.y, sz = s.depth
  var perp = Math.sqrt(sx * sx + sy * sy)
  var dx = perp > 1e-9 ? sx / perp : 1, dy = perp > 1e-9 ? sy / perp : 0
  var ux = -dy, uy = dx
  var points = []
  for (var i = 0; i <= n; i++) {
    var t = Math.PI * i / n
    points.push([Math.cos(t) * ux - Math.sin(t) * sz * dx, Math.cos(t) * uy - Math.sin(t) * sz * dy])
  }
  var start = Math.atan2(-uy, -ux)
  for (var j = 1; j < n; j++) {
    var a = start - Math.PI * j / n
    points.push([Math.cos(a), Math.sin(a)])
  }
  var out = []
  for (var k = 0; k < points.length; k++) {
    out.push((k === 0 ? "M" : "L") + (cx + r * points[k][0]).toFixed(1) + " " + (cy - r * points[k][1]).toFixed(1))
  }
  return out.join(" ") + " Z"
}

// Places most children have heard of, spread round the world, so the globe
// has somewhere to tap wherever it is turned.
var POPULAR_SPOTS = [
  "Honolulu", "Anchorage", "Vancouver", "Los Angeles", "Denver", "Chicago", "Toronto", "New York",
  "Mexico City", "Havana", "Lima", "Santiago, Chile", "Buenos Aires", "São Paulo", "Rio de Janeiro",
  "Reykjavik", "London", "Paris", "Madrid", "Rome", "Berlin", "Stockholm", "Athens", "Istanbul",
  "Cairo", "Lagos", "Nairobi", "Johannesburg", "Cape Town", "Moscow", "Riyadh", "Dubai", "Tehran",
  "Karachi", "Mumbai", "Delhi", "Kathmandu", "Bangkok", "Hanoi", "Singapore", "Jakarta", "Hong Kong",
  "Beijing", "Shanghai", "Seoul", "Tokyo", "Manila", "Perth", "Sydney", "Auckland"
]

function spotWhere(city) {
  if (!city) return ""
  if (city.country === "United States" && city.region) return city.region
  return city.country || ""
}

function popularSpots(cities) {
  var out = []
  for (var i = 0; i < POPULAR_SPOTS.length; i++) {
    var city = findCity(cities, POPULAR_SPOTS[i])
    if (!city) continue
    out.push({ kind: "spot", name: city.name, place: city.name, where: spotWhere(city), zone: city.zone, lat: city.lat, lon: city.lon })
  }
  return out
}

// Every marker the globe shows: home, the people, then the popular spots
// that none of them already covers.
function globeSpotList(homeName, homeCity, people, popular) {
  var out = []
  if (homeCity && homeCity.lat !== undefined && homeCity.lat !== null) {
    out.push({ kind: "home", name: homeName || homeCity.name, place: homeCity.name, where: spotWhere(homeCity),
      zone: homeCity.zone, lat: homeCity.lat, lon: homeCity.lon })
  }
  for (var i = 0; i < (people || []).length; i++) {
    var person = people[i]
    if (person.lat === null || person.lat === undefined) continue
    out.push({ kind: "person", name: person.name, place: person.city, where: "", zone: person.zone, lat: person.lat, lon: person.lon })
  }
  for (var j = 0; j < (popular || []).length; j++) {
    var spot = popular[j], covered = false
    for (var k = 0; k < out.length; k++) {
      if (Math.abs(out[k].lat - spot.lat) < 1 && Math.abs(out[k].lon - spot.lon) < 1) { covered = true; break }
    }
    if (!covered) out.push(spot)
  }
  return out
}

// The markers on the near side, nearest the rim first so the ones in the
// middle draw on top. `index` points back into the spot list.
function globeMarkers(spots, lat0, lon0, r, cx, cy) {
  var basis = globeBasis(lat0, lon0)
  var out = []
  for (var i = 0; i < (spots || []).length; i++) {
    var p = globeProject(spots[i].lat, spots[i].lon, basis, r, cx, cy)
    if (p.depth <= 0.04) continue
    out.push({ spot: spots[i], x: p.x, y: p.y, depth: p.depth, index: i })
  }
  out.sort(function(a, b) { return a.depth - b.depth })
  return out
}

// What the globe says about a tapped place. A person's own words for a
// person, home's for home, and for anywhere else the family's routine
// moved there, the same honest guess the cards make.
function spotView(spot, offsetInfo, utcMs, home, routine, rules, hourFormat) {
  var offset = offsetInfo ? offsetInfo.offsetSeconds : null
  if (offset === null || offset === undefined) {
    return { name: spot.name, where: spot.where || "", ready: false, isDay: true, t: 0.5,
      sentence: "Finding the time in " + spot.place + "...", timeWords: "", timeText: "", dayLabel: "", offsetWords: "" }
  }
  var parts = localParts(utcMs, offset)
  var sky = skyPosition(utcMs, solarTimesFor(utcMs, spot, offset))
  var activity = activityAt(parts.minutesOfDay, routine, parts.weekend)
  var label = home && rules.dayLabel ? dayLabel(home.dayIndex, parts.dayIndex) : "today"
  var sentence
  if (spot.kind === "home") {
    sentence = homeSentence(spot.place, parts.minutesOfDay)
  } else {
    sentence = "In " + spot.place + " it's " + timeWords(parts.minutesOfDay)
    if (label === "tomorrow") sentence += ", and it's already tomorrow"
    else if (label === "yesterday") sentence += ", and it's still yesterday"
    sentence += ". " + (spot.kind === "person" ? spot.name + " is" : "Children there are") + " probably " + activity.label + "."
  }
  var rounded = roundMinutes(parts.minutesOfDay, 5)
  return {
    name: spot.name,
    where: spot.kind === "person" ? spot.place : (spot.where || ""),
    ready: true,
    isDay: sky.isDay,
    t: clamp01(sky.t),
    sentence: sentence,
    timeWords: "It's about " + clockWords(rounded) + " " + dayPartWords(rounded) + ".",
    timeText: rules.digits ? formatTime(parts.hour, parts.minute, hourFormat) : "",
    dayLabel: rules.dayLabel ? label : "",
    offsetWords: rules.offsets && home && spot.kind !== "home" ? offsetWords(offset, home.offsetSeconds) : ""
  }
}

// ---- the themes. A folder name becomes a title the way omarchy-theme-list
// makes one, and the lines the listing script prints become swatches.

function themeTitle(slug) {
  return String(slug || "").split("-").map(function(word) {
    return word === "" ? "" : word.charAt(0).toUpperCase() + word.slice(1)
  }).join(" ")
}

function parseThemeLines(text) {
  var out = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var cells = lines[i].split("\t")
    if (cells.length < 4 || cells[0] === "") continue
    out.push({ slug: cells[0], title: themeTitle(cells[0]), background: cells[1], foreground: cells[2],
      accent: cells[3], light: (cells[4] || "").trim() === "light" })
  }
  out.sort(function(a, b) { return a.title.localeCompare(b.title) })
  return out
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
    offsetsCommand: offsetsCommand,
    parseOffsetLines: parseOffsetLines,
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
    roundMinutes: roundMinutes,
    handAngles: handAngles,
    clockWords: clockWords,
    dayPartWords: dayPartWords,
    gameRound: gameRound,
    gameView: gameView,
    subsolarPoint: subsolarPoint,
    nightPolygon: nightPolygon,
    mapPoint: mapPoint,
    landPath: landPath,
    pointsPath: pointsPath,
    mapMarkers: mapMarkers,
    cityKey: cityKey,
    cityLabel: cityLabel,
    searchCities: searchCities,
    parsePeopleRaw: parsePeopleRaw,
    peopleString: peopleString,
    addPerson: addPerson,
    removePerson: removePerson,
    DEFAULT_PEOPLE: DEFAULT_PEOPLE,
    SUN_GLYPH: SUN_GLYPH,
    globeBasis: globeBasis,
    globeProject: globeProject,
    globeDotsPath: globeDotsPath,
    globeNightPath: globeNightPath,
    popularSpots: popularSpots,
    globeSpotList: globeSpotList,
    globeMarkers: globeMarkers,
    spotView: spotView,
    themeTitle: themeTitle,
    parseThemeLines: parseThemeLines,
    MOON_GLYPH: MOON_GLYPH
  }
}
