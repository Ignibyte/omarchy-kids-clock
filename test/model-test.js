// node test/model-test.js
const assert = require("assert")
const path = require("path")
const fs = require("fs")
const Model = require(path.join(__dirname, "..", "Model.js"))
const cities = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "data", "cities.json"), "utf8"))

let passed = 0
function check(name, fn) { fn(); passed += 1; console.log("  ok  " + name) }

check("bands cap the number of people and gate the digits", () => {
  assert.strictEqual(Model.bandRules("explorer").digits, false)
  assert.strictEqual(Model.bandRules("tinkerer").digits, true)
  assert.strictEqual(Model.bandRules("navigator").offsets, true)
  assert.strictEqual(Model.bandRules("nonsense").label, "Explorer")
})

check("settings are found on the bar entry or in plugins[]", () => {
  const cfg = { bar: { layout: { right: [{ id: "ignibyte.kids-clock", band: "tinkerer" }] } }, plugins: [] }
  assert.strictEqual(Model.settingsFor(cfg, "ignibyte.kids-clock").band, "tinkerer")
  assert.deepStrictEqual(Model.settingsFor({ plugins: [{ id: "x", a: 1 }] }, "x"), { id: "x", a: 1 })
  assert.deepStrictEqual(Model.settingsFor(null, "x"), {})
})

check("settings are found when the shell hands over the bar on its own", () => {
  // Omarchy 4.0.3 injects a scoped API whose barConfig is the bar half of the
  // config, not the whole file; both shapes have to find the same entry.
  const bar = { layout: { right: [{ id: "ignibyte.kids-clock", band: "navigator" }] } }
  assert.strictEqual(Model.settingsFor(bar, "ignibyte.kids-clock").band, "navigator")
  assert.strictEqual(Model.settingsFor({ bar: bar }, "ignibyte.kids-clock").band, "navigator")
  assert.deepStrictEqual(Model.settingsFor({ layout: {} }, "ignibyte.kids-clock"), {})
})

check("the plugin finds its own directory when the manifest no longer carries it", () => {
  assert.strictEqual(Model.dirFromUrl("file:///home/a/.config/omarchy/plugins/p/"), "/home/a/.config/omarchy/plugins/p")
  assert.strictEqual(Model.dirFromUrl("file:///home/a%20b/p"), "/home/a b/p")
  assert.strictEqual(Model.dirFromUrl("/already/a/path/"), "/already/a/path")
  assert.strictEqual(Model.dirFromUrl(""), "")
})

check("clock strings parse, with am/pm and fallbacks", () => {
  assert.strictEqual(Model.parseClock("07:30", 0), 450)
  assert.strictEqual(Model.parseClock("8pm", 0), 20 * 60)
  assert.strictEqual(Model.parseClock("12:15 am", 0), 15)
  assert.strictEqual(Model.parseClock("nope", 99), 99)
  assert.strictEqual(Model.parseClock("25:00", 99), 99)
})

check("the default people parse, so a bare shell.json entry still shows three cards", () => {
  const people = Model.parsePeople(Model.DEFAULT_PEOPLE, cities, Model.bandRules("explorer").maxPeople)
  assert.strictEqual(people.length, 3)
  assert.deepStrictEqual(people.map(p => p.city), ["Phoenix", "Berlin", "Tokyo"])
})

check("people parse by city name, zone tail or full zone, capped by the band", () => {
  const people = Model.parsePeople("Grandma=Phoenix; Cousin Mia=Europe/Berlin; Uncle Ken=tokyo; Pen pal=Asia/Doha; Extra=Sydney", cities, 3)
  assert.strictEqual(people.length, 3)
  assert.strictEqual(people[0].zone, "America/Phoenix")
  assert.strictEqual(people[1].city, "Berlin")
  assert.strictEqual(people[2].zone, "Asia/Tokyo")
  const bare = Model.parsePeople("Pen pal=Asia/Doha", cities, 3)
  assert.strictEqual(bare[0].known, false)
  assert.strictEqual(bare[0].city, "Doha")
  assert.strictEqual(Model.parsePeople("junk without equals; =x; y=", cities, 3).length, 0)
})

check("date output parses into an offset", () => {
  assert.strictEqual(Model.parseOffset("+05:30"), 19800)
  assert.strictEqual(Model.parseOffset("-0700"), -25200)
  assert.deepStrictEqual(Model.parseOffsetLine("+09:00\tJST\t3\n"), { offsetSeconds: 32400, abbreviation: "JST", weekday: 3 })
  assert.strictEqual(Model.parseOffsetLine("garbage"), null)
  assert.deepStrictEqual(Model.offsetCommand("Asia/Tokyo", 1700000000.7), ["/usr/bin/env", "TZ=Asia/Tokyo", "/usr/bin/date", "--date=@1700000000", "+%:z\t%Z\t%u"])
})

