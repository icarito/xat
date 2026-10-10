extends VBoxContainer

# Burbuja de chat: fila con la burbuja alineada a un lado, hora/estado debajo
# (sólo en la última del grupo). Sin _process; la entrada usa un Tween.
# Si el mensaje trae `attach`, en vez del link crudo se dibuja la media
# (miniatura, reproductor de audio o chip de archivo).

signal media_action(rec, action) # action: "open" | "play" | "pause"
signal nick_clicked(nick)        # chip de remitente de sala (@mención)

const IconButton = preload("res://addons/xat_xmpp/ui/icon_button.gd")
const AudioWave = preload("res://addons/xat_xmpp/ui/audio_wave.gd")

const LocalTime = preload("res://addons/xat_xmpp/ui/localtime.gd")
const Palette = preload("res://addons/xat_xmpp/ui/palette.gd")
const Markdown = preload("res://addons/xat_xmpp/xmpp/markdown.gd")
const Media = preload("res://addons/xat_xmpp/xmpp/media.gd")
const MediaUtil = preload("res://addons/xat_xmpp/ui/media_util.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")
const EmojiInline = preload("res://addons/xat_xmpp/ui/emoji_inline.gd")

# Paleta de acentos para el chip de remitente (elegida por nick.hash()).
const NICK_COLORS := [Palette.AGENT_EDGE, Palette.OK, Palette.PENDING, Palette.TOOL, Palette.IDLE, Palette.ERROR]

static func color_for(p_nick: String) -> Color:
	if p_nick == "":
		return Palette.TEXT_DIM
	return NICK_COLORS[int(abs(p_nick.hash())) % NICK_COLORS.size()]

const MAX_FRAC := 0.7
const SLIDE := 14.0
const THUMB_MAX := 240

const SCRIPT_PATH := "res://addons/xat_xmpp/ui/bubble.gd"
const BBCODE_CACHE_KEY := "xat_bbcode_cache_v1"
const BBCODE_CACHE_MAX := 400

# Markdown -> BBCode memoizado por (tamaño de emoji, texto). `to_bbcode` compila
# tres RegEx y recorre el texto carácter a carácter en cada llamada; al cambiar
# de chat se reconstruyen todas las burbujas, así que sin esto se re-parseaba
# todo el historial.
static func _bbcode(p_text: String, p_emoji) -> String:
	var size = int(p_emoji.size) if p_emoji != null else 0
	var cache := _bbcode_cache()
	var key = str(size) + "\u0000" + p_text
	if cache.has(key):
		return cache[key]
	var out = Markdown.to_bbcode(p_text, p_emoji)
	if cache.size() >= BBCODE_CACHE_MAX:
		cache.erase(cache.keys()[0])
	cache[key] = out
	return out

static func _bbcode_cache() -> Dictionary:
	var script = load(SCRIPT_PATH)
	if not script.has_meta(BBCODE_CACHE_KEY):
		script.set_meta(BBCODE_CACHE_KEY, {})
	return script.get_meta(BBCODE_CACHE_KEY)

var rec := {}
var _last := false
var _gap := Palette.GAP
var _play := false
var _audio_btn
var _audio_wave
var _audio_info: Label
var _audio_active := false
var _spacer: Control
var _reply_box: PanelContainer
var _reply_quote: Label
var _reply_accent: ColorRect
var _reactions_row: HBoxContainer
var _search_hl := false

func set_search_highlight(p_on: bool) -> void:
	_search_hl = p_on
	_style()
