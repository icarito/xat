extends Node

# Zoom global (Ctrl+scroll / Ctrl++ / Ctrl+- como un navegador).
# Los DynamicFont que crea XatTheme.font() se registran aquí para poder
# redimensionarlos en caliente; el factor se persiste en xat_settings.json.
#
# El zoom es PROPORCIONAL: además de los glifos reescala la geometría
# (rect_min_size, separations, paddings de StyleBox) vía UiScale, aplicado
# sobre el árbol vivo en cada cambio. Las fuentes creadas fuera de XatTheme
# (p. ej. mind_panel) también deben registrarse aquí.

signal scale_changed(scale)

const UiScale = preload("res://addons/xat_xmpp/ui/ui_scale.gd")

const DEFAULT := 1.0
const MIN := 0.7
const MAX := 2.4
const STEP := 0.1

var scale := DEFAULT

var _fonts := [] # [[WeakRef(DynamicFont), tamaño_base]]

# Registra una fuente y la ajusta al factor actual. Guarda el tamaño base para
# poder reescalarla después sin perder el diseño original.
func register(p_font: DynamicFont, p_base: int) -> void:
	_prune()
	p_font.size = _size(p_base)
	_fonts.append([weakref(p_font), p_base])

func zoom_in() -> void:
	set_scale(scale + STEP)

func zoom_out() -> void:
	set_scale(scale - STEP)

func reset() -> void:
	set_scale(DEFAULT)

func set_scale(p_scale: float) -> void:
	var s = clamp(p_scale, MIN, MAX)
	if is_equal_approx(s, scale):
		return
	scale = s
	_prune()
	for e in _fonts:
		var f = e[0].get_ref()
		if f != null:
			f.size = _size(e[1])
	# Geometría proporcional: reescala el árbol visible desde la base capturada.
	apply_geometry()
	emit_signal("scale_changed", scale)

# Re-escala la geometría de todo el árbol (idempotente: el helper guarda bases).
func apply_geometry() -> void:
	var loop = Engine.get_main_loop()
	if loop is SceneTree:
		var root = loop.get_root()
		if root != null:
			UiScale.apply(root, scale)

# Escala un subárbol recién (re)construido (filas, burbujas, etiquetas). Los
# nodos nuevos no tenían base capturada: el helper la fija y aplica el factor.
func settle(p_node: Node) -> void:
	if p_node != null:
		UiScale.apply(p_node, scale)

func _size(p_base: int) -> int:
	return int(max(1, int(round(p_base * scale))))

func _prune() -> void:
	var keep := []
	for e in _fonts:
		if e[0].get_ref() != null:
			keep.append(e)
	_fonts = keep
