# Roadmap

What is likely to happen to the Sun Clock next, and why in that order. Every
item has an issue; this file is the shape of the pile, not a second copy of it.

Nothing here is a promise of a date.

## Where it is now

0.17.0. The clock, the game, Times on Earth, People, Me and a page for each
person all work; it runs on Omarchy 4.0.2 and 4.0.3. Listed in the marketplace
as `ignibyte.kids-clock`.

## Next, roughly in order

The order is effort against payoff, and which ones are waiting on a decision
rather than on work.

| | What | Why here |
|---|---|---|
| [#2](../../issues/2) | Moon phases | Smallest thing on the list. No network, no new data — the phase is arithmetic of the same family as the sunrise equation already in `Model.js`. Nothing to decide first. |
| [#5](../../issues/5) | The two days side by side, on a person's page | The best payoff for the work. "Can I call Grandma?" is what this plugin is for, and it currently answers with a sentence when it could answer with a picture. Everything it needs is already computed. |
| [#10](../../issues/10) | A parent-gated way to change the age band | The band decides what a child sees, and today it can only be changed from a terminal. The original design said "behind sudo" and that never got built. Someone hit it in the wild. |
| [#11](../../issues/11) | Call status that survives greyscale | Since the words moved to the person's page, one small dot carries the whole answer on the card, and two of its three states are the same colour at different alphas. |
| [#7](../../issues/7) | Widen the place list | A small town cannot be found, so a child is told their grandmother lives in the nearest city. One decision (which source) and a data file. |
| [#1](../../issues/1) | Weather | Wants a decision before it wants work: this would put the plugin on the network for the first time. Opt-in and off by default is the recommendation. |
| [#8](../../issues/8) | The child's own day, and screen time | The one slice of the original plan never built, and the reason the clock exists. The day track needs nobody; the screen time bar waits on a state file contract that has no owner yet. |
| [#3](../../issues/3) | Calendar | Needs a scope decision first — the issue lays out four readings of what "calendar" means here. |
| [#9](../../issues/9) | Say it out loud | The Explorer band is for children who cannot read and still asks them to. Wants a decision on where the audio comes from, and a word with the hub about its sound service. |
| [#4](../../issues/4) | A scene for each pin on the globe | The biggest, and the most fun. Fifty places is fifty scenes, so the mechanism matters more than the first one; it also needs artwork with a licence we can ship. |

## Open questions

Things waiting on a person, not on code.

- **Which place list** ([#7](../../issues/7)). Natural Earth's full set is
  public domain and five times bigger; GeoNames is far bigger again but CC-BY
  and megabytes.
- **Whether the plugin should ever touch the network** ([#1](../../issues/1)).
  It does not today, and the README and the marketplace listing both say so.
- **What a calendar means here** ([#3](../../issues/3)).
- **Where spoken audio comes from** ([#9](../../issues/9)), and whether the
  Omarchy Kids hub's sound service is going to cover it.
- **Registering as a spoke** of [omarchy-kids-mode](https://github.com/markcuda/omarchy-kids-mode),
  which is a row in its `SPOKES.md` and has not been filed.

## Not planned

- **Reading a real calendar** — an ICS file or the system calendar needs file
  or account access and puts a grown-up's appointments in front of a child. It
  would be a different plugin.
- **A band for 11 and over.** The original sketch had a fourth row for 11–12.
  By that age the answer is a world clock, and there are three good ones
  already; this plugin is under-13-first and should stop where it stops.
- **A palette of its own.** Everything binds to the Omarchy theme tokens. The
  sun, the moon, and a place's scene are content and get real colours; the
  chrome around them does not. See the README.
- **Enforcing anything.** The clock shows time and never takes it away.
  Enforcement is root's job — anything a child can edit, a child can defeat.

## Contributing

Issues and pull requests welcome, including on anything above. The quality
bar is what is already there: logic in `Model.js` with node tests
(`node test/model-test.js`), drawing with QtQuick Shapes so it re-tints, and
no colours of your own.