var _panel: PanelContainer
var _label: RichTextLabel
var _meta: Label
var _ticks: Control  # ✓ / ✓✓ dibujados (la fuente no trae el glifo)
var _metarow: HBoxContainer
var _tween: Tween
var _font: Font
var _emoji = null
var _fit_w := -1.0
var _reveal_tw = null # Tween pendiente si la burbuja aún no está en el árbol
var _col: VBoxContainer
var _row: HBoxContainer
var _pad: Control
var _inner: VBoxContainer
var _media_host: VBoxContainer
var _thumb_path := ""
var _thumb_tex = null
var _sender_btn: Button
var _sender := ""

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_constant_override("separation", 0)
	_font = XatTheme.font(Palette.FONT_REGULAR)
	_spacer = Control.new()
	_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_spacer)
	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(row)
	var col = VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE # deja pasar el arrastre al ScrollContainer
	col.add_constant_override("separation", 2)
	col.size_flags_horizontal = 0
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content_height = true
	_label.scroll_active = false
	_label.mouse_filter = Control.MOUSE_FILTER_PASS
	# En táctil el arrastre debe desplazar el chat; la selección se activa con
	# una pulsación larga (chat_panel llama a begin_selection). Sin selección el
	# label no consume el arrastre (IGNORE) y el ScrollContainer se mueve.
	_label.selection_enabled = true
	if OS.has_touchscreen_ui_hint():
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_color_override("default_color", Palette.TEXT)
	_label.add_font_override("normal_font", _font)
	_label.add_font_override("bold_font", XatTheme.font(Palette.FONT_BOLD))
	_label.add_font_override("italics_font", _font)
	_label.add_font_override("bold_italics_font", XatTheme.font(Palette.FONT_BOLD))
	_label.add_font_override("mono_font", XatTheme.font(Palette.FONT_MONO, Palette.FONT_SIZE - 1))
	_inner = VBoxContainer.new()
	_inner.mouse_filter = Control.MOUSE_FILTER_PASS
	_inner.add_constant_override("separation", 6)
	# Cita del mensaje respondido (XEP-0461).
	_reply_box = PanelContainer.new()
	_reply_box.visible = false
	_reply_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reply_box.add_stylebox_override("panel", XatTheme.box(Palette.BG1, 6, 8, 4))
	var reply_row = HBoxContainer.new()
	reply_row.add_constant_override("separation", 6)
	_reply_accent = ColorRect.new()
	_reply_accent.rect_min_size = Vector2(3, 0)
	_reply_accent.color = Palette.AGENT_EDGE
	reply_row.add_child(_reply_accent)
	_reply_quote = Label.new()
	_reply_quote.clip_text = true
	_reply_quote.max_lines_visible = 2
	_reply_quote.add_color_override("font_color", Palette.TEXT_DIM)
	_reply_quote.add_font_override("font", XatTheme.font(Palette.FONT_REGULAR, Palette.FONT_SIZE - 3))
	reply_row.add_child(_reply_quote)
	_reply_box.add_child(reply_row)
	_inner.add_child(_reply_box)
	_media_host = VBoxContainer.new()
	_media_host.mouse_filter = Control.MOUSE_FILTER_PASS
	_media_host.add_constant_override("separation", 4)
	_inner.add_child(_media_host)
	_inner.add_child(_label)
	_panel.add_child(_inner)
	_meta = Label.new()
	_meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meta.add_color_override("font_color", Palette.TEXT_DIM)
	_meta.add_font_override("font", XatTheme.font(Palette.FONT_REGULAR, Palette.FONT_SIZE - 4))
	_ticks = Control.new()
	_ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticks.connect("draw", self, "_draw_ticks")
	_metarow = HBoxContainer.new()
	_metarow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_metarow.add_constant_override("separation", 4)
	_metarow.add_child(_meta)
	_metarow.add_child(_ticks)
	# Chips de reacciones (XEP-0444).
	_reactions_row = HBoxContainer.new()
	_reactions_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reactions_row.add_constant_override("separation", 3)
	_reactions_row.visible = false
	# Chip de remitente (sala): sobre la burbuja, oprimible -> @mención.
	_sender_btn = Button.new()
	_sender_btn.visible = false
	_sender_btn.flat = true
	_sender_btn.focus_mode = Control.FOCUS_NONE
	_sender_btn.size_flags_horizontal = 0 # tamaño mínimo, pegado al inicio
	_sender_btn.add_font_override("font", XatTheme.font(Palette.FONT_MEDIUM, Palette.FONT_SIZE - 3))
	_sender_btn.connect("pressed", self, "_on_sender_pressed")
	col.add_child(_sender_btn)
	col.add_child(_panel)
	col.add_child(_reactions_row)
	col.add_child(_metarow)
	var pad = Control.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col = col
	_row = row
	_pad = pad
	connect("resized", self, "_fit")

func _ready() -> void:
	var zoom = get_node_or_null("/root/FontZoom")
	if zoom != null:
		zoom.connect("scale_changed", self, "_on_font_scale_changed")
	if _reveal_tw != null:
		_reveal_tw.start()
		_reveal_tw = null
	if _play:
		_animate()

