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

The plugin binds to Omarchy's theme tokens and ships no colours of its own.
The sun is the theme accent and the moon is the theme foreground, so it
re-tints when the theme changes, like the rest of the shell.

## The three faces

The age band is a parent setting. Each band adds to the one before.

| Band | Ages | What is on screen |
|---|---|---|
| explorer | 3 to 5 | home and up to three people; sun, moon and words only; no digits |
| tinkerer | 5 to 7 | adds the digital time and "tomorrow" or "yesterday" |
| navigator | 8 to 10 | adds "3 hours ahead", up to six people |

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
| Escape | back to now if the sun was moved, otherwise close |

## How it works

`Model.js` is the whole logic, free of Qt so `node test/model-test.js` runs
it: the sunrise equation for the sun's place on the arc, the routine mapping,
the words. QML's JavaScript has no time zone tables, so `Service.qml` asks
`date` for each zone's offset through a Quickshell process, one at a time.
`Overlay.qml` draws the skies with QtQuick Shapes bound to theme colours;
`BarWidget.qml` is the chip.

## Part of Omarchy Kids

A spoke of the community Kids Mode effort at
[markcuda/omarchy-kids-mode](https://github.com/markcuda/omarchy-kids-mode).
Started from Jason Fried's world clock plugin, which asks the grown-up
version of the same question.

MIT.