check("local parts follow the offset across midnight and the weekday", () => {
  // 2026-09-05 (a Saturday) 23:30 UTC
  const utc = Date.UTC(2026, 8, 5, 23, 30)
  const tokyo = Model.localParts(utc, 9 * 3600)
  assert.strictEqual(tokyo.hour, 8); assert.strictEqual(tokyo.minute, 30); assert.strictEqual(tokyo.weekday, 0); assert.strictEqual(tokyo.weekend, true)
  const chicago = Model.localParts(utc, -5 * 3600)
  assert.strictEqual(chicago.hour, 18); assert.strictEqual(chicago.weekday, 6)
  assert.strictEqual(Model.dayLabel(chicago.dayIndex, tokyo.dayIndex), "tomorrow")
  assert.strictEqual(Model.dayLabel(tokyo.dayIndex, chicago.dayIndex), "yesterday")
  assert.strictEqual(Model.formatTime(18, 5, "12"), "6:05 PM")
  assert.strictEqual(Model.formatTime(0, 5, "12"), "12:05 AM")
  assert.strictEqual(Model.formatTime(18, 5, "24"), "18:05")
})

check("offset words", () => {
  assert.strictEqual(Model.offsetWords(-7 * 3600, -5 * 3600), "2 hours behind")
  assert.strictEqual(Model.offsetWords(19800, 0), "5½ hours ahead")
  assert.strictEqual(Model.offsetWords(3600, 0), "1 hour ahead")
  assert.strictEqual(Model.offsetWords(-5 * 3600, -5 * 3600), "same time as home")
})

check("sunrise and sunset land where the almanac puts them", () => {
  // Chicago, 2026-09-05, CDT (-5h): almanac sunrise about 06:22, sunset about 19:16.
  const noonUtc = Date.UTC(2026, 8, 5, 17, 0)
  const t = Model.solarTimes(noonUtc, 41.88, -87.63, -5 * 3600)
  const rise = Model.localParts(t.sunrise, -5 * 3600), set = Model.localParts(t.sunset, -5 * 3600)
  assert.ok(Math.abs(rise.hour * 60 + rise.minute - (6 * 60 + 22)) <= 6, "chicago sunrise " + rise.hour + ":" + rise.minute)
  assert.ok(Math.abs(set.hour * 60 + set.minute - (19 * 60 + 16)) <= 6, "chicago sunset " + set.hour + ":" + set.minute)
  // Sydney, 2026-09-05, AEST (+10h): about 06:12 and 17:36.
  const syd = Model.solarTimes(Date.UTC(2026, 8, 5, 2, 0), -33.87, 151.21, 10 * 3600)
  const sr = Model.localParts(syd.sunrise, 36000), ss = Model.localParts(syd.sunset, 36000)
  assert.ok(Math.abs(sr.hour * 60 + sr.minute - (6 * 60 + 12)) <= 8, "sydney sunrise " + sr.hour + ":" + sr.minute)
  assert.ok(Math.abs(ss.hour * 60 + ss.minute - (17 * 60 + 36)) <= 8, "sydney sunset " + ss.hour + ":" + ss.minute)
  // Tromsø in late June never sets; in late December never rises.
  assert.strictEqual(Model.solarTimes(Date.UTC(2026, 5, 21, 12), 69.65, 18.96, 7200).polar, "day")
  assert.strictEqual(Model.solarTimes(Date.UTC(2026, 11, 21, 12), 69.65, 18.96, 3600).polar, "night")
})

check("the sky position runs 0 to 1 by day and by night", () => {
  const times = Model.flatSolarTimes(Date.UTC(2026, 8, 5, 12), 0)
  assert.deepStrictEqual(Model.skyPosition(times.sunrise, times), { isDay: true, t: 0 })
  assert.strictEqual(Model.skyPosition(times.transit, times).t, 0.5)
  const night = Model.skyPosition(times.sunset + 6 * 3600000, times)
  assert.strictEqual(night.isDay, false); assert.ok(Math.abs(night.t - 0.5) < 1e-9)
  const early = Model.skyPosition(times.sunrise - 3 * 3600000, times)
  assert.strictEqual(early.isDay, false); assert.ok(Math.abs(early.t - 0.75) < 1e-9)
})

check("the routine says what people are doing and whether to call", () => {
  const r = Model.routineFrom({ wakeTime: "07:00", schoolStart: "08:30", schoolEnd: "15:00", dinnerTime: "18:00", bedTime: "20:00" })
  assert.strictEqual(Model.activityAt(3 * 60, r, false).call, "asleep")
  assert.strictEqual(Model.activityAt(7 * 60 + 10, r, false).key, "waking")
  assert.strictEqual(Model.activityAt(10 * 60, r, false).key, "school")
  assert.strictEqual(Model.activityAt(10 * 60, r, true).key, "playing")
  assert.strictEqual(Model.activityAt(16 * 60, r, false).call, "good")
  assert.strictEqual(Model.activityAt(18 * 60 + 20, r, false).key, "dinner")
  assert.strictEqual(Model.activityAt(19 * 60 + 30, r, false).key, "bedtime")
  assert.strictEqual(Model.activityAt(21 * 60, r, false).awake, false)
  assert.strictEqual(Model.timeWords(2 * 60), "the middle of the night")
  assert.strictEqual(Model.timeWords(15 * 60), "afternoon")
})

