# Sun Clock

A clock for kids, as an Omarchy 4 (Quattro) shell plugin. It answers the
question a child asks about the people they love in other places: is Grandma
awake right now, and can I call her?

Time is abstract for a young child, so this clock does not lead with digits.
Each place gets a sky with the sun on its arc by day and the moon by night. A
sentence says what time of day it is there in words. Each person gets a card:
their own sky, whether they are awake, what they are probably doing, and
whether it is a good time to call. The arrow keys move the sun forward and
back an hour at a time, so a child can watch it become bedtime in Tokyo.

![The big clock on the Explorer face, Tokyo Night theme](preview.png)

From the second band an analog face sits beside the digits, showing the same
time, and Enter opens a small game: set the hands to Grandma's time. The sun
under the face follows the hands, and the round is won when it sits in the
ring where Grandma's sun really is.

![The set-the-clock game on the Tinkerer face](preview-game.png)

The plugin binds to Omarchy's theme tokens and ships no colours of its own.
The sun is the theme accent and the moon is the theme foreground, so it
re-tints when the theme changes, like the rest of the shell.

## The three faces

The age band is a parent setting. Each band adds to the one before.

| Band | Ages | What is on screen |
|---|---|---|
| explorer | 3 to 5 | home and up to three people; sun, moon and words only; no digits |
| tinkerer | 5 to 7 | adds the digital time, the analog face, "tomorrow" or "yesterday", and the set-the-clock game in quarter hours |
| navigator | 8 to 10 | adds the world map with the night side, "3 hours ahead", up to six people; the game works in five minutes |

![The Tinkerer face: the digits, the analog face and the day labels](preview-tinkerer.png)

## The map

On the Navigator band, M swaps the clock for a map of the world with the
night side shaded. The shade is the real one for the shown instant, worked
out from the sun's declination and Greenwich solar noon, so it leans towards
one pole in December and the other in June, and it sweeps west as the arrow
keys move the sun. A sun marks where the sun is straight overhead, a moon
where it is the middle of the night, a ring marks home and a dot each
person, with their time beside it. It is a flat map rather than a globe on
purpose: it hides no hemisphere, and the shade crossing a continent is the
whole lesson.

![The map on the Navigator face](preview-map.png)

The land outlines are Natural Earth 1:110m, which is public domain, rounded
to a tenth of a degree in `data/land.json`.

## Install

```bash
omarchy plugin add https://github.com/Ignibyte/omarchy-kids-clock.git
omarchy plugin enable ignibyte.kids-clock right
```

The plugin lands disabled so you can read the code first. Omarchy plugins run
unsandboxed inside `omarchy-shell` with your permissions. This one runs
`date` and `timedatectl` and reads its own `data/cities.json`. It makes no
network requests and writes nothing outside `~/.config/omarchy/shell.json`,
where Omarchy keeps every plugin's settings.

## Settings

Open Setup, then Plugins, then Sun Clock, or edit the plugin's entry in
`~/.config/omarchy/shell.json`.

| Key | Default | Meaning |
|---|---|---|
| `band` | `explorer` | `explorer`, `tinkerer` or `navigator` |
| `people` | `Grandma=Phoenix; Cousin Mia=Berlin; Uncle Ken=Tokyo` | `Name=City` pairs separated by semicolons. Cities from the built-in list of about a hundred, or any IANA zone such as `America/Phoenix` |
| `homeCity` | blank | The city that matches the system time zone. Set it when the system zone is a region, not your city, so the sunrise is right |
| `wakeTime`, `schoolStart`, `schoolEnd`, `dinnerTime`, `bedTime` | `07:00`, `08:30`, `15:00`, `18:00`, `20:00` | The family routine. "Uncle Ken is probably at school" means the child's own routine moved to Tokyo, which is honest and personal rather than a guess about another country |
| `hourFormat` | `12` | `12` or `24`, for the bands that show digits |

Names never leave the machine. Nothing about a child is collected.

## In the bar

The chip shows the sun by day and the moon by night for home. Left click
opens the big clock. Right click puts the sun back to now after a scrub.

## Keys in the big clock

| Key | Does |
|---|---|
| Right, Left | move the sun an hour later or earlier; with Shift, a quarter hour |
| 0, Home, Space | back to now |
| Enter | open the set-the-clock game (tinkerer and navigator); clicking the face does the same |
| M | the map, and back to the clock (navigator) |
| Escape | back to now if the sun was moved, back to the clock from the map, otherwise close |

A view can be opened directly, which suits a keybinding:

```bash
omarchy-shell shell toggle ignibyte.kids-clock '{"view":"map"}'
omarchy-shell shell toggle ignibyte.kids-clock '{"view":"game"}'
```

## The set-the-clock game

One person at a time. Their time is frozen as the round starts and rounded
to the band's step, and the words say it the way school does: "It's about
quarter to three in the afternoon in Phoenix." The hands start at twelve in
the same half of the day, like a toy clock reset, so the child sets the hour
and then the minutes. The hour hand is geared to the minute hand, so half
past shows it halfway to the next numeral, which is the thing children find
hardest about a real clock.

The sky under the face belongs to that person, and its sun or moon follows
the hands. A dashed ring marks where the sun really is right now. When the
hands are right the sun sits in the ring, the ring fills, and the sentence
says what the person is probably doing. Twelve hours out is the one trap:
the hands read right, the sky shows the other half of the day, and the hint
says so.

| Key | Does |
|---|---|
| Right, Left | turn the hands five minutes; with Shift, one minute |
| Up, Down | turn the hands an hour |
| 0, Home | hands back to twelve |
| Enter, Space | the next person, once the round is won |
| Escape | back to the clock |

Four big round buttons under the face do the same for a mouse or a finger.

## How it works

`Model.js` is the whole logic, free of Qt so `node test/model-test.js` runs
it: the sunrise equation for the sun's place on the arc and for the night
side of the map, the routine mapping, the words, the hand angles, and the
game's rounds and hints. QML's JavaScript has no time zone tables, so
`Service.qml` asks `date` for each zone's offset through a Quickshell
process, one at a time. `Overlay.qml` draws the skies and the map with
QtQuick Shapes (the land as one SVG path built from the data file) and the
face from rotated rectangles, all bound to theme colours so they re-tint;
`BarWidget.qml` is the chip.

## Part of Omarchy Kids

A spoke of the community Kids Mode effort at
[markcuda/omarchy-kids-mode](https://github.com/markcuda/omarchy-kids-mode).
Started from Jason Fried's world clock plugin, which asks the grown-up
version of the same question.

MIT.
