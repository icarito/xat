extends Reference

# Tema oscuro de xat construido desde palette.gd. Se aplica en la raíz
# (theme = XatTheme.build()) y lo heredan todos los Control.

const Palette = preload("res://addons/xat_xmpp/ui/palette.gd")

const SCRIPT_PATH := "res://addons/xat_xmpp/ui/xat_theme.gd"
const FONT_CACHE_KEY := "xat_font_cache_v1"

# Fuente memoizada por (path, tamaño). Antes se creaba una DynamicFont nueva en
# cada llamada (7 por burbuja, y una por fila de roster/card): cada rebind de
# historial reasignaba decenas de fuentes. Compartir el recurso es seguro (los
# overrides son por Control) y el FontZoom la reescala una sola vez.
static func font(p_path: String, p_size: int = Palette.FONT_SIZE) -> DynamicFont:
	var cache := _font_cache()
	var key = p_path + "|" + str(p_size)
	if cache.has(key):
		return cache[key]
	var f = DynamicFont.new()
	f.font_data = load(p_path)
	f.add_fallback(load(Palette.FONT_FALLBACK))
	f.size = p_size
	f.use_filter = true
	# El zoom global (FontZoom) reescala en caliente todas las fuentes creadas.
	var fz = _font_zoom()
	if fz != null:
		fz.register(f, p_size)
	cache[key] = f
	return f

static func _font_cache() -> Dictionary:
	var script = load(SCRIPT_PATH)
	if not script.has_meta(FONT_CACHE_KEY):
		script.set_meta(FONT_CACHE_KEY, {})
	return script.get_meta(FONT_CACHE_KEY)

# Acceso suave al singleton global (null si no está instalado, p. ej. tests).
static func _font_zoom():
	var loop = Engine.get_main_loop()
	if loop is SceneTree:
		var root = loop.get_root()
		if root != null:
			return root.get_node_or_null("FontZoom")
	return null

static func box(p_bg: Color, p_radius: int = Palette.RADIUS, p_mx: int = 12, p_my: int = 8) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = p_bg
	s.set_corner_radius_all(p_radius)
	s.set_border_width_all(0)
	s.content_margin_left = p_mx
	s.content_margin_right = p_mx
	s.content_margin_top = p_my
	s.content_margin_bottom = p_my
	s.anti_aliasing = true
	return s

static func with_border(p_box: StyleBoxFlat, p_color: Color, p_w: int = 1) -> StyleBoxFlat:
	p_box.border_color = p_color
	p_box.set_border_width_all(p_w)
	return p_box

static func build() -> Theme:
	var t = Theme.new()
	var regular = font(Palette.FONT_REGULAR)
	t.default_font = regular

	var empty = StyleBoxEmpty.new()
	t.set_stylebox("panel", "PanelContainer", box(Palette.BG1, 0, 0, 0))
	t.set_stylebox("panel", "Panel", box(Palette.BG1, 0, 0, 0))

	t.set_color("font_color", "Label", Palette.TEXT)

	# Botones.
	t.set_stylebox("normal", "Button", box(Palette.BG2, Palette.RADIUS, 14, 8))
	t.set_stylebox("hover", "Button", with_border(box(Palette.LINE, Palette.RADIUS, 14, 8), Palette.AGENT_EDGE))
	t.set_stylebox("pressed", "Button", box(Palette.USER, Palette.RADIUS, 14, 8))
	t.set_stylebox("focus", "Button", with_border(box(Color(0, 0, 0, 0), Palette.RADIUS, 14, 8), Palette.AGENT_EDGE))
	t.set_stylebox("disabled", "Button", box(Palette.BG1, Palette.RADIUS, 14, 8))
	for c in ["font_color", "font_color_hover", "font_color_pressed"]:
		t.set_color(c, "Button", Palette.TEXT)
	t.set_color("font_color_disabled", "Button", Palette.TEXT_DIM)

	# Campos de texto.
	for cls in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", cls, with_border(box(Palette.BG2, Palette.RADIUS, 14, 10), Palette.LINE))
		t.set_stylebox("focus", cls, with_border(box(Palette.BG2, Palette.RADIUS, 14, 10), Palette.AGENT_EDGE))
		t.set_color("font_color", cls, Palette.TEXT)
		t.set_color("caret_color", cls, Palette.AGENT_EDGE)
		t.set_color("selection_color", cls, Color(Palette.USER.r, Palette.USER.g, Palette.USER.b, 0.6))
	t.set_stylebox("read_only", "LineEdit", box(Palette.BG1, Palette.RADIUS, 14, 10))
	t.set_color("font_color_uneditable", "LineEdit", Palette.TEXT_DIM)
	t.set_color("font_color_selected", "LineEdit", Palette.TEXT)
	t.set_color("font_color_selected", "TextEdit", Palette.TEXT)
	t.set_color("font_color_readonly", "TextEdit", Palette.TEXT_DIM)

	# Scroll delgado.
	var grab = box(Palette.LINE, 3, 0, 0)
	var grab_hi = box(Palette.TEXT_DIM, 3, 0, 0)
	for cls in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", cls, box(Color(0, 0, 0, 0), 3, 0, 0))
		t.set_stylebox("scroll_focus", cls, box(Color(0, 0, 0, 0), 3, 0, 0))
		t.set_stylebox("grabber", cls, grab)
		t.set_stylebox("grabber_highlight", cls, grab_hi)
		t.set_stylebox("grabber_pressed", cls, grab_hi)
	t.set_icon("increment", "VScrollBar", ImageTexture.new())
	t.set_icon("decrement", "VScrollBar", ImageTexture.new())
	t.set_icon("increment_highlight", "VScrollBar", ImageTexture.new())
	t.set_icon("decrement_highlight", "VScrollBar", ImageTexture.new())
	t.set_icon("increment", "HScrollBar", ImageTexture.new())
	t.set_icon("decrement", "HScrollBar", ImageTexture.new())
	t.set_icon("increment_highlight", "HScrollBar", ImageTexture.new())
	t.set_icon("decrement_highlight", "HScrollBar", ImageTexture.new())
	t.set_constant("scrollbar_separation", "ScrollContainer", 0)

	# Popups y diálogos.
	t.set_stylebox("panel", "PopupMenu", with_border(box(Palette.BG2, 8, 4, 4), Palette.LINE))
	t.set_stylebox("hover", "PopupMenu", box(Palette.LINE, 6, 6, 4))
	t.set_color("font_color", "PopupMenu", Palette.TEXT)
	t.set_color("font_color_hover", "PopupMenu", Palette.TEXT)
	t.set_stylebox("panel", "WindowDialog", with_border(box(Palette.BG1, Palette.RADIUS, 12, 12), Palette.LINE))
	t.set_color("title_color", "WindowDialog", Palette.TEXT)
	t.set_font("title_font", "WindowDialog", font(Palette.FONT_MEDIUM))
	t.set_stylebox("panel", "AcceptDialog", with_border(box(Palette.BG1, Palette.RADIUS, 12, 12), Palette.LINE))
	t.set_stylebox("panel", "PopupPanel", with_border(box(Palette.BG1, 8, 8, 8), Palette.LINE))
	return t