check("rows and the home carry the words a child reads", () => {
  const rules = Model.bandRules("tinkerer")
  const utc = Date.UTC(2026, 8, 5, 23, 30) // Saturday 18:30 in Chicago, Sunday 08:30 in Tokyo
  const home = Model.buildHome("Chicago", 41.88, -87.63, -5 * 3600, utc, rules, "12")
  assert.strictEqual(home.sentence, "It's evening here in Chicago.")
  assert.strictEqual(home.timeText, "6:30 PM")
  assert.strictEqual(home.isDay, true)
  const ken = Model.parsePeople("Uncle Ken=Tokyo", cities, 3)[0]
  const row = Model.buildRow(ken, { offsetSeconds: 9 * 3600, abbreviation: "JST" }, utc, home, Model.routineFrom({}), rules, "12")
  assert.strictEqual(row.ready, true)
  assert.strictEqual(row.dayLabel, "tomorrow")
  assert.strictEqual(row.timeText, "8:30 AM")
  assert.strictEqual(row.awake, true)
  assert.ok(row.sentence.indexOf("In Tokyo it's morning, and it's already tomorrow.") === 0, row.sentence)
  assert.ok(row.sentence.indexOf("Uncle Ken is probably playing, it's the weekend.") > 0, row.sentence)
  const pending = Model.buildRow(ken, undefined, utc, home, Model.routineFrom({}), rules, "12")
  assert.strictEqual(pending.ready, false)
  assert.strictEqual(Model.scrubWords(0), "")
  assert.strictEqual(Model.scrubWords(180), "Pretend it's 3 hours later")
  assert.strictEqual(Model.scrubWords(-60), "Pretend it's 1 hour earlier")
  assert.strictEqual(Model.tooltip([row, pending]), "Sun Clock · Uncle Ken: good time to call")
  assert.strictEqual(Model.barGlyph(true), "")
})

check("the face: rounding, hand angles and the words for a time", () => {
  assert.strictEqual(Model.roundMinutes(157, 15), 150)
  assert.strictEqual(Model.roundMinutes(158, 15), 165)
  assert.strictEqual(Model.roundMinutes(1438, 5), 0)
  assert.strictEqual(Model.roundMinutes(1436, 5), 1435)
  assert.deepStrictEqual(Model.handAngles(150), { hour: 75, minute: 180 })
  assert.deepStrictEqual(Model.handAngles(720), { hour: 0, minute: 0 })
  assert.deepStrictEqual(Model.handAngles(1439), { hour: 359.5, minute: 354 })
  assert.strictEqual(Model.clockWords(120), "two o'clock")
  assert.strictEqual(Model.clockWords(135), "quarter past two")
  assert.strictEqual(Model.clockWords(150), "half past two")
  assert.strictEqual(Model.clockWords(165), "quarter to three")
  assert.strictEqual(Model.clockWords(130), "ten past two")
  assert.strictEqual(Model.clockWords(155), "twenty-five to three")
  assert.strictEqual(Model.clockWords(175), "five to three")
  assert.strictEqual(Model.clockWords(127), "7 minutes past two")
  assert.strictEqual(Model.clockWords(0), "twelve o'clock")
  assert.strictEqual(Model.clockWords(705), "quarter to twelve")
  assert.strictEqual(Model.dayPartWords(150), "at night")
  assert.strictEqual(Model.dayPartWords(510), "in the morning")
  assert.strictEqual(Model.dayPartWords(870), "in the afternoon")
  assert.strictEqual(Model.dayPartWords(1080), "in the evening")
  assert.strictEqual(Model.dayPartWords(1230), "at night")
  assert.strictEqual(Model.bandRules("explorer").face, false)
  assert.strictEqual(Model.bandRules("tinkerer").gameStep, 15)
  assert.strictEqual(Model.bandRules("navigator").gameStep, 5)
})

// A repeatable stand-in for Math.random, so a round's shape can be asserted.
function stream(values) {
  let i = 0
  return () => values[i++ % values.length]
}

check("set the clock: a random time on the band's step, hands starting at twelve", () => {
  const tinkerer = Model.setRound(Model.bandRules("tinkerer"), "12", stream([0.31]))
  assert.strictEqual(tinkerer.mode, "set")
  assert.strictEqual(tinkerer.targetMinutes % 15, 0, "the tinkerer band asks for quarter hours")
  assert.ok(tinkerer.targetMinutes >= 0 && tinkerer.targetMinutes < 720, "a dial time, not a day time")
  assert.strictEqual(tinkerer.prompt, "Set the clock to " + Model.clockWords(tinkerer.targetMinutes) + ".")
  assert.strictEqual(tinkerer.startHands, tinkerer.targetMinutes === 0 ? 540 : 0)

  const navigator = Model.setRound(Model.bandRules("navigator"), "12", stream([0.77]))
  assert.strictEqual(navigator.targetMinutes % 5, 0, "the navigator band works in five minutes")

  // Twelve o'clock cannot start on twelve, or the round is already won.
  const noon = Model.setRound(Model.bandRules("navigator"), "12", stream([0]))
  assert.strictEqual(noon.targetMinutes, 0)
  assert.strictEqual(noon.startHands, 540)
})

check("the digits in the game carry no AM or PM, because a dial has none", () => {
  assert.strictEqual(Model.faceDigits(0), "12:00")
  assert.strictEqual(Model.faceDigits(15 * 60 + 5), "3:05", "afternoon reads off the same dial")
  assert.strictEqual(Model.faceDigits(719), "11:59")
  const round = Model.setRound(Model.bandRules("navigator"), "12", stream([0.5]))
  assert.ok(!/AM|PM/.test(round.digits), round.digits)
})

