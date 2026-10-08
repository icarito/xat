# Unicode 17.0 emoji atlas

This directory contains raster artwork for every fully-qualified and component
sequence in the pinned Unicode 17.0 `emoji-test.txt`: 3,944 fully-qualified
sequences and 9 components. The manifest also maps the 1,272 listed minimally
qualified and unqualified forms to canonical sequences when removing U+FE0F
produces an exact, unambiguous canonical match. Other strings do not receive
aliases.

`manifest.json` is version 2. It lists each sequence's page and 64 × 64 tile,
all page dimensions and SHA-256 hashes, aliases, source data URLs and hashes,
font metadata, rendering tool versions, and coverage results. The 16 PNG pages
are 1024 × 1024 except the final 1024 × 512 page. `properties.json` contains
Unicode 17.0 grapheme-break, Extended_Pictographic, and Emoji ranges for runtime
text segmentation. Chat text must retain its original Unicode sequence; atlas
lookup only selects its rendering.

The generator validates every canonical sequence with HarfBuzz before raster
rendering. A sequence must shape to exactly one non-.notdef glyph with bitmap
art in the font's 109 × 109 color strike. A normal full build stops if any
sequence fails that check; it does not count decomposed or missing glyphs as
covered. The manifest records actual counts and any missing items for an
explicit research build.

The PNGs are raster derivatives of Noto Color Emoji. `LICENSE.txt` carries the
font's SIL Open Font License notice. The pinned Unicode data and its license
are in `tools/emoji-data/17.0/`; `UNICODE-LICENSE.txt` carries the Unicode
License V3 notice for those data files.

To regenerate with Pillow/RAQM, fontTools, and libharfbuzz installed:

```sh
python3 tools/build_emoji_atlas.py \
  --font /path/to/NotoColorEmoji.ttf \
  --license /path/to/OFL-LICENSE \
  --out app/emoji
```

The font must contain its fixed 109 × 109 color bitmap strike. `--fixtures`
builds the small legacy fixture subset for debugging. `--allow-missing` is for
research only; it records incomplete coverage in the manifest. Neither option
is used by the default full-coverage build.
