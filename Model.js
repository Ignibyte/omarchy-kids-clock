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
    DEFAULT_PEOPLE: DEFAULT_PEOPLE,
    SUN_GLYPH: SUN_GLYPH,
    MOON_GLYPH: MOON_GLYPH
  }
}