func _on_font_scale_changed(_scale: float) -> void:
	refresh()

# p_gap: separación superior (GAP dentro del grupo, GROUP_GAP entre grupos).
func set_record(p_rec: Dictionary, p_last: bool, p_new: bool, p_gap: int = Palette.GAP, p_reveal: bool = false) -> void:
	rec = p_rec
	_last = p_last
	_gap = p_gap
	var out = rec.get("direction", "in") == "out"
	if _col.get_parent() == null:
		if out:
			_row.add_child(_pad)
			_row.add_child(_col)
		else:
			_row.add_child(_col)
			_row.add_child(_pad)
		_panel.size_flags_horizontal = Control.SIZE_SHRINK_END if out else 0
		_metarow.alignment = BoxContainer.ALIGN_END if out else BoxContainer.ALIGN_BEGIN
	_spacer.rect_min_size.y = _gap
	refresh()
	if p_reveal:
		# Máquina de escribir vía Tween sobre percent_visible: cada paso pide
		# redibujo (un RichTextEffect se congela con low_processor_mode y la
		# burbuja quedaba vacía). Tope 0.6 s aunque el mensaje sea largo.
		_label.percent_visible = 0.0
		var tw = Tween.new()
		add_child(tw)
		tw.interpolate_property(_label, "percent_visible", 0.0, 1.0, min(0.6, str(rec.get("body", "")).length() / 90.0 + 0.1))
		tw.connect("tween_all_completed", tw, "queue_free")
		if is_inside_tree():
			tw.start()
		else:
			_reveal_tw = tw
	if p_new:
		if is_inside_tree():
			_animate()
		else:
			_play = true

func set_group_last(p_last: bool) -> void:
	_last = p_last
	_style()
	_update_meta()

# Muestra el nombre del ocupante sobre la burbuja (sólo mensajes de sala
# entrantes, en la primera del grupo). Oprimirlo inserta `@nick` en el composer.
func set_sender(p_nick: String, p_color: Color) -> void:
	_sender = p_nick
	_sender_btn.visible = p_nick != ""
	_sender_btn.text = p_nick
	_sender_btn.add_color_override("font_color", p_color)
	_sender_btn.add_color_override("font_color_hover", p_color.lightened(0.2))
	_sender_btn.hint_tooltip = "Mencionar a @%s" % p_nick

func _on_sender_pressed() -> void:
	if _sender != "":
		emit_signal("nick_clicked", _sender)

func deselect() -> void:
	_label.deselect()

# --- Selección de texto (escritorio: arrastre; táctil: pulsación larga) ---

func text_global_rect() -> Rect2:
	return _label.get_global_rect()

func is_text_visible() -> bool:
	return _label.visible

# --- Selección de texto ---
# El RichTextLabel 3.x no procesa eventos táctiles para seleccionar, pero su
# `_gui_input` sí ancla con un press y extiende con motion. En táctil le
# inyectamos mouse sintético: press al mantener, motion al arrastrar, release al
# soltar. Así se puede elegir sólo una parte del mensaje.
var _drag_active := false
var _last_global := Vector2.ZERO

func begin_selection_at(p_global: Vector2) -> void:
	_label.deselect()
	_drag_active = true
	_feed_mouse(p_global, true)

func drag_selection(p_global: Vector2) -> void:
	if _drag_active:
		_feed_motion(p_global)

func end_selection_drag() -> void:
	if _drag_active:
		_drag_active = false
		_feed_mouse(_last_global, false)

# Selección total (botón "Todo" de la barra).
func select_all() -> void:
	_label.deselect()
	_label.select_all()

func begin_selection() -> void:
	select_all()

func end_selection() -> void:
	if _drag_active:
		end_selection_drag()
	_label.deselect()

func selected_text() -> String:
	return _label.get_selected_text()

func _feed_mouse(p_global: Vector2, p_pressed: bool) -> void:
	_last_global = p_global
	var local = _label.get_global_transform().affine_inverse().xform(p_global)
	var ev = InputEventMouseButton.new()
	ev.button_index = BUTTON_LEFT
	ev.pressed = p_pressed
	ev.position = local
	ev.global_position = p_global
	_label.call("_gui_input", ev)