check("read the clock: four times, exactly one right, all on the band's step", () => {
  const round = Model.readRound(Model.bandRules("navigator"), "12", stream([0.31, 0.77, 0.12, 0.55, 0.9, 0.4]))
  assert.strictEqual(round.mode, "read")
  assert.strictEqual(round.choices.length, 4)
  assert.strictEqual(round.choices.filter(c => c.right).length, 1)
  const right = round.choices.find(c => c.right)
  assert.strictEqual(right.minutes, round.shownMinutes)
  assert.strictEqual(right.words, Model.clockWords(round.shownMinutes))
  const seen = new Set(round.choices.map(c => c.minutes))
  assert.strictEqual(seen.size, 4, "no time is offered twice")
  round.choices.forEach(c => {
    assert.strictEqual(c.minutes % 5, 0)
    assert.ok(c.minutes >= 0 && c.minutes < 720)
  })

  const tinkerer = Model.readRound(Model.bandRules("tinkerer"), "12", stream([0.2, 0.6, 0.1, 0.8, 0.35, 0.45]))
  tinkerer.choices.forEach(c => assert.strictEqual(c.minutes % 15, 0, "quarter hours only on that band"))
})

check("the wrong answers are the mistakes a child actually makes", () => {
  // Quarter past three: an hour either way, quarter to three, and the hands
  // read the wrong way round.
  const wrong = Model.readDistractors(3 * 60 + 15, 5)
  assert.ok(wrong.indexOf(4 * 60 + 15) !== -1, "an hour on")
  assert.ok(wrong.indexOf(2 * 60 + 15) !== -1, "an hour back")
  assert.ok(wrong.indexOf(3 * 60 + 45) !== -1, "past read as to")
  assert.ok(wrong.indexOf(3 * 60 + 15) === -1, "never the right answer")
  assert.ok(wrong.length >= 3, "always enough to fill the other three")
  Model.readDistractors(0, 15).forEach(m => assert.strictEqual(m % 15, 0))
})

check("two rounds in a row are never the same time", () => {
  const rules = Model.bandRules("navigator")
  const same = () => 0.25
  const first = Model.setRound(rules, "12", same)
  const second = Model.setRound(rules, "12", same, first.targetMinutes)
  assert.notStrictEqual(second.targetMinutes, first.targetMinutes)
})

check("the game view follows the hands and hints the shortest way round", () => {
  const round = Model.setRound(Model.bandRules("tinkerer"), "12", stream([0.5]))
  const target = round.targetMinutes

  assert.strictEqual(Model.gameView(round, target).solved, true)
  assert.strictEqual(Model.gameView(round, target).hint, "That's it!")
  // A dial repeats every twelve hours, so a full turn round is the same time.
  assert.strictEqual(Model.gameView(round, target + 720).solved, true,
    "no half-of-the-day trap any more: the hands are the whole answer")
  assert.strictEqual(Model.gameView(round, target + 1440).solved, true)

  const near = Model.gameView(round, target - 15)
  assert.strictEqual(near.hint, "Nearly. A little further on.")
  const nearBack = Model.gameView(round, target + 15)
  assert.strictEqual(nearBack.hint, "Nearly. A little back.")
  const far = Model.gameView(round, target - 180)
  assert.strictEqual(far.hint, "Turn the hands forward.")

  assert.deepStrictEqual(Model.gameView(round, target).angles, Model.handAngles(target))
  assert.ok(Model.gameView(round, target + 720).minutesOfDay < 720, "the face only ever shows a dial time")
})

check("a person is removed by who they are, not by the row they were on", () => {
  let people = "Grandma=Phoenix; Uncle Ken=Tokyo; Nana=Sydney"
  assert.strictEqual(Model.indexOfPerson(people, "Uncle Ken", "Tokyo"), 1)
  assert.strictEqual(Model.indexOfPerson(people, "Nobody", "Nowhere"), -1)
  // Always taking the top row empties the list, last one included.
  for (let n = 0; n < 3; n++) {
    const first = Model.parsePeopleRaw(people)[0]
    people = Model.removePerson(people, Model.indexOfPerson(people, first.name, first.where))
  }
  assert.strictEqual(people, "")
  // And out of the middle, where a stale row index would take the wrong one.
  let middle = "A=Phoenix; B=Tokyo; C=Sydney"
  middle = Model.removePerson(middle, Model.indexOfPerson(middle, "B", "Tokyo"))
  assert.strictEqual(middle, "A=Phoenix; C=Sydney")
})


check("the subsolar point and the night side follow the clock and the season", () => {
  const june = Model.subsolarPoint(Date.UTC(2026, 5, 21, 12, 0))
  assert.ok(Math.abs(june.lat - 23.44) < 0.1, "june lat " + june.lat)
  assert.ok(Math.abs(june.lon) < 1.5, "june noon lon " + june.lon)
  const sep = Model.subsolarPoint(Date.UTC(2026, 8, 22, 18, 0))
  assert.ok(Math.abs(sep.lat) < 0.3, "equinox lat " + sep.lat)
  assert.ok(Math.abs(sep.lon + 92) < 2, "18:00 UTC lon " + sep.lon)
  const late = Model.subsolarPoint(Date.UTC(2026, 8, 5, 23, 50))
  assert.ok(Math.abs(late.lon + 177.5) < 2, "23:50 UTC lon " + late.lon)
  const night = Model.nightPolygon(Date.UTC(2026, 5, 21, 12, 0), 2)
  assert.strictEqual(night.length, 181 + 2)
  assert.deepStrictEqual(night[night.length - 1], [-180, -90], "in June the dark pole is the south pole")
  assert.ok(Math.abs(night[90][1] + 66.56) < 0.6, "on the subsolar meridian the terminator sits on the antarctic circle: " + night[90][1])
  const december = Model.nightPolygon(Date.UTC(2026, 11, 21, 12, 0), 2)
  assert.deepStrictEqual(december[december.length - 1], [-180, 90])
  assert.ok(Math.abs(december[90][1] - 66.56) < 0.6, december[90][1])
  assert.strictEqual(Model.bandRules("navigator").map, true)
  assert.strictEqual(Model.bandRules("tinkerer").map, false)
})

