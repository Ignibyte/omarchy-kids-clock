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

check("a game round freezes the person's time, rounds it and starts the hands at twelve", () => {
  const frozen = Date.UTC(2026, 8, 5, 21, 37) // Saturday 14:37 in Phoenix, Sunday 06:37 in Tokyo
  const routine = Model.routineFrom({})
  const grandma = Model.parsePeople("Grandma=Phoenix", cities, 3)[0]
  const tinkerer = Model.gameRound(grandma, { offsetSeconds: -7 * 3600 }, frozen, routine, Model.bandRules("tinkerer"), "12")
  assert.strictEqual(tinkerer.exactMinutes, 14 * 60 + 37)
  assert.strictEqual(tinkerer.targetMinutes, 14 * 60 + 30)
  assert.strictEqual(tinkerer.startHands, 720)
  assert.strictEqual(tinkerer.targetWords, "half past two in the afternoon")
  assert.strictEqual(tinkerer.targetDigits, "2:30 PM")
  assert.strictEqual(tinkerer.prompt, "It's about half past two in the afternoon in Phoenix.")
  assert.strictEqual(tinkerer.task, "Turn the hands until the sun sits in the ring.")
  assert.strictEqual(tinkerer.solvedSentence, "That's it! In Phoenix it's about half past two in the afternoon. Grandma is probably playing, it's the weekend.")
  assert.strictEqual(tinkerer.goalIsDay, true)
  const navigator = Model.gameRound(grandma, { offsetSeconds: -7 * 3600 }, frozen, routine, Model.bandRules("navigator"), "24")
  assert.strictEqual(navigator.targetMinutes, 14 * 60 + 35)
  assert.strictEqual(navigator.targetWords, "twenty-five to three in the afternoon")
  assert.strictEqual(navigator.targetDigits, "14:35")
  const ken = Model.parsePeople("Uncle Ken=Tokyo", cities, 3)[0]
  const tokyo = Model.gameRound(ken, { offsetSeconds: 9 * 3600 }, frozen, routine, Model.bandRules("tinkerer"), "12")
  assert.strictEqual(tokyo.targetMinutes, 6 * 60 + 30)
  assert.strictEqual(tokyo.startHands, 0)
  assert.strictEqual(tokyo.targetWords, "half past six in the morning")
  assert.strictEqual(tokyo.goalIsDay, true, "the sun is up in Tokyo at half past six in September")
  // A target of noon exactly cannot start at noon.
  const noon = Model.gameRound(grandma, { offsetSeconds: -7 * 3600 }, Date.UTC(2026, 8, 5, 19, 0), routine, Model.bandRules("tinkerer"), "12")
  assert.strictEqual(noon.targetMinutes, 720)
  assert.strictEqual(noon.startHands, 540)
})

check("the game view follows the hands, hints the shortest way and knows the twelve-hour trap", () => {
  const frozen = Date.UTC(2026, 8, 5, 21, 37)
  const grandma = Model.parsePeople("Grandma=Phoenix", cities, 3)[0]
  const round = Model.gameRound(grandma, { offsetSeconds: -7 * 3600 }, frozen, Model.routineFrom({}), Model.bandRules("tinkerer"), "12")
  const start = Model.gameView(round, round.startHands)
  assert.strictEqual(start.solved, false)
  assert.strictEqual(start.delta, 150)
  assert.strictEqual(start.hint, "Turn the hands forward.")
  assert.deepStrictEqual(start.angles, { hour: 0, minute: 0 })
  assert.strictEqual(start.isDay, true)
  assert.ok(start.t < round.goalT, "noon's sun sits earlier on the arc than half past two's")
  const near = Model.gameView(round, 855)
  assert.strictEqual(near.hint, "Nearly. A little further on.")
  const past = Model.gameView(round, 900)
  assert.strictEqual(past.delta, -30)
  assert.strictEqual(past.hint, "Nearly. A little back.")
  const done = Model.gameView(round, 870)
  assert.strictEqual(done.solved, true)
  assert.ok(Math.abs(done.t - round.goalT) < 1e-9, "the sun lands in the ring")
  assert.strictEqual(Model.gameView(round, 870 + 1440).solved, true, "a full turn past midnight still counts")
  const trap = Model.gameView(round, 150)
  assert.strictEqual(trap.solved, false)
  assert.deepStrictEqual(trap.angles, Model.handAngles(870))
  assert.strictEqual(trap.isDay, false, "half past two at night shows the moon")
  assert.ok(trap.hint.indexOf("wrong half of the day") > 0, trap.hint)
  const wayBack = Model.gameView(round, 1300)
  assert.strictEqual(wayBack.delta, -430)
  assert.strictEqual(wayBack.hint, "Turn the hands back.")
})

console.log(passed + " checks passed")
