extends Control

# Visor de imagen a pantalla completa (lightbox). Un clic o Escape cierra.

signal closed()

const MediaUtil = preload("res://addons/xat_xmpp/ui/media_util.gd")

var _tex: TextureRect
var _bg: ColorRect

func _init() -> void:
	visible = false
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0, 0.9)
	_bg.anchor_right = 1.0
	_bg.anchor_bottom = 1.0
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)
	_tex = TextureRect.new()
	_tex.expand = true
	_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tex.anchor_right = 1.0
	_tex.anchor_bottom = 1.0
	_tex.margin_left = 24
	_tex.margin_top = 24
	_tex.margin_right = -24
	_tex.margin_bottom = 24
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tex)
	var hint = Label.new()
	hint.text = "Tocá o Esc para cerrar"
	hint.anchor_left = 0.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.margin_left = 20
	hint.margin_top = -34
	hint.add_color_override("font_color", Color(1, 1, 1, 0.6))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	set_process_input(true)

func open(p_path: String) -> void:
	var tex = MediaUtil.load_texture(p_path)
	if tex == null:
		return
	_tex.texture = tex
	visible = true

func close() -> void:
	visible = false
	_tex.texture = null
	emit_signal("closed")

func _gui_input(p_ev: InputEvent) -> void:
	if p_ev is InputEventMouseButton and p_ev.pressed:
		close()
		accept_event()

func _input(p_ev: InputEvent) -> void:
	if visible and p_ev is InputEventKey and p_ev.pressed and not p_ev.echo and p_ev.scancode == KEY_ESCAPE:
		close()
		get_tree().set_input_as_handled()
