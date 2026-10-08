extends VBoxContainer

# Burbuja de chat: fila con la burbuja alineada a un lado, hora/estado debajo
# (sólo en la última del grupo). Sin _process; la entrada usa un Tween.

const LocalTime = preload("res://addons/xat_xmpp/ui/localtime.gd")
const Palette = preload("res://addons/xat_xmpp/ui/palette.gd")
const Markdown = preload("res://addons/xat_xmpp/xmpp/markdown.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")
const EmojiInline = preload("res://addons/xat_xmpp/ui/emoji_inline.gd")

const MAX_FRAC := 0.7
const SLIDE := 14.0

var rec := {}
var _last := false
var _gap := Palette.GAP
var _play := false
var _spacer: Control
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
	# En táctil el arrastre debe desplazar el chat, no seleccionar texto.
	_label.selection_enabled = not OS.has_touchscreen_ui_hint()
	_label.add_color_override("default_color", Palette.TEXT)
	_label.add_font_override("normal_font", _font)
	_label.add_font_override("bold_font", XatTheme.font(Palette.FONT_BOLD))
	_label.add_font_override("italics_font", _font)
	_label.add_font_override("bold_italics_font", XatTheme.font(Palette.FONT_BOLD))
	_label.add_font_override("mono_font", XatTheme.font(Palette.FONT_MONO, Palette.FONT_SIZE - 1))
	_panel.add_child(_label)
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
	col.add_child(_panel)
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

func deselect() -> void:
	_label.deselect()

# Re-renderiza cuerpo, marcas y estilo (corrección, entrega).
func refresh() -> void:
	# Un motor anterior sigue mostrando Unicode normal. No sustituir por imágenes
	# si no sabe devolver su secuencia original al seleccionar/copiar.
	_emoji = EmojiInline.new(int(_font.get_height())) if _label.has_method("add_inline_image") else null
	var bb = Markdown.to_bbcode(str(rec.get("body", "")), _emoji)
	_label.bbcode_text = bb
	_fit_w = -1.0
	_fit()
	_style()
	_update_meta()

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
	var w := 0.0
	# El zoom cambia métricas y tamaño de imágenes, además de los glifos Slug.
	if _emoji != null and _emoji.size != int(_font.get_height()):
		_emoji = EmojiInline.new(int(_font.get_height()))
		_label.bbcode_text = Markdown.to_bbcode(str(rec.get("body", "")), _emoji)
	for line in str(rec.get("body", "")).split("\n"):
		var line_w = _emoji.line_width(line, _font) if _emoji != null else _font.get_string_size(line).x
		w = max(w, line_w * 1.06)
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
