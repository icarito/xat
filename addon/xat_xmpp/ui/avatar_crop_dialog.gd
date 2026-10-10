extends AcceptDialog

# Recorte de la foto de perfil: muestra la imagen con ajuste "contain" y deja
# mover un cuadrado de selección; al confirmar recorta esa porción (mapeada a
# píxeles de la imagen original) y emite `cropped(path)` con un PNG temporal.

signal cropped(path)

const Avatar = preload("res://addons/xat_xmpp/xmpp/avatar.gd")
const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")

const MAX_DISPLAY := 1024

var _path := ""
var _img_size := Vector2.ZERO
var _view: Control
var _tex: TextureRect
var _sel: Control
var _drag := false

func _init() -> void:
	name = "AvatarCropDialog"
	window_title = "Recortar foto"
	rect_min_size = Vector2(560, 560)
	var margin = MarginContainer.new()
	margin.add_constant_override("margin_left", 18)
	margin.add_constant_override("margin_right", 18)
	margin.add_constant_override("margin_top", 16)
	margin.add_constant_override("margin_bottom", 16)
	add_child(margin)
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 12)
	margin.add_child(box)
	var title = Label.new()
	title.text = "Elegí qué parte de la foto se verá como avatar."
	title.autowrap = true
	title.add_color_override("font_color", P.TEXT_DIM)
	box.add_child(title)
	_view = Control.new()
	_view.rect_min_size = Vector2(500, 420)
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.connect("draw", self, "_draw_dim")
	_view.connect("resized", self, "_layout")
	box.add_child(_view)
	_tex = TextureRect.new()
	_tex.expand = true
	_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tex.anchor_right = 1.0
	_tex.anchor_bottom = 1.0
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(_tex)
	_sel = Control.new()
	_sel.mouse_filter = Control.MOUSE_FILTER_STOP
	_sel.connect("gui_input", self, "_on_sel_input")
	_sel.connect("draw", self, "_draw_sel")
	_view.add_child(_sel)
	connect("confirmed", self, "_on_ok")
	get_ok().text = "Usar"
	get_ok().disabled = true

func open(p_path: String) -> void:
	_path = p_path
	_drag = false
	var img = Image.new()
	if img.load(p_path) != OK:
		_img_size = Vector2.ZERO
		get_ok().disabled = true
		popup_centered(Vector2(560, 560))
		return
	_img_size = Vector2(img.get_width(), img.get_height())
	# Copia reducida sólo para mostrar; el recorte se calcula sobre el tamaño real.
	if max(_img_size.x, _img_size.y) > MAX_DISPLAY:
		var s = float(MAX_DISPLAY) / max(_img_size.x, _img_size.y)
		img.resize(int(_img_size.x * s), int(_img_size.y * s), Image.INTERPOLATE_BILINEAR)
	var tx = ImageTexture.new()
	tx.create_from_image(img, 0)
	_tex.texture = tx
	get_ok().disabled = _img_size == Vector2.ZERO
	popup_centered(Vector2(560, 560))
	_layout()

# Escala "contain" + centrado: la misma cuenta que Avatar.map_view_rect.
func _disp() -> Dictionary:
	var view = _view.rect_size
	if _img_size == Vector2.ZERO or view.x <= 0.0 or view.y <= 0.0:
		return {"scale": 0.0, "off": Vector2.ZERO, "disp": Vector2.ZERO}
	var scale = min(view.x / _img_size.x, view.y / _img_size.y)
	var disp = _img_size * scale
	return {"scale": scale, "off": (view - disp) * 0.5, "disp": disp}

func _layout() -> void:
	if _img_size == Vector2.ZERO or _sel == null:
		return
	var d = _disp()
	if d["scale"] <= 0.0:
		return
	var disp = d["disp"]
	var side = min(disp.x, disp.y) * 0.7
	_sel.rect_size = Vector2(side, side)
	_sel.rect_position = d["off"] + (disp - Vector2(side, side)) * 0.5
	_view.update()

func _on_sel_input(p_ev: InputEvent) -> void:
	if p_ev is InputEventMouseButton and p_ev.button_index == BUTTON_LEFT:
		_drag = p_ev.pressed
		accept_event()
	elif p_ev is InputEventMouseMotion and _drag:
		_move_by(p_ev.relative)
		accept_event()

func _move_by(p_delta: Vector2) -> void:
	var d = _disp()
	var disp = d["disp"]
	var side = _sel.rect_size
	var lo = d["off"]
	var hi = d["off"] + disp - side
	_sel.rect_position = Vector2(
		clamp(_sel.rect_position.x + p_delta.x, lo.x, max(lo.x, hi.x)),
		clamp(_sel.rect_position.y + p_delta.y, lo.y, max(lo.y, hi.y)))
	_view.update()

func _draw_dim() -> void:
	var r = Rect2(_sel.rect_position, _sel.rect_size)
	var v = _view.rect_size
	var dim = Color(0, 0, 0, 0.55)
	_view.draw_rect(Rect2(0, 0, v.x, r.position.y), dim)
	_view.draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), dim)
	_view.draw_rect(Rect2(r.position.x + r.size.x, r.position.y, v.x - (r.position.x + r.size.x), r.size.y), dim)
	_view.draw_rect(Rect2(0, r.position.y + r.size.y, v.x, v.y - (r.position.y + r.size.y)), dim)

func _draw_sel() -> void:
	_sel.draw_rect(Rect2(Vector2.ZERO, _sel.rect_size), P.USER, false, 2.0)

func _on_ok() -> void:
	if _img_size == Vector2.ZERO or _path == "":
		return
	var rect_view = Rect2(_sel.rect_position, _sel.rect_size)
	var img_rect = Avatar.map_view_rect(rect_view, _view.rect_size, _img_size)
	var a = Avatar.process_rect(_path, img_rect)
	if a.empty():
		return
	var out = "user://avatar_crop.png"
	if Avatar.save(out, a["bytes"]):
		emit_signal("cropped", out)