check("the map projection, the paths and the land file", () => {
  assert.deepStrictEqual(Model.mapPoint(-180, 90, 360, 180), [0, 0])
  assert.deepStrictEqual(Model.mapPoint(0, 0, 360, 180), [180, 90])
  assert.strictEqual(Model.landPath([[-180, 90, 180, 90, 180, -90, -180, -90]], 360, 180), "M0.0 0.0L360.0 0.0L360.0 180.0L0.0 180.0Z")
  assert.strictEqual(Model.pointsPath([[0, 0], [10, 0], [10, 10]], 360, 180), "M180.0 90.0L190.0 90.0L190.0 80.0Z")
  assert.strictEqual(Model.pointsPath([], 10, 10), "")
  const land = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "data", "land.json"), "utf8"))
  assert.ok(land.length > 100, "land rings " + land.length)
  for (const ring of land) assert.ok(ring.length >= 6 && ring.length % 2 === 0)
  const p = Model.landPath(land, 944, 472)
  assert.ok(p.length > 20000 && p.indexOf("NaN") === -1)
})

check("map markers: home first, then the people with coordinates", () => {
  const people = Model.parsePeople("Grandma=Phoenix; Pen pal=Asia/Doha", cities, 6)
  const home = { city: "Chicago", timeText: "4:45 PM" }
  const rows = [{ ready: true, timeText: "2:45 PM" }, { ready: false, timeText: "" }]
  const m = Model.mapMarkers(home, 41.88, -87.63, people, rows)
  assert.strictEqual(m.length, 2)
  assert.strictEqual(m[0].home, true); assert.strictEqual(m[0].name, "Chicago"); assert.strictEqual(m[0].label, "4:45 PM")
  assert.strictEqual(m[1].name, "Grandma"); assert.strictEqual(m[1].label, "2:45 PM"); assert.strictEqual(m[1].home, false)
  assert.strictEqual(Model.mapMarkers(home, null, null, people, rows).length, 1)
})

check("city search: starts-with first, labels that disambiguate, keys that round-trip", () => {
  const list = [
    { name: "Portland", country: "United States", region: "Oregon", zone: "America/Los_Angeles", lat: 45.52, lon: -122.68 },
    { name: "Port Moresby", country: "Papua New Guinea", region: "National Capital", zone: "Pacific/Port_Moresby", lat: -9.44, lon: 147.18 },
    { name: "Portland", country: "United States", region: "Maine", zone: "America/New_York", lat: 43.66, lon: -70.26 },
    { name: "Newport", country: "United Kingdom", region: "Wales", zone: "Europe/London", lat: 51.58, lon: -3.0 },
    { name: "Sydney", country: "Australia", region: "New South Wales", zone: "Australia/Sydney", lat: -33.87, lon: 151.21 }
  ]
  assert.deepStrictEqual(Model.searchCities(list, "p", 6), [], "one letter is too little")
  const hits = Model.searchCities(list, "port", 6)
  assert.deepStrictEqual(hits.map(h => h.label), ["Portland, Oregon, United States", "Port Moresby, Papua New Guinea", "Portland, Maine, United States", "Newport, United Kingdom"])
  assert.deepStrictEqual(hits.map(h => h.key), ["Portland, Oregon", "Port Moresby", "Portland, Maine", "Newport"])
  assert.strictEqual(Model.searchCities(list, "port", 2).length, 2)
  assert.strictEqual(Model.searchCities(list, "SYD", 6)[0].label, "Sydney, Australia")
  assert.strictEqual(Model.findCity(list, "Portland").region, "Oregon", "a bare shared name means the biggest")
  assert.strictEqual(Model.findCity(list, "Portland, Maine").region, "Maine")
  assert.strictEqual(Model.findCity(list, "portland, united states").region, "Oregon")
  assert.strictEqual(Model.findCity(list, "Portland, Nowhere").region, "Oregon", "an unknown qualifier still finds the name")
  assert.strictEqual(Model.findCity(cities, "Phoenix").zone, "America/Phoenix")
  assert.strictEqual(Model.cityKey(list, list[4]), "Sydney")
  assert.strictEqual(Model.searchCities(cities, "zurich", 3)[0].city.name, "Zürich", "plain spelling finds the accented name")
  assert.strictEqual(Model.findCity(cities, "Sao Paulo").zone, "America/Sao_Paulo")
  assert.strictEqual(Model.searchCities(cities, "phoe", 3)[0].label, "Phoenix, United States")
  assert.ok(cities.length > 1000, "the city list has " + cities.length)
})

