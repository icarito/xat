#!/usr/bin/env python3
"""Build a deterministic atlas from pinned Unicode Emoji 17.0 data."""

from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import hashlib
import json
import math
import re
import shutil
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, __version__ as pillow_version
from PIL import features
from fontTools.ttLib import TTFont
import fontTools

UNICODE_VERSION = "17.0"
DATA_DIR = Path("tools/emoji-data/17.0")
EMOJI_TEST = DATA_DIR / "emoji-test.txt"
EMOJI_DATA = DATA_DIR / "emoji-data.txt"
GRAPHEME_DATA = DATA_DIR / "GraphemeBreakProperty.txt"
UNICODE_LICENSE = DATA_DIR / "LICENSE.txt"
FONT_PATH = "/usr/share/fonts/noto/NotoColorEmoji.ttf"
FONT_LICENSE_PATH = "/usr/share/licenses/noto-fonts-emoji/LICENSE"
TILE = 64
PADDING = 4
PAGE_SIZE = 1024
COLS = PAGE_SIZE // TILE
ROWS_PER_PAGE = PAGE_SIZE // TILE
FIXTURES = [
    "😀", "😂", "🙂", "❤️", "👍", "👍🏽", "👩‍💻", "👨‍👩‍👧‍👦",
    "🇵🇪", "🇺🇸", "1️⃣", "✅", "🎉", "🔥", "🚀", "👋",
]
UNICODE_SOURCES = {
    "emoji-test.txt": "https://www.unicode.org/Public/17.0.0/emoji/emoji-test.txt",
    "emoji-data.txt": "https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-data.txt",
    "GraphemeBreakProperty.txt": "https://www.unicode.org/Public/17.0.0/ucd/auxiliary/GraphemeBreakProperty.txt",
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def codepoints(text: str) -> list[str]:
    return [f"U+{ord(char):04X}" for char in text]


def remove_vs16(sequence: str) -> str:
    return sequence.replace("\ufe0f", "")


def parse_code_range(value: str) -> tuple[int, int]:
    parts = value.strip().split("..", 1)
    start = int(parts[0], 16)
    return start, int(parts[1], 16) if len(parts) == 2 else start


def merge_ranges(ranges: list[tuple[int, int]]) -> list[list[int]]:
    merged: list[list[int]] = []
    for start, end in sorted(ranges):
        if merged and start <= merged[-1][1] + 1:
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])
    return merged


def parse_unicode_properties(emoji_text: str, grapheme_text: str) -> dict:
    grapheme: list[tuple[int, int, str]] = []
    for line in grapheme_text.splitlines():
        body = line.split("#", 1)[0].strip()
        if not body or ";" not in body:
            continue
        code_range, prop = (part.strip() for part in body.split(";", 1))
        start, end = parse_code_range(code_range)
        grapheme.append((start, end, prop))

    grapheme.sort()
    merged_gcb: list[list] = []
    for start, end, prop in grapheme:
        if merged_gcb and merged_gcb[-1][2] == prop and start <= merged_gcb[-1][1] + 1:
            merged_gcb[-1][1] = max(merged_gcb[-1][1], end)
        else:
            merged_gcb.append([start, end, prop])

    emoji_ranges: dict[str, list[tuple[int, int]]] = {"Extended_Pictographic": [], "Emoji": []}
    for line in emoji_text.splitlines():
        body = line.split("#", 1)[0].strip()
        if not body or ";" not in body:
            continue
        code_range, prop = (part.strip() for part in body.split(";", 1))
        if prop in emoji_ranges:
            emoji_ranges[prop].append(parse_code_range(code_range))
    return {
        "version": 1,
        "unicode_version": UNICODE_VERSION,
        "grapheme_break": merged_gcb,
        "extended_pictographic": merge_ranges(emoji_ranges["Extended_Pictographic"]),
        "emoji": merge_ranges(emoji_ranges["Emoji"]),
    }


