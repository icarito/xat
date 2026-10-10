extends Reference

# Escalado geométrico proporcional al zoom tipográfico (FontZoom).
#
# Problema que resuelve: FontZoom sólo agranda los glifos, pero los controles
# conservan rect_min_size, separations y paddings en píxeles de diseño. Con
# letra grande el texto se desborda de las cajas y las filas se montan.
#
# En vez de reescribir cada widget con `* scale`, este helper recorre el árbol
# y multiplica desde un valor BASE capturado la primera vez (metadata), de modo
# que aplicar el factor varias veces no acumula deriva.
#
# Escala:
#   - Control.rect_min_size           (metadata __ui_base_min)
#   - Stack/Box separations           (constants: separation/hseparation/vseparation)
#   - StyleBoxFlat content margins    (metadata __ui_base_box, por clase)
#   - Button/icon min sizes via Control (ya cubierto por rect_min_size)
#
# No escala posiciones de anclaje ni márgenes de layout (margin_*), que son
# responsabilidad de los contenedores; el tamaño lo gobiernan los min_sizes.

const META_MIN := "__ui_base_min"
const META_SEP := "__ui_base_sep"
const META_BOX := "__ui_base_box"

const SEP_KEYS := ["separation", "hseparation", "vseparation"]

# Aplica el factor sobre el subárbol p_root. Los nodos que ya tengan base
# capturada sólo se reescalan; los nuevos capturan su base al factor actual
# (por eso p_reset(true) fuerza recaptura con base = valor actual).
static func apply(p_root: Node, p_scale: float, p_reset: bool = false) -> void:
	if p_root == null:
		return
	# No escalar el Control raíz: su rect_min_size gobierna el tamaño mínimo de
	# la ventana, no contenido.
	for c in p_root.get_children():
		_walk(c, p_scale, p_reset)

static func _walk(p_node: Node, p_scale: float, p_reset: bool) -> void:
	if p_node is Control:
		_scale_control(p_node, p_scale, p_reset)
	if p_node is BoxContainer:
		_scale_box(p_node, p_scale, p_reset)
	for c in p_node.get_children():
		if c is Node:
			_walk(c, p_scale, p_reset)

static func _scale_control(p_node: Control, p_scale: float, p_reset: bool) -> void:
	# rect_min_size
	var base
	if p_reset or not p_node.has_meta(META_MIN):
		base = p_node.rect_min_size
		p_node.set_meta(META_MIN, base)
	else:
		base = p_node.get_meta(META_MIN)
	p_node.rect_min_size = Vector2(round(base.x * p_scale), round(base.y * p_scale))

	# StyleBoxFlat propio (overrides locales). Escala los content margins.
	for prop in ["custom_styles/normal", "custom_styles/hover", "custom_styles/pressed",
			"custom_styles/focus", "custom_styles/disabled", "custom_styles/panel",
			"custom_styles/bg", "custom_styles/read_only"]:
		if not p_node.has_stylebox_override(prop):
			continue
		var sb = p_node.get_stylebox(prop)
		if sb == null or not (sb is StyleBoxFlat):
			continue
		_scale_stylebox(sb, p_node, prop, p_scale, p_reset)

static func _scale_stylebox(p_sb: StyleBoxFlat, p_owner: Control, p_prop: String, p_scale: float, p_reset: bool) -> void:
	var key = META_BOX + "|" + p_prop
	var base
	if p_reset or not p_owner.has_meta(key):
		# Guarda los cuatro márgenes como Vector4-like en un Array.
		base = [p_sb.content_margin_left, p_sb.content_margin_top,
				p_sb.content_margin_right, p_sb.content_margin_bottom]
		p_owner.set_meta(key, base)
	else:
		base = p_owner.get_meta(key)
	p_sb.content_margin_left = round(base[0] * p_scale)
	p_sb.content_margin_top = round(base[1] * p_scale)
	p_sb.content_margin_right = round(base[2] * p_scale)
	p_sb.content_margin_bottom = round(base[3] * p_scale)

static func _scale_box(p_node: BoxContainer, p_scale: float, p_reset: bool) -> void:
	for k in SEP_KEYS:
		if not p_node.has_constant_override(k):
			continue
		var key = META_SEP + "|" + k
		var base
		if p_reset or not p_node.has_meta(key):
			base = p_node.get_constant(k)
			p_node.set_meta(key, base)
		else:
			base = p_node.get_meta(key)
		p_node.add_constant_override(k, int(round(base * p_scale)))