check("the people setting edits as a string and round-trips", () => {
  const raw = Model.parsePeopleRaw("Grandma=Phoenix; Pen pal=Asia/Doha;; junk; =x")
  assert.deepStrictEqual(raw, [{ name: "Grandma", where: "Phoenix" }, { name: "Pen pal", where: "Asia/Doha" }])
  const added = Model.addPerson("Grandma=Phoenix", "Nana", "Portland, Maine")
  assert.strictEqual(added, "Grandma=Phoenix; Nana=Portland, Maine")
  assert.strictEqual(Model.parsePeopleRaw(added)[1].where, "Portland, Maine")
  assert.strictEqual(Model.removePerson(added, 0), "Nana=Portland, Maine")
  assert.strictEqual(Model.removePerson(added, 5), added)
  assert.strictEqual(Model.addPerson("", "Auntie; Jo", "Sydney"), "Auntie  Jo=Sydney", "separators cannot sneak into a name")
  assert.strictEqual(Model.peopleString([]), "")
})

check("the globe projects the centre to the middle and hides the far side", () => {
  const basis = Model.globeBasis(30, -90)
  const centre = Model.globeProject(30, -90, basis, 100, 200, 200)
  assert.ok(Math.abs(centre.x - 200) < 1e-6 && Math.abs(centre.y - 200) < 1e-6 && Math.abs(centre.depth - 1) < 1e-9)
  const far = Model.globeProject(-30, 90, basis, 100, 200, 200)
  assert.ok(!far.visible && Math.abs(far.depth + 1) < 1e-9)
  const east = Model.globeProject(0, 0, basis, 100, 200, 200)
  assert.ok(Math.abs(east.x - 300) < 1e-6 && Math.abs(east.depth) < 1e-9, "ninety degrees east sits on the right-hand rim")
  const pole = Model.globeProject(90, 0, basis, 100, 200, 200)
  assert.ok(pole.visible && pole.y < 200 && Math.abs(pole.x - 200) < 1e-6, "the pole shows above the centre when tilted")
  const dots = Model.globeDotsPath([-90, 30, 90, -30, 1, 0], 30, -90, 100, 200, 200, 4)
  assert.strictEqual((dots.match(/M/g) || []).length, 1, "the antipode and a point just round the rim are skipped")
})

check("the night on the globe is nothing, half, or everything as the sun moves round", () => {
  const ms = Date.UTC(2026, 5, 21, 12, 0, 0)
  const sun = Model.subsolarPoint(ms)
  const area = (path) => {
    const n = path.replace(/[MLZ]/g, " ").trim().split(/\s+/).map(Number)
    let a = 0
    for (let i = 0; i < n.length; i += 2) { const j = (i + 2) % n.length; a += n[i] * n[j + 1] - n[j] * n[i + 1] }
    return Math.abs(a) / 2
  }
  const disc = Math.PI * 100 * 100
  const facing = Model.globeNightPath(ms, sun.lat, sun.lon, 100, 200, 200, 36)
  assert.ok(facing.indexOf("M") === 0 && facing.slice(-1) === "Z")
  assert.ok(area(facing) < disc * 0.01, "sun straight ahead: no night")
  assert.ok(area(Model.globeNightPath(ms, -sun.lat, sun.lon + 180, 100, 200, 200, 36)) > disc * 0.98, "sun behind: all night")
  const half = area(Model.globeNightPath(ms, 0, sun.lon + 90, 100, 200, 200, 36))
  assert.ok(Math.abs(half - disc / 2) < disc * 0.03, "sun on the rim: half, got " + (half / disc).toFixed(3))
})

check("the popular spots resolve and the globe's markers stay on the near side", () => {
  const spots = Model.popularSpots(cities)
  assert.ok(spots.length >= 45, "resolved " + spots.length)
  assert.ok(spots.some(s => s.name === "Santiago" && s.where === "Chile"))
  assert.ok(spots.some(s => s.name === "Chicago" && s.where === "Illinois"))
  const people = [{ name: "Grandma", city: "Phoenix", zone: "America/Phoenix", lat: 33.45, lon: -112.07 }]
  const all = Model.globeSpotList("Chicago", Model.findCity(cities, "Chicago"), people, spots)
  assert.strictEqual(all[0].kind, "home")
  assert.strictEqual(all[1].kind, "person")
  assert.strictEqual(all.filter(s => s.place === "Chicago").length, 1, "home covers the popular Chicago")
  const markers = Model.globeMarkers(all, 40, -100, 100, 200, 200)
  assert.ok(markers.length > 5 && markers.length < all.length)
  assert.ok(markers.every(m => m.depth > 0))
  assert.ok(markers.some(m => m.spot.place === "Chicago") && !markers.some(m => m.spot.place === "Perth"))
  assert.ok(markers[markers.length - 1].depth >= markers[0].depth, "nearest the middle comes last")
})

