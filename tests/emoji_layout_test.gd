extends SceneTree

const EmojiInline = preload("res://addons/xat_xmpp/ui/emoji_inline.gd")
const Markdown = preload("res://addons/xat_xmpp/xmpp/markdown.gd")

var _fail := 0

func _init():
	call_deferred("_run")

func _run() -> void:
	var provider = EmojiInline.new(24)
	var root = get_root()

	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.selection_enabled = true
	label.scroll_active = false
	label.rect_position = Vector2(32, 32)
	label.rect_size = Vector2(200, 120)
	label.add_font_override("normal_font", _test_font())
	label.add_color_override("default_color", Color(1, 1, 1, 1))
	root.add_child(label)
	var mixed = "AAAA👩‍💻BBBB"
	label.bbcode_text = Markdown.to_bbcode(mixed, provider)
	label.visible_characters = -1
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var wide_height = label.get_content_height()
	label.rect_size.x = 48
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var narrow_height = label.get_content_height()
	check(label.get_total_character_count() == 9, "wrapped mixed source keeps one atom for the emoji")
	check(narrow_height > wide_height, "narrow layout wraps mixed text around the whole emoji")
	label.select_all()
	check(label.get_selected_text() == mixed, "wrapping preserves source selection")

	label.bbcode_text = Markdown.to_bbcode("👩‍💻", provider)
	label.rect_size.x = 200
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var emoji_wide_height = label.get_content_height()
	label.rect_size.x = 48 # one 24px image plus RichTextLabel margins
	label.visible_characters = 0
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var emoji_narrow_height = label.get_content_height()
	check(emoji_narrow_height == emoji_wide_height, "emoji atom does not split at a width larger than tile and margins")
	var hidden = root.get_texture().get_data()
	hidden.flip_y()
	hidden.lock()
	label.visible_characters = 1
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	var shown = root.get_texture().get_data()
	shown.flip_y()
	shown.lock()
	check(label.get_total_character_count() == 1 and label.get_visible_characters() == 1, "emoji reveal advances one whole atom")
	check(_pixel_differences(hidden, shown, Rect2(24, 24, 64, 64)) >= 8, "revealing emoji changes rendered pixels")
	hidden.unlock()
	shown.unlock()
	label.queue_free()

	if _fail == 0:
		print("EMOJI_LAYOUT_CHECK_OK")
	quit()

func _test_font() -> DynamicFont:
	var font := DynamicFont.new()
	font.font_data = load("res://fonts/NotoSans-Regular.ttf")
	font.size = 20
	return font

func _pixel_differences(a: Image, b: Image, rect: Rect2) -> int:
	var changed = 0
	for y in range(int(rect.position.y), int(rect.position.y + rect.size.y)):
		for x in range(int(rect.position.x), int(rect.position.x + rect.size.x)):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				changed += 1
	return changed

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
