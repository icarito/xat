extends Reference

# Proveedor raster Unicode versionado. Sólo presentación, conserva el body.
# Las páginas se cargan bajo demanda; canonical y aliases comparten artwork.
const Sequences = preload("res://addons/xat_xmpp/ui/emoji_sequences.gd")
const SCRIPT_PATH := "res://addons/xat_xmpp/ui/emoji_inline.gd"
const MANIFEST_PATH := "res://emoji/manifest.json"
const CACHE_KEY := "xat_emoji_atlas_v2"

var size := 20
var _state := {}
var _lines := {}

func _init(p_size: int = 20) -> void:
	size = max(1, p_size)
	_state = _assets()

func available() -> bool:
	return not _state.empty()

# Se llama sobre texto fuente antes de generar BBCode; el código queda intacto.
func replacement(p_line: String, p_index: int) -> Dictionary:
	if not available():
		return {}
	if not _lines.has(p_line):
		var matches := {}
		for run in Sequences.tokenize_indexed(p_line, _state["lookup"]):
			if run["kind"] == "emoji":
				matches[run["start"]] = run
		_lines[p_line] = matches
	if not _lines[p_line].has(p_index):
		return {}
	var run = _lines[p_line][p_index]
	var path = _tile_path(run["text"])
	if path == "":
		return {}
	# El tag codifica la secuencia recibida, incluso si el arte usa un alias.
	return {"length": run["end"] - run["start"], "markup": "[emoji=%d,%s]%s[/emoji]" % [size, _hex(run["text"]), path]}

func line_width(p_line: String, p_font: Font) -> float:
	if not available():
		return p_font.get_string_size(p_line).x
	var width := 0.0
	for run in Sequences.tokenize_indexed(p_line, _state["lookup"]):
		width += size if run["kind"] == "emoji" and _tile_path(run["text"]) != "" else p_font.get_string_size(run["text"]).x
	return width

func _tile_path(p_sequence: String) -> String:
	if _state["paths"].has(p_sequence):
		return _state["paths"][p_sequence]
	var canonical: String = _state["canonical"].get(p_sequence, "")
	if canonical == "":
		return ""
	var path = "res://emoji/runtime/v2/%s.tres" % _hex(canonical)
	if not _state["tiles"].has(canonical):
		var entry: Dictionary = _state["entries"][canonical]
		var page_index: int = entry["page"]
		var texture = _page(page_index)
		if texture == null:
			return ""
		var rect: Array = entry["rect"]
		var tile := AtlasTexture.new()
		tile.atlas = texture
		tile.region = Rect2(rect[0], rect[1], rect[2], rect[3])
		tile.filter_clip = true
		# ResourceLoader consume este recurso en caché; no necesita un .tres físico.
		tile.take_over_path(path)
		_state["tiles"][canonical] = tile
	_state["paths"][p_sequence] = path
	_state["paths"][canonical] = path
	return path

func _page(p_index: int):
	if _state["pages"].has(p_index):
		return _state["pages"][p_index]
	if _state["failed_pages"].has(p_index):
		return null
	var page: Dictionary = _state["manifest"]["pages"][p_index]
	var texture = null
	var path: String = page["path"]
	# Exports pueden remapear el PNG a StreamTexture; frt tools=no lee PNG crudo.
	if ResourceLoader.exists(path, "Texture"):
		texture = load(path)
	else:
		var image := Image.new()
		if image.load(path) == OK:
			texture = ImageTexture.new()
			texture.create_from_image(image, Texture.FLAG_FILTER)
	if texture == null or texture.get_width() != int(page["width"]) or texture.get_height() != int(page["height"]):
		_state["failed_pages"][p_index] = true
		return null
	_state["pages"][p_index] = texture
	return texture

static func _hex(p_sequence: String) -> String:
	var out := []
	for i in range(p_sequence.length()):
		out.append("%x" % p_sequence.ord_at(i))
	return "-".join(out)

static func _assets() -> Dictionary:
	var script = load(SCRIPT_PATH)
	if script.has_meta(CACHE_KEY):
		return script.get_meta(CACHE_KEY)
	var manifest = _read_json(MANIFEST_PATH)
	if manifest.get("version", 0) != 2 or manifest.get("pages", []).empty():
		return {}
	var properties = _read_json(manifest.get("properties", "res://emoji/properties.json"))
	if properties.get("unicode_version", "") != manifest.get("unicode_version", ""):
		return {}
	var state := {"manifest": manifest, "pages": {}, "failed_pages": {}, "tiles": {},
		"paths": {}, "entries": {}, "canonical": {}, "sequences": []}
	for entry in manifest.get("entries", []):
		var sequence: String = entry.get("sequence", "")
		var rect: Array = entry.get("rect", [])
		var page_index: int = entry.get("page", -1)
		if sequence == "" or rect.size() != 4 or page_index < 0 or page_index >= manifest["pages"].size():
			continue
		var page: Dictionary = manifest["pages"][page_index]
		if rect[0] < 0 or rect[1] < 0 or rect[2] <= 0 or rect[3] <= 0 or rect[0] + rect[2] > page["width"] or rect[1] + rect[3] > page["height"]:
			continue
		state["entries"][sequence] = entry
		state["canonical"][sequence] = sequence
		state["sequences"].append(sequence)
	for alias in manifest.get("aliases", []):
		var sequence: String = alias.get("sequence", "")
		var canonical: String = alias.get("canonical", "")
		if sequence == "" or state["canonical"].has(sequence) or not state["entries"].has(canonical):
			continue
		state["canonical"][sequence] = canonical
		state["sequences"].append(sequence)
	if state["sequences"].empty():
		return {}
	state["lookup"] = Sequences.compile(state["sequences"], properties)
	script.set_meta(CACHE_KEY, state)
	return state

static func _read_json(p_path: String) -> Dictionary:
	var file := File.new()
	if file.open(p_path, File.READ) != OK:
		return {}
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	return parsed.result if parsed.error == OK and parsed.result is Dictionary else {}
