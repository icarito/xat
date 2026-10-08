import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("build_emoji_atlas", ROOT / "tools/build_emoji_atlas.py")
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)


class EmojiAtlasDataTests(unittest.TestCase):
    def test_only_fully_qualified_and_components_are_canonical(self):
        canonical, aliases = BUILDER.parse_emoji_test(
            """# Version: 17.0
                1F600 ; fully-qualified # 😀 E1.0 grinning face
                2764 FE0F ; fully-qualified # ❤️ E0.6 red heart
                2764 ; minimally-qualified # ❤ E0.6 red heart
                1F3FB ; component # 🏻 E1.0 light skin tone
                1F600 ; unqualified # 😀 E1.0 grinning face
                1F600 FE0F ; unqualified # 😀 E1.0 listed emoji variation
            """
        )
        self.assertEqual([row["sequence"] for row in canonical], ["😀", "❤️", "🏻"])
        self.assertEqual(aliases, [
            {"sequence": "❤", "canonical": "❤️"},
            {"sequence": "😀️", "canonical": "😀"},
        ])

    def test_only_exact_test_data_variants_become_aliases(self):
        canonical, aliases = BUILDER.parse_emoji_test(
            "1F44D FE0F ; fully-qualified # 👍️\n"
            "1F44D ; minimally-qualified # 👍\n"
        )
        self.assertEqual(len(canonical), 1)
        self.assertEqual(aliases, [{"sequence": "👍", "canonical": "👍️"}])
        self.assertNotIn({"sequence": "👍🏽", "canonical": "👍️"}, aliases)

    def test_full_coverage_rejects_missing_glyphs_unless_research_opted_in(self):
        missing = [{"name": "new emoji", "sequence": "🫩", "reason": ".notdef"}]
        with self.assertRaisesRegex(RuntimeError, "refusing full atlas"):
            BUILDER.require_complete_coverage(missing, allow_missing=False)
        BUILDER.require_complete_coverage(missing, allow_missing=True)

    def test_unicode_properties_are_sorted_and_cover_expected_classes(self):
        properties = BUILDER.parse_unicode_properties(
            """0041 ; Emoji
1F600 ; Emoji
1F600 ; Extended_Pictographic
""",
            """0300..0301 ; Extend
0302 ; Extend
200D ; ZWJ
""",
        )
        self.assertEqual(properties["emoji"], [[0x41, 0x41], [0x1F600, 0x1F600]])
        self.assertEqual(properties["extended_pictographic"], [[0x1F600, 0x1F600]])
        self.assertEqual(properties["grapheme_break"], [[0x300, 0x302, "Extend"], [0x200D, 0x200D, "ZWJ"]])

    def test_page_slots_stay_within_1024px_page_bounds(self):
        self.assertEqual(BUILDER.atlas_slot(0), (0, [0, 0, 64, 64]))
        self.assertEqual(BUILDER.atlas_slot(255), (0, [960, 960, 64, 64]))
        self.assertEqual(BUILDER.atlas_slot(256), (1, [0, 0, 64, 64]))

    def test_pinned_unicode_data_is_complete_17_0_release(self):
        content = (ROOT / "tools/emoji-data/17.0/emoji-test.txt").read_text()
        self.assertIn("# Version: 17.0", content)
        canonical, _aliases = BUILDER.parse_emoji_test(content)
        self.assertEqual(len(canonical), 3953)
        self.assertIn("# fully-qualified : 3944", content)


if __name__ == "__main__":
    unittest.main()