func _feed_motion(p_global: Vector2) -> void:
	_last_global = p_global
	var local = _label.get_global_transform().affine_inverse().xform(p_global)
	var ev = InputEventMouseMotion.new()
	ev.position = local
	ev.global_position = p_global
	ev.relative = Vector2.ZERO
	_label.call("_gui_input", ev)

# Re-renderiza cuerpo, marcas y estilo (corrección, entrega, media).
func refresh() -> void:
	# Un motor anterior sigue mostrando Unicode normal. No sustituir por imágenes
	# si no sabe devolver su secuencia original al seleccionar/copiar.
	_emoji = EmojiInline.new(int(_font.get_height())) if _label.has_method("add_inline_image") else null
	_render_reply()
	_render_reactions()
	var attach = rec.get("attach", {})
	if bool(rec.get("retracted", false)):
		# Mensaje eliminado (XEP-0424): texto atenuado en cursiva.
		_clear_media()
		_label.visible = true
		_label.bbcode_text = "[i][color=#8b93a7]Mensaje eliminado[/color][/i]"
		_fit_w = -1.0
		_fit()
		_style()
		_update_meta()
		return
	if attach is Dictionary and not (attach as Dictionary).empty():
		var url = str(attach.get("url", ""))
		_render_media(attach)
		var caption = Media.caption_of(str(rec.get("body", "")), url)
		_label.bbcode_text = _bbcode(caption, _emoji)
		_label.visible = caption != ""
	else:
		_clear_media()
		_label.visible = true
		_label.bbcode_text = _bbcode(str(rec.get("body", "")), _emoji)
	_fit_w = -1.0
	_fit()
	_style()
	_update_meta()

# --- Media del adjunto ---

# Muestra la cita del mensaje respondido (XEP-0461/0428).
func _render_reply() -> void:
	if _reply_box == null:
		return
	var quote = str(rec.get("reply_quote", ""))
	if quote == "":
		_reply_box.visible = false
		return
	_reply_quote.text = quote.replace("\n", " ")
	_reply_box.visible = true

# Chips de reacciones (XEP-0444): emoji + total.
func _render_reactions() -> void:
	if _reactions_row == null:
		return
	for c in _reactions_row.get_children():
		_reactions_row.remove_child(c)
		c.queue_free()
	var rs = rec.get("reactions", [])
	if not (rs is Array) or rs.empty():
		_reactions_row.visible = false
		return
	# Cuenta por emoji (el modelo puede repetir de varias personas).
	var counts := {}
	for e in rs:
		counts[str(e)] = int(counts.get(str(e), 0)) + 1
	for e in counts.keys():
		var chip = Label.new()
		chip.text = str(e) if counts[e] == 1 else "%s %d" % [e, counts[e]]
		chip.add_color_override("font_color", Palette.TEXT)
		chip.add_stylebox_override("normal", XatTheme.box(Palette.BG2, 10, 6, 2))
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_reactions_row.add_child(chip)
	_reactions_row.visible = true

func _clear_media() -> void:
	if _media_host == null:
		return
	for c in _media_host.get_children():
		_media_host.remove_child(c)
		c.queue_free()

func _render_media(attach: Dictionary) -> void:
	_clear_media()
	var state = str(attach.get("state", ""))
	var name = Media.short_name(str(attach.get("name", "adjunto")))
	var size = int(attach.get("size", 0))
	if state == "uploading":
		_media_host.add_child(_media_label("Subiendo %s…" % name, Palette.TEXT_DIM))
		return
	if state == "failed":
		var reason = str(attach.get("error", ""))
		if reason == "":
			reason = "No se pudo enviar" if rec.get("direction", "in") == "out" else "No se pudo descargar"
		_media_host.add_child(_media_label(reason, Palette.ERROR))
		return
	var local = str(attach.get("local", ""))
	var has_local = local != "" and File.new().file_exists(local)
	match str(attach.get("kind", "file")):
		"image":
			_add_image(local if has_local else "", name)
		"audio":
			_add_audio(local if has_local else "", name, size, int(attach.get("duration_ms", 0)))
		_:
			_add_file(has_local, name, size)

