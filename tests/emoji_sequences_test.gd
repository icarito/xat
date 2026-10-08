extends SceneTree

var _fail := 0

func _init():
	var Sequences = load("res://addons/xat_xmpp/ui/emoji_sequences.gd")
	var supported = ["😀", "❤️", "👩‍💻", "🇵🇪", "1️⃣", "🏴󠁧󠁢󠁥󠁮󠁧󠁿", "👍"]

	check(Sequences.tokenize("😀❤️", supported).size() == 2, "adjacent known sequences")
	check(_kinds(Sequences.tokenize("x👩‍💻y", supported)) == ["text", "emoji", "text"], "known ZWJ compound")
	check(_emoji_texts(Sequences.tokenize("🇵🇪🇺🇸", ["🇵🇪", "🇺🇸"])) == ["🇵🇪", "🇺🇸"], "two regional pairs")
	var odd_flags = Sequences.tokenize("🇵🇪🇦", ["🇵🇪"])
	check(_emoji_texts(odd_flags) == ["🇵🇪"] and odd_flags[1].kind == "text" and odd_flags[1].text == "🇦", "odd regional indicator remains text")
	check(_same_text(Sequences.tokenize("👍🏽‍🦾", ["👍"]), "👍🏽‍🦾"), "no supported prefix before modifier and ZWJ")
	check(_same_text(Sequences.tokenize("🇵🇪︎", ["🇵🇪"]), "🇵🇪︎"), "no flag prefix before VS15")
	check(_same_text(Sequences.tokenize("🇵🇪🏽", ["🇵🇪"]), "🇵🇪🏽"), "no flag prefix before modifier")
	check(_same_text(Sequences.tokenize("🇵🇪󠁡", ["🇵🇪"]), "🇵🇪󠁡"), "no flag prefix before tag")
	check(_same_text(Sequences.tokenize("🇵🇪‍👩", ["🇵🇪"]), "🇵🇪‍👩"), "no flag prefix before ZWJ chain")
	check(_same_text(Sequences.tokenize("👩‍unknown", ["👩"]), "👩‍unknown"), "no supported prefix before unknown ZWJ tail")
	check(_same_text(Sequences.tokenize("❤️︎", ["❤️"]), "❤️︎"), "VS15 forces text")
	var digit_and_keycap = Sequences.tokenize("1 1️⃣", ["1️⃣"])
	check(digit_and_keycap[0].kind == "text" and digit_and_keycap[0].text == "1 " and _emoji_texts(digit_and_keycap) == ["1️⃣"], "ASCII digit stays text and keycap is not split")
	check(_emoji_texts(Sequences.tokenize("1️⃣", ["1️⃣"])) == ["1️⃣"], "supported keycap")
	check(_emoji_texts(Sequences.tokenize("🏴󠁧󠁢󠁥󠁮󠁧󠁿", ["🏴󠁧󠁢󠁥󠁮󠁧󠁿"])) == ["🏴󠁧󠁢󠁥󠁮󠁧󠁿"], "tag flag")
	check(_same_text(Sequences.tokenize("é", []), "é"), "combining accent untouched")
	check(Sequences.tokenize("😀", []).size() == 1 and Sequences.tokenize("😀", [])[0].kind == "text", "no support means text")
	check(Sequences.tokenize("", supported).empty(), "empty input")

	var indexed = Sequences.tokenize("á😀z", ["😀"])
	check(indexed.size() == 3 and indexed[1].start == 1 and indexed[1].end == 2 and indexed[2].start == 2, "offsets count Unicode scalars")
	check(_roundtrips(Sequences.tokenize("á👩‍💻!👍🏽", supported), "á👩‍💻!👍🏽"), "source roundtrip")
	var alias = "❤"
	var compiled = Sequences.compile(["😀", "❤️", alias], {
		"grapheme_break": [[0x1AB0, 0x1AB0, "Extend"], [0x20D0, 0x20FF, "Extend"]],
		"extended_pictographic": [[0x1F000, 0x1FAFF]],
		"emoji": [[0x23, 0x23], [0x2A, 0x2A], [0x30, 0x39], [0x1F000, 0x1FAFF]]
	})
	check(_emoji_texts(Sequences.tokenize_indexed("❤", compiled)) == [alias], "compiled lookup accepts exact unqualified alias")
	check(_same_text(Sequences.tokenize_indexed("😀᪰", compiled), "😀᪰"), "Unicode 17 extender blocks supported prefix")
	check(_same_text(Sequences.tokenize_indexed("😀⃐", compiled), "😀⃐"), "supplementary combining range blocks supported prefix")
	check(_same_text(Sequences.tokenize_indexed("1", compiled), "1"), "Emoji property keeps bare digit as text")
	check(_emoji_texts(Sequences.tokenize_indexed("1️⃣", Sequences.compile(["1️⃣"], {"emoji": [[0x30, 0x39]]}))) == ["1️⃣"], "compiled lookup accepts keycap sequence")

	if _fail == 0:
		print("EMOJI_SEQUENCES_CHECK_OK")
	quit()

func _kinds(runs: Array) -> Array:
	var result = []
	for run in runs:
		result.append(run.kind)
	return result

func _emoji_texts(runs: Array) -> Array:
	var result = []
	for run in runs:
		if run.kind == "emoji":
			result.append(run.text)
	return result

func _same_text(runs: Array, expected: String) -> bool:
	return runs.size() == 1 and runs[0].kind == "text" and runs[0].text == expected

func _roundtrips(runs: Array, source: String) -> bool:
	var rebuilt = ""
	for run in runs:
		rebuilt += run.text
	return rebuilt == source

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