def parse_emoji_test(text: str) -> tuple[list[dict], list[dict]]:
    """Return canonical rows and only listed aliases that resolve unambiguously."""
    canonical: list[dict] = []
    variants: list[tuple[str, str]] = []
    seen: set[str] = set()
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line or ";" not in line:
            continue
        cp_text, status = (part.strip() for part in line.split(";", 1))
        sequence = "".join(chr(int(cp, 16)) for cp in cp_text.split())
        if status in ("fully-qualified", "component"):
            if sequence in seen:
                continue
            seen.add(sequence)
            canonical.append({"sequence": sequence, "codepoints": codepoints(sequence)})
        elif status in ("minimally-qualified", "unqualified"):
            variants.append((sequence, status))

    bases: dict[str, list[str]] = {}
    for row in canonical:
        bases.setdefault(remove_vs16(row["sequence"]), []).append(row["sequence"])
    aliases: dict[str, str] = {}
    for sequence, _status in variants:
        targets = bases.get(remove_vs16(sequence), [])
        if len(targets) == 1 and sequence != targets[0]:
            aliases[sequence] = targets[0]
    return canonical, [
        {"sequence": sequence, "canonical": target}
        for sequence, target in sorted(aliases.items(), key=lambda item: item[0])
    ]


def fixture_rows(canonical: list[dict]) -> list[dict]:
    by_sequence = {row["sequence"]: row for row in canonical}
    missing = [sequence for sequence in FIXTURES if sequence not in by_sequence]
    if missing:
        raise ValueError(f"fixture sequences absent from Emoji {UNICODE_VERSION}: {missing!r}")
    return [by_sequence[sequence] for sequence in FIXTURES]