check("a tapped spot says the time there in words", () => {
  const spot = { kind: "spot", name: "Tokyo", place: "Tokyo", where: "Japan", zone: "Asia/Tokyo", lat: 35.69, lon: 139.75 }
  const routine = Model.routineFrom({})
  const rules = Model.bandRules("navigator")
  const utc = Date.UTC(2026, 8, 5, 22, 0, 0)
  const home = Model.buildHome("Chicago", 41.8, -87.6, -5 * 3600, utc, rules, "12")
  const view = Model.spotView(spot, { offsetSeconds: 9 * 3600 }, utc, home, routine, rules, "12")
  assert.ok(view.ready && view.isDay)
  assert.strictEqual(view.timeText, "7:00 AM")
  assert.strictEqual(view.timeWords, "It's about seven o'clock in the morning.")
  assert.strictEqual(view.sentence, "In Tokyo it's morning, and it's already tomorrow. Children there are probably waking up and having breakfast.")
  assert.strictEqual(view.dayLabel, "tomorrow")
  const grandma = Model.spotView({ kind: "person", name: "Grandma", place: "Phoenix", where: "", zone: "America/Phoenix", lat: 33.45, lon: -112.07 },
    { offsetSeconds: -7 * 3600 }, utc, home, routine, rules, "12")
  assert.ok(grandma.sentence.indexOf("In Phoenix it's afternoon. Grandma is probably") === 0, grandma.sentence)
  assert.strictEqual(grandma.where, "Phoenix")
  const waiting = Model.spotView(spot, null, utc, home, routine, rules, "12")
  assert.ok(!waiting.ready && waiting.sentence.indexOf("Finding the time in Tokyo") === 0)
  const here = Model.spotView({ kind: "home", name: "Chicago", place: "Chicago", where: "Illinois", zone: "America/Chicago", lat: 41.8, lon: -87.6 },
    { offsetSeconds: -5 * 3600 }, utc, home, routine, rules, "12")
  assert.strictEqual(here.sentence, "It's evening here in Chicago.")
  assert.strictEqual(here.offsetWords, "", "home is not ahead of or behind itself")
})

check("many zones are asked in one process and parsed back by name", () => {
  const { execFileSync } = require("child_process")
  const argv = Model.offsetsCommand(["Asia/Tokyo", "America/Chicago", "Australia/Sydney"], Date.UTC(2026, 8, 5, 22, 0, 0) / 1000)
  const text = execFileSync(argv[0], argv.slice(1), { encoding: "utf8" })
  const parsed = Model.parseOffsetLines(text)
  assert.strictEqual(parsed["Asia/Tokyo"].offsetSeconds, 9 * 3600)
  assert.strictEqual(parsed["America/Chicago"].offsetSeconds, -5 * 3600)
  assert.strictEqual(parsed["Australia/Sydney"].offsetSeconds, 10 * 3600)
  assert.strictEqual(parsed["Asia/Tokyo"].weekday, 7, "Sunday morning in Tokyo")
  assert.deepStrictEqual(Model.parseOffsetLines("junk\nAsia/Tokyo\tnonsense\n"), {})
})

check("zones are gated: real tzdata names pass, paths and junk do not", () => {
  for (const good of ["America/Phoenix", "Etc/GMT+3", "America/Argentina/Buenos_Aires", "America/Port-au-Prince"]) assert.ok(Model.isZone(good), good)
  for (const bad of ["/dev/ptmx", "../x", "America/", "a b/c", "x\ty/z", "Phoenix", "A/B/C/D", "$(id)/x", "America/" + "x".repeat(60)])
    assert.ok(!Model.isZone(bad), bad)
  const people = Model.parsePeople("Nana=/dev/ptmx; Pop=America/Denver", cities, 6)
  assert.strictEqual(people.length, 1)
  assert.strictEqual(people[0].zone, "America/Denver")
})

check("the people setting is bounded and cleaned", () => {
  const many = Array.from({ length: 100 }, (_, i) => "P" + i + "=Tokyo").join("; ")
  assert.strictEqual(Model.parsePeopleRaw(many).length, 32)
  assert.strictEqual(Model.parsePeopleRaw("N=" + "x".repeat(200))[0].where.length, 64)
  assert.strictEqual(Model.peopleString([{ name: "Na\nna", where: "Sydney\t" }]), "Na na=Sydney")
  assert.strictEqual(Model.cleanField("  a;b=c  ", 40), "a b c")
  assert.strictEqual(Model.bandRules("__proto__").label, "Explorer")
  assert.strictEqual(Model.bandRules("constructor").label, "Explorer")
  assert.strictEqual(Model.parseClock("  8   pm ", 0), 20 * 60)
})

check("an unknown zone comes back as unknown, not as UTC", () => {
  const { execFileSync } = require("child_process")
  const argv = Model.offsetsCommand(["America/Pheonix", "Asia/Tokyo"], Date.UTC(2026, 8, 5, 22, 0, 0) / 1000)
  const parsed = Model.parseOffsetLines(execFileSync(argv[0], argv.slice(1), { encoding: "utf8" }))
  assert.strictEqual(parsed["America/Pheonix"].unknown, true)
  assert.strictEqual(parsed["Asia/Tokyo"].offsetSeconds, 9 * 3600)
  const row = Model.buildRow({ name: "Nana", city: "Pheonix", zone: "America/Pheonix", lat: null, lon: null }, { unknown: true },
    Date.now(), null, Model.routineFrom({}), Model.bandRules("explorer"), "12")
  assert.ok(!row.ready && row.unknown && row.sentence.indexOf("Pheonix is not a place") === 0, row.sentence)
})

check("New Zealand on summer time has a day, and a sunset after midnight is still day", () => {
  const auckland = Model.findCity(cities, "Auckland")
  const nz = Date.UTC(2026, 11, 15, 1, 0, 0)
  const sky = Model.skyPosition(nz, Model.solarTimes(nz, auckland.lat, auckland.lon, 13 * 3600))
  assert.ok(sky.isDay && sky.t > 0.3 && sky.t < 0.8, "Auckland at 14:00 NZDT: " + JSON.stringify(sky))
  const reykjavik = Model.findCity(cities, "Reykjavik")
  const june = Date.UTC(2026, 5, 22, 0, 2, 0)
  const late = Model.skyPosition(june, Model.solarTimes(june, reykjavik.lat, reykjavik.lon, 0))
  assert.ok(late.isDay, "Reykjavík two minutes past midnight in June: " + JSON.stringify(late))
})