func _add_image(p_local: String, p_name: String) -> void:
	if p_local == "":
		var b = _media_button(p_name + "  ·  tocar para ver", Palette.BG2)
		b.connect("pressed", self, "_emit_media", ["open"])
		_media_host.add_child(b)
		return
	var tex = null
	if p_local == _thumb_path and _thumb_tex != null:
		tex = _thumb_tex
	else:
		tex = MediaUtil.load_thumbnail(p_local, THUMB_MAX)
		if tex != null:
			_thumb_path = p_local
			_thumb_tex = tex
	if tex == null:
		_media_host.add_child(_media_label(p_name, Palette.TEXT))
		return
	var tr = TextureRect.new()
	tr.texture = tex
	tr.expand = true
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.rect_min_size = _thumb_size(tex)
	tr.mouse_filter = Control.MOUSE_FILTER_STOP
	tr.hint_tooltip = "Tocar para ampliar"
	tr.connect("gui_input", self, "_on_image_input")
	_media_host.add_child(tr)

func _add_audio(p_local: String, p_name: String, p_size: int, p_duration_ms: int) -> void:
	# Reproductor embebido: botón play/pausa + barra de progreso + duración. Antes
	# era un botón "▶" plano, sin estado ni avance visible.
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	_audio_btn = IconButton.new()
	_audio_btn.setup("play", 36, Palette.TEXT, "Reproducir")
	_audio_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_audio_btn.connect("pressed", self, "_on_audio_press")
	row.add_child(_audio_btn)
	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_constant_override("separation", 2)
	_audio_wave = AudioWave.new()
	_audio_wave.rect_min_size = Vector2(120, 18)
	_audio_wave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_audio_wave)
	var info := p_name
	if p_duration_ms > 0:
		info = Media.format_duration_ms(p_duration_ms)
	if p_size > 0:
		info += " · " + Media.format_size(p_size)
	elif p_local == "":
		info += " · tocar para oír"
	_audio_info = _media_label(info, Palette.TEXT_DIM)
	col.add_child(_audio_info)
	row.add_child(col)
	_media_host.add_child(row)

# El botón alterna reproducir/pausar según el estado del player global.
func _on_audio_press() -> void:
	_emit_media("pause" if _audio_active else "play")

# Estado del player global aplicado a esta burbuja (acción solicitada).
func set_audio_active(p_active: bool) -> void:
	_audio_active = p_active
	if _audio_btn != null:
		_audio_btn.set_glyph("pause" if p_active else "play")
		_audio_btn.hint_tooltip = "Pausar" if p_active else "Reproducir"

# Progreso en vivo (0..1); mueve el marcador del waveform.
func set_audio_progress(p_frac: float) -> void:
	if _audio_wave != null:
		_audio_wave.set_progress(clamp(p_frac, 0.0, 1.0))

func _add_file(p_has_local: bool, p_name: String, p_size: int) -> void:
	var txt = p_name
	if p_size > 0:
		txt += " (" + Media.format_size(p_size) + ")"
	if not p_has_local:
		txt += " · descargar"
	var b = _media_button(txt, Palette.BG2)
	b.connect("pressed", self, "_emit_media", ["open"])
	_media_host.add_child(b)

func _media_label(p_text: String, p_color: Color) -> Label:
	var l = Label.new()
	l.text = p_text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_color_override("font_color", p_color)
	l.add_font_override("font", XatTheme.font(Palette.FONT_REGULAR, Palette.FONT_SIZE - 1))
	l.clip_text = true
	return l

func _media_button(p_text: String, p_bg: Color) -> Button:
	var b = Button.new()
	b.text = p_text
	b.focus_mode = Control.FOCUS_NONE
	b.align = Button.ALIGN_LEFT
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_stylebox_override(st, XatTheme.box(p_bg.lightened(0.1) if st == "hover" else p_bg, Palette.RADIUS_SMALL, 8, 6))
	b.add_font_override("font", XatTheme.font(Palette.FONT_REGULAR, Palette.FONT_SIZE - 2))
	return b

func _thumb_size(p_tex: Texture) -> Vector2:
	var w = float(p_tex.get_width())
	var h = float(p_tex.get_height())
	if w <= 0.0 or h <= 0.0:
		return Vector2(120, 120)
	var scale = min(1.0, float(THUMB_MAX) / max(w, h))
	return Vector2(max(60.0, w * scale), max(60.0, h * scale))

