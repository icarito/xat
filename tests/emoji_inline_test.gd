extends SceneTree

const Markdown = preload("res://addons/xat_xmpp/xmpp/markdown.gd")
const EmojiInline = preload("res://addons/xat_xmpp/ui/emoji_inline.gd")
const Bubble = preload("res://addons/xat_xmpp/ui/bubble.gd")
const FontZoom = preload("res://addons/xat_xmpp/ui/font_zoom.gd")

var _fail := 0

func _init():
	call_deferred("_run")

func _run() -> void:
	var script = load(EmojiInline.SCRIPT_PATH)
	if script.has_meta(EmojiInline.CACHE_KEY):
		script.remove_meta(EmojiInline.CACHE_KEY)
	var provider = EmojiInline.new(20)
	check(provider.available(), "Unicode 17 provider loads catalog")
	if not provider.available():
		_finish()
		return
	check(provider._state["sequences"].size() == 5225, "provider indexes canonical sequences and aliases")
	check(provider._state["pages"].empty(), "provider does not load atlas pages during catalog setup")
	check(provider._state["manifest"]["coverage"]["canonical_count"] == 3953 and provider._state["manifest"]["coverage"]["rendered_count"] == 3953, "manifest declares complete rendered canonical coverage")

	var source = "A👩‍💻B"
	var replacement = provider.replacement(source, 1)
	check(not replacement.empty() and replacement["length"] == 3, "provider matches full ZWJ fixture")
	check(provider.line_width("👩‍💻", _test_font()) == float(provider.size), "emoji advance equals configured size")
	check(provider._state["pages"].size() == 1, "first replacement loads just its atlas page")
	var first_page: int = provider._state["entries"]["👩‍💻"]["page"]
	var same_page_sequence := _sequence_on_page(provider._state, first_page, "👩‍💻")
	if same_page_sequence != "":
		provider.replacement(same_page_sequence, 0)
		check(provider._state["pages"].size() == 1, "sequences on one page share its loaded texture")
	var alias = "❤"
	var alias_replacement = provider.replacement(alias, 0)
	check(not alias_replacement.empty() and provider._state["canonical"][alias] == "❤️", "unqualified heart alias resolves to canonical artwork")
	check(provider._state["paths"][alias] == provider._state["paths"]["❤️"] and provider._state["tiles"].has("❤️"), "alias and canonical sequence share one texture tile")

	var markdown = Markdown.to_bbcode(source, provider)
	check(markdown.find("[emoji=20,1f469-200d-1f4bb]") >= 0, "markdown emits inline fixture tag")
	check(Markdown.to_bbcode("`👩‍💻`", provider).find("[emoji=") < 0, "inline code keeps source emoji text")
	check(Markdown.to_bbcode("```\n👩‍💻\n```", provider).find("[emoji=") < 0, "fenced code keeps source emoji text")
	var link = Markdown.to_bbcode("[👩‍💻](https://example.test/😀)", provider)
	check(link.find("[url=https://example.test/😀]") >= 0 and link.find("[emoji=") >= 0, "link label renders emoji and URL target remains literal")
	check(Markdown.to_bbcode("[emoji=20,1f600]literal[/emoji]", provider).find("[lb]emoji=") >= 0, "literal tag input is escaped")
	check(provider.replacement("👩‍unknown", 0).empty(), "unknown ZWJ sequence remains text")

	var root = get_root()
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.selection_enabled = true
	root.add_child(label)
	check(label.has_method("add_inline_image"), "native renderer exposes source-preserving inline images")
	if label.has_method("add_inline_image"):
		var native_sequences = ["😀", "👍🏽", "👩‍💻", "👨‍👩‍👧‍👦", "🇵🇪", "1️⃣", "🧑‍🚀", "❤", "1⃣", _sequence_on_page(provider._state, 15, "")]
		for sequence in native_sequences:
			if sequence == "":
				continue
			label.bbcode_text = Markdown.to_bbcode(sequence, provider)
			check(label.get_total_character_count() == 1, "native atom count is current immediately after parsing: " + EmojiInline._hex(sequence))
			label.visible_characters = -1
			yield(self, "idle_frame")
			check(label.get_text() == sequence, "native source text: " + EmojiInline._hex(sequence))
			check(label.get_total_character_count() == 1, "fixture occupies one visible atom: " + EmojiInline._hex(sequence))
			label.select_all()
			check(label.get_selected_text() == sequence, "native copy source: " + EmojiInline._hex(sequence))

		label.bbcode_text = Markdown.to_bbcode(source, provider)
		yield(self, "idle_frame")
		label.select_all()
		check(label.get_text() == source and label.get_selected_text() == source, "mixed text selection returns original Unicode")
		label.bbcode_text = "[emoji=20,1f600]res://emoji/runtime/missing.tres[/emoji]"
		yield(self, "idle_frame")
		check(label.get_text() == "😀", "missing image resource falls back to full Unicode")
		for malformed in ["1f600-", "-1f600", "1f--600", "d800", "110000"]:
			label.bbcode_text = "[emoji=20,%s]res://emoji/runtime/missing.tres[/emoji]" % malformed
			yield(self, "idle_frame")
			check(label.get_text() == "" and label.get_total_character_count() == 0, "invalid scalar syntax ignored: " + malformed)
		var too_many = "1f600"
		for i in range(64):
			too_many += "-1f600"
		label.bbcode_text = "[emoji=20,%s]res://emoji/runtime/missing.tres[/emoji]" % too_many
		yield(self, "idle_frame")
		check(label.get_text() == "" and label.get_total_character_count() == 0, "too many scalars are ignored")
		label.bbcode_text = "[emoji=0,1f600]res://emoji/runtime/missing.tres[/emoji]"
		yield(self, "idle_frame")
		check(label.get_text() == "" and label.get_total_character_count() == 0, "invalid size parameter is ignored")
		label.bbcode_text = "[img]%s[/img]" % provider._state["paths"]["😀"]
		yield(self, "idle_frame")
		label.select_all()
		check(label.get_total_character_count() == 1 and label.get_text() == "" and label.get_selected_text() == "", "ordinary cached image adds no source text or alt text")
	label.queue_free()

	var zoom = root.get_node_or_null("FontZoom")
	var made_zoom = zoom == null
	if made_zoom:
		zoom = FontZoom.new()
		zoom.name = "FontZoom"
		root.add_child(zoom)
	var bubble = Bubble.new()
	root.add_child(bubble)
	var first_body = "A👩‍💻B"
	bubble.set_record({"body": first_body, "direction": "in", "timestamp": "2026-10-08T12:00:00Z"}, true, false)
	yield(self, "idle_frame")
	bubble._label.select_all()
	check(bubble._label.get_text() == first_body and bubble._label.get_selected_text() == first_body, "bubble record displays and copies original body")
	var corrected_body = "corregido 👩‍💻"
	bubble.set_record({"body": corrected_body, "direction": "in", "timestamp": "2026-10-08T12:00:00Z", "edited": true}, true, false)
	yield(self, "idle_frame")
	bubble._label.select_all()
	check(bubble.rec["body"] == corrected_body and bubble._label.get_selected_text() == corrected_body, "bubble correction refreshes emoji source")
	var old_size = bubble._emoji.size
	var old_scale = zoom.scale
	zoom.set_scale(old_scale + FontZoom.STEP)
	yield(self, "idle_frame")
	bubble._label.select_all()
	check(bubble._emoji.size > old_size and bubble._emoji.size == int(bubble._font.get_height()) and bubble._label.get_selected_text() == corrected_body, "font zoom refreshes inline size and preserves copy")
	zoom.set_scale(old_scale)
	bubble.queue_free()
	if made_zoom:
		zoom.queue_free()
	_finish()

func _test_font() -> DynamicFont:
	var font := DynamicFont.new()
	font.font_data = load("res://fonts/NotoSans-Regular.ttf")
	font.size = 20
	return font

func _sequence_on_page(state: Dictionary, page: int, excluded: String) -> String:
	for sequence in state["entries"]:
		if sequence != excluded and int(state["entries"][sequence]["page"]) == page:
			return sequence
	return ""

func _finish() -> void:
	if _fail == 0:
		print("EMOJI_INLINE_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
