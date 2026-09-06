# Where the data comes from

All three files are derived from [Natural Earth](https://www.naturalearthdata.com/),
which is in the public domain. The generation was a few short Python scripts,
not kept; what they did is written here so it can be done again.

## `land.json`

Natural Earth 1:110m Physical, "Land" (`ne_110m_land`). Every ring of every
polygon, in order, as a flat `[lon, lat, lon, lat, ...]` array rounded to a
tenth of a degree: 128 rings, about ten thousand points. The map draws them as
one SVG path with the even-odd rule.

## `globe.json`

The same 1:110m land, sampled rather than traced: points on a two-degree
equal-area grid (the longitude step widens with the cosine of the latitude)
that fall inside any land ring by the even-odd test, from 88°S to 88°N.
About three thousand points as a flat `[lon, lat, ...]` array, one square each
on the globe.

## `cities.json`

Natural Earth 1:10m Cultural, "Populated Places" (`ne_10m_populated_places`):
every place with `POP_MAX` of 300,000 or more, and every national capital
(`FEATURECLA` beginning "Admin-0 capital"). Fields kept: `NAME`, `ADM0NAME` as
`country`, `ADM1NAME` as `region`, `LATITUDE` and `LONGITUDE` rounded to two
decimals, and `TIMEZONE` as `zone`. An `ascii` alias is added when the name
has letters outside ASCII, transliterated so that ø, ł, ı, ß, æ and the like
become letters rather than disappearing.

Two corrections after the export. Natural Earth's zone column was wrong for
twenty places (Lagos in Europe/Athens, Prague in America/Chicago, Cardiff in
Australia/Sydney, and so on); every zone is now checked against tzdata's
`zone1970.tab`, the country of each place must be among the zone's countries,
and the test suite keeps it that way. Deprecated zone names that tzdata keeps
only as links (`Asia/Rangoon`, `Europe/Kiev`, `Asia/Harbin` for Beijing) were
replaced by their current names where the renamed zone is the same place;
regional links such as `Europe/Oslo` stay as they are, because they still name
the right place to a reader. Duplicate rows for the same place were removed.
