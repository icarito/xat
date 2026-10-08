extends SceneTree

const Sequences = preload("res://addons/xat_xmpp/ui/emoji_sequences.gd")
var _fail := 0

func _init():
	var manifest = _read_json("res://emoji/manifest.json")
	var properties = _read_json(manifest.get("properties", "res://emoji/properties.json"))
	check(manifest.get("version", 0) == 2, "catalog manifest v2")
	check(manifest.get("unicode_version", "") == "17.0", "catalog pinned to Unicode 17.0")
	check(properties.get("unicode_version", "") == "17.0", "grapheme properties pinned to Unicode 17.0")
	var entries: Array = manifest.get("entries", [])
	var aliases: Array = manifest.get("aliases", [])
	check(entries.size() == 3953, "all 3953 canonical RGI entries present")
	check(aliases.size() == 1272, "all 1272 listed qualification aliases present")
	var supported := []
	for entry in entries:
		supported.append(entry.get("sequence", ""))
	for alias in aliases:
		supported.append(alias.get("sequence", ""))
	var lookup = Sequences.compile(supported, properties)
	var bad = 0
	for sequence in supported:
		var runs = Sequences.tokenize_indexed(sequence, lookup)
		if runs.size() != 1 or runs[0].kind != "emoji" or runs[0].text != sequence:
			bad += 1
	check(bad == 0, "every catalog sequence tokenizes as exactly one matching emoji")
	var pair = Sequences.tokenize_indexed("😀❤️", lookup)
	check(pair.size() == 2 and pair[0].kind == "emoji" and pair[1].kind == "emoji", "adjacent canonical sequences remain separate")
	if _fail == 0:
		print("EMOJI_CATALOG_CHECK_OK canonical=%d aliases=%d checked=%d" % [entries.size(), aliases.size(), supported.size()])
	quit()

func _read_json(path: String) -> Dictionary:
	var file := File.new()
	if file.open(path, File.READ) != OK:
		return {}
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	return parsed.result if parsed.error == OK and parsed.result is Dictionary else {}

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
		return
	_fail += 1
	print("FAIL %s" % label)
	OS.exit_code = 1
