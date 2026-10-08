extends Control

# Conversación local para revisar baseline, wrapping, Markdown y copia Unicode.
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")
const Palette = preload("res://addons/xat_xmpp/ui/palette.gd")
const Bubble = preload("res://addons/xat_xmpp/ui/bubble.gd")

func _ready() -> void:
	theme = XatTheme.build()
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	var margins := MarginContainer.new()
	add_child(margins)
	margins.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	for side in ["left", "top", "right", "bottom"]:
		margins.add_constant_override("margin_" + side, 24)
	var column := VBoxContainer.new()
	column.add_constant_override("separation", 12)
	margins.add_child(column)
	var title := Label.new()
	title.text = "Emojis Unicode 17.0"
	title.add_font_override("font", XatTheme.font(Palette.FONT_BOLD, 24))
	column.add_child(title)
	var hint := Label.new()
	hint.text = "Texto Slug + emojis rasterizados · selecciona y copia · Ctrl + rueda para zoom"
	hint.add_color_override("font_color", Palette.TEXT_DIM)
	column.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var conversation := VBoxContainer.new()
	conversation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conversation.add_constant_override("separation", 8)
	scroll.add_child(conversation)
	var bodies = [
		"Caritas: 😀 😃 😄 😁 😆 😅 😂 🙂 🙃 🥹 🫠 🧑‍🚀",
		"Gestos: 👋 👋🏻 👋🏽 👋🏿 👍 👍🏽 👎 👏 🙌 🫶",
		"Corazones: ❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 💕",
		"Objetos: 🎉 🎂 🎁 💡 📱 💻 🚀 🔥 ⚽ 🎸",
		"Animales: 🐶 🐱 🐭 🐰 🦊 🐻 🐼 🐸 🦋 🦄",
		"Símbolos: ✅ ❌ ⚠️ ♻️ ✨ 💯 🔱 ☮️ ♾️",
		"Banderas: 🇵🇪 🇺🇸 🇯🇵 🇧🇷 🇲🇽 🏳️‍🌈 🏴‍☠️",
		"Zodiaco: ♈ ♉ ♊ ♋ ♌ ♍ ♎ ♏ ♐ ♑ ♒ ♓",
		"Secuencias completas: 👩‍💻 · 👨‍👩‍👧‍👦 · 🇵🇪 · 🇺🇸 · 1️⃣",
		"👩‍💻 👨‍👩‍👧‍👦 🇵🇪 1️⃣ " + "Texto que obliga a envolver la línea con una familia 👨‍👩‍👧‍👦 y un tono 👍🏽 sin separarlos. ".repeat(3),
		"[Enlace con emoji 🚀](https://example.org) y código literal `👩‍💻` / `[emoji=20,1f600]`",
		"Presentación conservada: ❤ / ❤️ / ❤︎. No cubierto: 🫿 (reservado) permanece como texto Unicode.",
		"👨‍👩‍👧‍👦",
	]
	for i in range(bodies.size()):
		var bubble = Bubble.new()
		conversation.add_child(bubble)
		bubble.set_record({"body": bodies[i], "direction": "in" if i % 2 == 0 else "out", "timestamp": "2026-10-08T15:30:00Z"}, true, false)

func _input(p_event: InputEvent) -> void:
	if p_event is InputEventMouseButton and p_event.pressed and p_event.control:
		var zoom = get_node_or_null("/root/FontZoom")
		if zoom != null and p_event.button_index == BUTTON_WHEEL_UP:
			zoom.zoom_in()
		elif zoom != null and p_event.button_index == BUTTON_WHEEL_DOWN:
			zoom.zoom_out()