check("words for quarter hours, minutes, midday and a bedtime after midnight", () => {
  assert.strictEqual(Model.offsetWords(5.75 * 3600, 0), "5¾ hours ahead")
  assert.strictEqual(Model.offsetWords(-900, 0), "a quarter of an hour behind")
  assert.strictEqual(Model.offsetWords(3600, 0), "1 hour ahead")
  assert.strictEqual(Model.offsetWords(1800, 0), "half an hour ahead")
  assert.strictEqual(Model.scrubWords(15), "Pretend it's 15 minutes later")
  assert.strictEqual(Model.scrubWords(-75), "Pretend it's 1 hour 15 minutes earlier")
  assert.strictEqual(Model.scrubWords(180), "Pretend it's 3 hours later")
  assert.strictEqual(Model.clockWords(61), "1 minute past one")
  assert.strictEqual(Model.dayPartWords(720), "at midday")
  const late = Model.routineFrom({ bedTime: "00:30", wakeTime: "07:00" })
  assert.strictEqual(Model.activityAt(19 * 60, late, false).key, "playing")
  assert.strictEqual(Model.activityAt(10, late, false).key, "bedtime")
  assert.strictEqual(Model.activityAt(60, late, false).key, "asleep")
  assert.strictEqual(Model.activityAt(7 * 60 + 10, late, false).key, "waking")
})

check("every city keeps to its country's zones, comes back from its own key, and the spots are right", () => {
  const zoneCodes = {}
  for (const line of fs.readFileSync("/usr/share/zoneinfo/zone1970.tab", "utf8").split("\n")) {
    if (!line || line[0] === "#") continue
    const cells = line.split("\t"); zoneCodes[cells[2]] = cells[0].split(",")
  }
  const isoNames = {}
  for (const line of fs.readFileSync("/usr/share/zoneinfo/iso3166.tab", "utf8").split("\n")) {
    if (!line || line[0] === "#") continue
    const [code, name] = line.split("\t"); isoNames[name.toLowerCase()] = code
  }
  const alias = { "united states": "US", "united states of america": "US", "russia": "RU", "south korea": "KR", "north korea": "KP",
    "czech republic": "CZ", "czechia": "CZ", "democratic republic of the congo": "CD", "congo (kinshasa)": "CD", "republic of the congo": "CG",
    "congo (brazzaville)": "CG", "iran": "IR", "vietnam": "VN", "bolivia": "BO", "venezuela": "VE", "tanzania": "TZ", "laos": "LA", "syria": "SY",
    "united kingdom": "GB", "taiwan": "TW", "the bahamas": "BS", "gambia": "GM", "the gambia": "GM", "ivory coast": "CI", "brunei": "BN",
    "macedonia": "MK", "north macedonia": "MK", "east timor": "TL", "timor-leste": "TL", "cape verde": "CV", "swaziland": "SZ", "eswatini": "SZ",
    "moldova": "MD", "palestine": "PS", "myanmar": "MM", "burma": "MM", "federated states of micronesia": "FM", "micronesia": "FM",
    "saint kitts and nevis": "KN", "saint lucia": "LC", "saint vincent and the grenadines": "VC", "sao tome and principe": "ST",
    "são tomé and príncipe": "ST", "hong kong s.a.r.": "HK", "hong kong": "HK", "macau s.a.r": "MO", "macau": "MO", "vatican": "VA",
    "vatican city": "VA", "republic of serbia": "RS", "guinea bissau": "GW", "brunei darussalam": "BN", "curaçao": "CW", "åland": "AX",
    "united states virgin islands": "VI", "u.s. virgin islands": "VI", "somaliland": "SO", "northern cyprus": "CY" }
  const mismatches = [], skipped = []
  for (const c of cities) {
    const key = c.country.toLowerCase()
    const code = alias[key] || isoNames[key]
    const codes = zoneCodes[c.zone]
    if (!code) { skipped.push(c.country); continue }
    if (!codes) continue
    if (!codes.includes(code)) mismatches.push(c.name + " (" + c.country + ") " + c.zone)
  }
  assert.deepStrictEqual(mismatches, [])
  assert.ok(skipped.length < cities.length * 0.05, "unmapped countries: " + [...new Set(skipped)].join(", "))
  const lost = cities.filter(c => Model.findCity(cities, Model.cityKey(cities, c)) !== c).map(c => c.name + ", " + c.region + ", " + c.country)
  assert.deepStrictEqual(lost, [])
  const spots = Model.popularSpots(cities)
  const zoneOf = (name) => spots.find(s => s.name === name).zone
  assert.strictEqual(zoneOf("Lagos"), "Africa/Lagos")
  assert.strictEqual(zoneOf("Santiago"), "America/Santiago")
  assert.strictEqual(zoneOf("Beijing"), "Asia/Shanghai")
  assert.strictEqual(zoneOf("Kathmandu"), "Asia/Kathmandu")
  assert.strictEqual(spots.length, 50)
  assert.strictEqual(Model.findCity(cities, "Washington").region, "District of Columbia")
  assert.strictEqual(Model.findCity(cities, "Kobenhavn").name, "København")
  assert.strictEqual(Model.findCity(cities, ","), null)
})

console.log(passed + " checks passed")