def atlas_slot(index: int) -> tuple[int, list[int]]:
    per_page = COLS * ROWS_PER_PAGE
    page, local_index = divmod(index, per_page)
    x = (local_index % COLS) * TILE
    y = ((local_index // COLS) % ROWS_PER_PAGE) * TILE
    return page, [x, y, TILE, TILE]


def require_complete_coverage(missing: list[dict], allow_missing: bool) -> None:
    if missing and not allow_missing:
        examples = ", ".join(
            f"{row['name']} ({' '.join(codepoints(row['sequence']))}: {row['reason']})"
            for row in missing[:12]
        )
        raise RuntimeError(
            f"font does not cover {len(missing)} canonical Emoji {UNICODE_VERSION} sequences; "
            f"refusing full atlas. Examples: {examples}"
        )


class HarfBuzz:
    """Small ctypes wrapper used only to validate exact sequence shaping."""

    class GlyphInfo(ctypes.Structure):
        _fields_ = [("codepoint", ctypes.c_uint32), ("mask", ctypes.c_uint32),
                    ("cluster", ctypes.c_uint32), ("var1", ctypes.c_uint32),
                    ("var2", ctypes.c_uint32)]

    def __init__(self, font_path: Path):
        library = ctypes.util.find_library("harfbuzz")
        if not library:
            raise RuntimeError("libharfbuzz is required for exact emoji sequence coverage checks")
        self.lib = ctypes.CDLL(library)
        self._declare("hb_blob_create", ctypes.c_void_p,
                      [ctypes.c_char_p, ctypes.c_uint, ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p])
        self._declare("hb_face_create", ctypes.c_void_p, [ctypes.c_void_p, ctypes.c_uint])
        self._declare("hb_font_create", ctypes.c_void_p, [ctypes.c_void_p])
        self._declare("hb_ot_font_set_funcs", None, [ctypes.c_void_p])
        self._declare("hb_font_set_scale", None, [ctypes.c_void_p, ctypes.c_int, ctypes.c_int])
        self._declare("hb_buffer_create", ctypes.c_void_p, [])
        self._declare("hb_buffer_add_utf8", None,
                      [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int, ctypes.c_uint, ctypes.c_int])
        self._declare("hb_buffer_guess_segment_properties", None, [ctypes.c_void_p])
        self._declare("hb_shape", None, [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint])
        self._declare("hb_buffer_destroy", None, [ctypes.c_void_p])
        self._declare("hb_buffer_get_glyph_infos", ctypes.POINTER(self.GlyphInfo),
                      [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint)])
        self._declare("hb_version_string", ctypes.c_char_p, [])
        self.version = self.lib.hb_version_string().decode("ascii")
        self.data = font_path.read_bytes()
        # HB_MEMORY_MODE_READONLY; retain self.data for the life of the blob.
        self.blob = self.lib.hb_blob_create(self.data, len(self.data), 1, None, None)
        self.face = self.lib.hb_face_create(self.blob, 0)
        self.font = self.lib.hb_font_create(self.face)
        self.lib.hb_ot_font_set_funcs(self.font)
        ttfont = TTFont(font_path)
        self.lib.hb_font_set_scale(self.font, ttfont["head"].unitsPerEm, ttfont["head"].unitsPerEm)

    def _declare(self, name, result, args):
        function = getattr(self.lib, name)
        function.restype = result
        function.argtypes = args
        return function

    def glyphs(self, sequence: str) -> list[int]:
        encoded = sequence.encode("utf-8")
        buffer = self.lib.hb_buffer_create()
        self.lib.hb_buffer_add_utf8(buffer, encoded, len(encoded), 0, len(encoded))
        self.lib.hb_buffer_guess_segment_properties(buffer)
        self.lib.hb_shape(self.font, buffer, None, 0)
        length = ctypes.c_uint()
        infos = self.lib.hb_buffer_get_glyph_infos(buffer, ctypes.byref(length))
        glyphs = [infos[index].codepoint for index in range(length.value)]
        self.lib.hb_buffer_destroy(buffer)
        return glyphs


def drawable_glyph_ids(font: TTFont) -> set[int]:
    if "CBDT" not in font or "CBLC" not in font:
        return set()
    drawable_names = set()
    for strike in font["CBDT"].strikeData:
        drawable_names.update(strike.keys())
    return {index for index, name in enumerate(font.getGlyphOrder()) if name in drawable_names}


def rasterize(sequence: str, font: ImageFont.FreeTypeFont) -> tuple[Image.Image, tuple[int, int, int, int]]:
    scratch = Image.new("RGBA", (TILE * 4, TILE * 4), (0, 0, 0, 0))
    ImageDraw.Draw(scratch).text((TILE, TILE), sequence, font=font,
                                 embedded_color=True, direction="ltr")
    bbox = scratch.getchannel("A").getbbox()
    if bbox is None:
        raise RuntimeError("shaped sequence produced no bitmap ink")
    ink = scratch.crop(bbox)
    max_ink = TILE - 2 * PADDING
    scale = min(max_ink / ink.width, max_ink / ink.height, 1.0)
    size = (max(1, round(ink.width * scale)), max(1, round(ink.height * scale)))
    if size != ink.size:
        ink = ink.resize(size, Image.Resampling.LANCZOS)
    return ink, bbox


def render_rows(rows: list[dict], drawable: set[int], shaper: HarfBuzz,
                ttfont: TTFont, font: ImageFont.FreeTypeFont) -> tuple[list[dict], list[dict]]:
    names = ttfont.getGlyphOrder()
    missing = []
    renderable = []
    for index, row in enumerate(rows):
        sequence = row["sequence"]
        glyphs = shaper.glyphs(sequence)
        name = row.get("name", f"emoji-{index}")
        reason = None
        if len(glyphs) != 1:
            reason = f"HarfBuzz shaped to {len(glyphs)} glyphs"
        elif glyphs[0] == 0:
            reason = "HarfBuzz returned .notdef"
        elif glyphs[0] not in drawable:
            glyph_name = names[glyphs[0]] if glyphs[0] < len(names) else str(glyphs[0])
            reason = f"glyph {glyph_name} has no color bitmap"
        if reason:
            missing.append({**row, "name": name, "reason": reason})
        else:
            renderable.append(row)
    return renderable, missing


def build_images(rows: list[dict], aliases: list[dict], out_dir: Path, font: ImageFont.FreeTypeFont,
                 font_path: Path, ttfont: TTFont, shaper: HarfBuzz, missing: list[dict],
                 mode: str) -> dict:
    rendered = []
    pages = []
    page_count = math.ceil(len(rows) / (COLS * ROWS_PER_PAGE))
    for page_index in range(page_count):
        page_rows = rows[page_index * COLS * ROWS_PER_PAGE:(page_index + 1) * COLS * ROWS_PER_PAGE]
        used_rows = math.ceil(len(page_rows) / COLS)
        page = Image.new("RGBA", (PAGE_SIZE, used_rows * TILE), (0, 0, 0, 0))
        for local_index, row in enumerate(page_rows):
            global_index = page_index * COLS * ROWS_PER_PAGE + local_index
            _page, rect = atlas_slot(global_index)
            x, y = rect[:2]
            ink, _bbox = rasterize(row["sequence"], font)
            dest = (x + (TILE - ink.width) // 2, y + (TILE - ink.height) // 2)
            page.alpha_composite(ink, dest)
            rendered.append({
                "sequence": row["sequence"], "page": page_index,
                "rect": rect, "name": row["name"],
                "codepoints": row["codepoints"],
            })
        filename = f"atlas-{page_index:03d}.png"
        path = out_dir / filename
        page.save(path, format="PNG", optimize=False, compress_level=9)
        pages.append({"path": f"res://emoji/{filename}", "width": page.width,
                      "height": page.height, "sha256": sha256(path),
                      "format": "RGBA8", "mipmaps": False})

    family = ttfont["name"].getDebugName(1)
    version = ttfont["name"].getDebugName(5)
    sources = {}
    for filename, url in UNICODE_SOURCES.items():
        path = DATA_DIR / filename
        sources[filename] = {"url": url, "sha256": sha256(path)}
    properties = parse_unicode_properties(EMOJI_DATA.read_text(encoding="utf-8"),
                                          GRAPHEME_DATA.read_text(encoding="utf-8"))
    (out_dir / "properties.json").write_text(json.dumps(properties, separators=(",", ":")) + "\n")
    manifest = {
        "version": 2,
        "unicode_version": UNICODE_VERSION,
        "tile_size": TILE,
        "padding_px": PADDING,
        "pages": pages,
        "properties": "res://emoji/properties.json",
        "entries": rendered,
        "aliases": [alias for alias in aliases if alias["canonical"] in {r["sequence"] for r in rows}],
        "unicode_sources": sources,
        "unicode_license": {"file": "UNICODE-LICENSE.txt", "license": "Unicode License V3",
                            "source": "https://github.com/unicode-org/unicodetools/blob/main/LICENSE"},
        "coverage": {"canonical_count": len(rows) + len(missing),
                     "rendered_count": len(rendered), "missing": missing,
                     "kind": "fixture-subset" if mode == "fixtures" else "full-canonical",
                     "complete": not missing and mode == "full"},
        "rendering": {"strike_px": 109, "padding_px": PADDING, "tool": "Pillow",
                      "pillow_version": pillow_version, "layout_engine": "RAQM",
                      "fonttools_version": fontTools.version, "harfbuzz_version": shaper.version,
                      "resampling": "LANCZOS", "normalization": "fit ink inside 56x56; centered"},
        "source_font": {"family": family, "version": version,
                        "font_revision": ttfont["head"].fontRevision,
                        "filename": font_path.name, "sha256": sha256(font_path),
                        "license_file": "LICENSE.txt", "license": "SIL Open Font License 1.1"},
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--font", type=Path, default=Path(FONT_PATH))
    parser.add_argument("--license", type=Path, default=Path(FONT_LICENSE_PATH))
    parser.add_argument("--out", type=Path, default=Path("app/emoji"))
    parser.add_argument("--fixtures", action="store_true", help="build the small legacy fixture subset")
    parser.add_argument("--allow-missing", action="store_true",
                        help="research only: emit a manifest listing uncovered sequences")
    args = parser.parse_args()
    if not args.font.is_file() or not args.license.is_file():
        parser.error("--font and --license must point to existing files")
    for source in (EMOJI_TEST, EMOJI_DATA, GRAPHEME_DATA, UNICODE_LICENSE):
        if not source.is_file():
            parser.error(f"missing pinned Unicode input: {source}")

    data = EMOJI_TEST.read_text(encoding="utf-8")
    if f"# Version: {UNICODE_VERSION}" not in data:
        parser.error(f"{EMOJI_TEST} is not Unicode {UNICODE_VERSION}")
    canonical, aliases = parse_emoji_test(data)
    rows = fixture_rows(canonical) if args.fixtures else canonical
    names_by_sequence = {}
    for line in data.splitlines():
        if ";" in line and "#" in line:
            cp_text, rest = line.split(";", 1)
            if rest.split("#", 1)[0].strip() in ("fully-qualified", "component"):
                sequence = "".join(chr(int(cp, 16)) for cp in cp_text.split())
                comment = line.split("#", 1)[1].strip()
                name_match = re.search(r"\s(E\d+(?:\.\d+)?\s+.*)$", comment)
                names_by_sequence[sequence] = name_match.group(1) if name_match else comment
    rows = [{**row, "name": names_by_sequence.get(row["sequence"], "")}
            for row in rows]

    ttfont = TTFont(args.font)
    strikes = ttfont["CBLC"].strikes if "CBLC" in ttfont else []
    if not any(s.bitmapSizeTable.ppemX == 109 and s.bitmapSizeTable.ppemY == 109 for s in strikes):
        parser.error("font must contain the pinned 109x109 color bitmap strike")
    if not features.check("raqm"):
        parser.error("Pillow must be built with RAQM for shaping consistency")
    font = ImageFont.truetype(str(args.font), 109, layout_engine=ImageFont.Layout.RAQM)
    shaper = HarfBuzz(args.font)
    renderable, missing = render_rows(rows, drawable_glyph_ids(ttfont), shaper, ttfont, font)
    require_complete_coverage(missing, args.allow_missing or args.fixtures)
    if missing:
        print(f"Research build: {len(missing)} of {len(rows)} sequences have no exact drawable glyph.",
              file=sys.stderr)

    out_dir = args.out
    out_dir.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix="emoji-atlas-", dir=out_dir.parent))
    try:
        manifest = build_images(renderable, aliases, stage, font, args.font, ttfont,
                                shaper, missing, "fixtures" if args.fixtures else "full")
        # All coverage checks and output generation succeeded before touching the current atlas.
        out_dir.mkdir(parents=True, exist_ok=True)
        for stale in out_dir.glob("atlas-*.png"):
            stale.unlink()
        legacy = out_dir / "atlas.png"
        if legacy.exists():
            legacy.unlink()
        for filename in (stage / "manifest.json", stage / "properties.json", *sorted(stage.glob("atlas-*.png"))):
            shutil.move(str(filename), out_dir / filename.name)
        shutil.copyfile(args.license, out_dir / "LICENSE.txt")
        shutil.copyfile(UNICODE_LICENSE, out_dir / "UNICODE-LICENSE.txt")
    finally:
        shutil.rmtree(stage, ignore_errors=True)
    print(f"Wrote {len(manifest['pages'])} pages and {len(manifest['entries'])}/{manifest['coverage']['canonical_count']} canonical sequences")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, ValueError) as error:
        print(f"emoji atlas: {error}", file=sys.stderr)
        sys.exit(1)