func _on_image_input(p_ev: InputEvent) -> void:
	if p_ev is InputEventMouseButton and p_ev.pressed and p_ev.button_index == BUTTON_LEFT:
		accept_event()
		_emit_media("open")

func _emit_media(p_action: String) -> void:
	emit_signal("media_action", rec, p_action)

# Cuelga un nodo (card de aprobación) justo bajo la burbuja.
func attach(p_node: Control) -> void:
	var m = MarginContainer.new()
	m.add_constant_override("margin_top", 6)
	m.mouse_filter = Control.MOUSE_FILTER_PASS
	m.add_child(p_node)
	add_child(m)

func _style() -> void:
	var out = rec.get("direction", "in") == "out"
	var s = XatTheme.box(Palette.USER if out else Palette.BG2, Palette.RADIUS, 12, 8)
	if not out:
		XatTheme.with_border(s, Color(Palette.AGENT_EDGE.r, Palette.AGENT_EDGE.g, Palette.AGENT_EDGE.b, 0.35))
	if _search_hl:
		# Resalta la burbuja durante la búsqueda.
		s.set_border_width_all(2)
		s.border_color = Palette.PENDING
	if _last:
		if out:
			s.corner_radius_bottom_right = Palette.RADIUS_SMALL
		else:
			s.corner_radius_bottom_left = Palette.RADIUS_SMALL
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 2)
	_panel.add_stylebox_override("panel", s)

func _update_meta() -> void:
	var t = _short_time(LocalTime.local_iso(str(rec.get("timestamp", ""))))
	var parts := []
	if t != "":
		parts.append(t)
	if rec.get("edited", false):
		parts.append("editado")
	var txt = " · ".join(parts)
	var out = rec.get("direction", "in") == "out"
	_meta.text = txt
	_ticks.visible = out
	_ticks.rect_min_size = Vector2(20 if rec.get("delivered", false) else 12, 10)
	_ticks.update()
	_metarow.visible = _last and (txt != "" or out)

func _draw_ticks() -> void:
	var col = Palette.AGENT_EDGE if rec.get("delivered", false) else Palette.TEXT_DIM
	for k in range(2 if rec.get("delivered", false) else 1):
		var o = Vector2(k * 7, 0)
		_ticks.draw_polyline(PoolVector2Array([Vector2(1, 6) + o, Vector2(4, 9) + o, Vector2(10, 2) + o]), col, 1.5, true)

static func _short_time(p_iso: String) -> String:
	return p_iso.substr(11, 5) if p_iso.length() >= 16 else ""

# Ancho del texto: lo que mide la línea más larga, tope 70% de la fila.
func _fit() -> void:
	var max_w = rect_size.x * MAX_FRAC - 24.0
	if max_w <= 40.0:
		return
	var body = str(rec.get("body", ""))
	var attach = rec.get("attach", {})
	if attach is Dictionary and not (attach as Dictionary).empty():
		body = Media.caption_of(body, str(attach.get("url", "")))
	var w := 0.0
	# El zoom cambia métricas y tamaño de imágenes, además de los glifos Slug.
	if _emoji != null and _emoji.size != int(_font.get_height()):
		_emoji = EmojiInline.new(int(_font.get_height()))
		_label.bbcode_text = _bbcode(body, _emoji)
	for line in body.split("\n"):
		var line_w = _emoji.line_width(line, _font) if _emoji != null else _font.get_string_size(line).x
		w = max(w, line_w * 1.06)
	if body == "":
		return
	w = clamp(w + 2.0, 24.0, max_w)
	if abs(w - _fit_w) > 0.5:
		_fit_w = w
		_label.rect_min_size.x = w

# Entrada: fade + deslizamiento vertical (vía el espaciador, el contenedor
# manda sobre la posición del hijo).
func _animate() -> void:
	_play = false
	_anim(0.0)
	_tween = Tween.new()
	add_child(_tween)
	_tween.interpolate_method(self, "_anim", 0.0, 1.0, 0.22, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	_tween.start()

func _anim(p_t: float) -> void:
	modulate.a = p_t
	_spacer.rect_min_size.y = _gap + (1.0 - p_t) * SLIDE
