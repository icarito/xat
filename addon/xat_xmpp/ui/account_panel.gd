extends PanelContainer

# Diálogo de cuenta. Panel de conexión con validación-before-persist: emite la
# configuración y muestra el estado; no guarda credenciales por sí sola.

signal connect_requested(cfg)
signal register_requested(cfg)
# Vista "Yo": reenvía a main el zoom y las acciones de cuenta.
signal font_scale_requested(dir)
signal avatar_requested()
signal updates_requested()

const XatXmpp = preload("res://addons/xat_xmpp/xat_xmpp.gd")
const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")

var _jid: LineEdit
var _pass: LineEdit
var _host: LineEdit
var _port: LineEdit
var _cafile: LineEdit
var _email: LineEdit
var _status: Label
var _button: Button
var _register_btn: Button
# "Yo" (ajustes de la cuenta): mismos valores de user://xat_settings.json.
var _juice = null
var _yo_sound: Button
var _yo_haptic: Button
var _yo_motion: Button
var _font_label: Label

func _init() -> void:
	name = "AccountPanel"
	_build()

func _build() -> void:
	var margin = MarginContainer.new()
	margin.set("custom_constants/margin_left", 24)
	margin.set("custom_constants/margin_right", 24)
	margin.set("custom_constants/margin_top", 18)
	# La vista "Yo" agrega los ajustes debajo del formulario: con pantallas
	# bajas (compacto) el contenido puede superar el alto, así que scrollea.
	var sc = ScrollContainer.new()
	sc.scroll_horizontal_enabled = false
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(sc)
	var form = _make_form()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(form)
	add_child(margin)

func _make_form() -> VBoxContainer:
	var v = VBoxContainer.new()
	v.add_child(_title())
	_jid = _row(v, "JID", "agente@hablar.fuentelibre.org")
	_pass = _row(v, "Contraseña", "")
	_pass.secret = true
	_host = _row(v, "Servidor", "hablar.fuentelibre.org")
	_port = _row(v, "Puerto", "5222")
	_cafile = _row(v, "CA (opcional)", "/etc/ssl/certs/ca-certificates.crt")
	# Registro en banda (XEP-0077): sólo se muestra si el servidor lo ofrece.
	_email = _row(v, "Correo (registro)", "")
	_email.visible = true
	v.add_child(HSeparator.new())
	_button = Button.new()
	_button.text = "Conectar"
	_button.connect("pressed", self, "_on_connect")
	v.add_child(_button)
	_register_btn = Button.new()
	_register_btn.text = "Crear cuenta nueva"
	_register_btn.visible = true
	_register_btn.connect("pressed", self, "_on_register")
	v.add_child(_register_btn)
	_status = Label.new()
	_status.autowrap = true
	v.add_child(_status)
	v.add_child(_legal_links())
	v.add_child(HSeparator.new())
	v.add_child(_make_yo())
	return v

func _title() -> Label:
	var l = Label.new()
	l.text = "xat — conectar"
	l.align = Label.ALIGN_CENTER
	return l

func _legal_links() -> HBoxContainer:
	var h = HBoxContainer.new()
	h.alignment = BoxContainer.ALIGN_CENTER
	h.add_child(_link("Política de privacidad", XatXmpp.PRIVACY_URL))
	var sep = Label.new()
	sep.text = "  ·  "
	h.add_child(sep)
	h.add_child(_link("Soporte", XatXmpp.SUPPORT_URL))
	return h

func _link(p_text: String, p_url: String) -> LinkButton:
	var b = LinkButton.new()
	b.text = p_text
	b.focus_mode = Control.FOCUS_NONE
	b.connect("pressed", self, "_open_url", [p_url])
	return b

func _open_url(p_url: String) -> void:
	OS.shell_open(p_url)

func _row(p_parent: VBoxContainer, p_label: String, p_default: String) -> LineEdit:
	var h = HBoxContainer.new()
	var l = Label.new()
	l.text = p_label
	l.rect_min_size = Vector2(120, 0)
	h.add_child(l)
	var e = LineEdit.new()
	e.text = p_default
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(e)
	p_parent.add_child(h)
	return e

func set_status(p_text: String) -> void:
	_status.text = p_text

func set_busy(p_busy: bool) -> void:
	_button.disabled = p_busy
	if p_busy:
		set_status("Conectando…")

func config() -> Dictionary:
	return {
		"jid": _jid.text.strip_edges(),
		"pass": _pass.text,
		"host": _host.text.strip_edges(),
		"port": int(_port.text) if _port.text.is_valid_integer() else 5222,
		"cafile": _cafile.text.strip_edges(),
		"email": _email.text.strip_edges(),
	}

# Muestra u oculta la sección de registro en banda según el servidor la anuncie.
func set_register_supported(p_supported: bool) -> void:
	_email.visible = p_supported
	_register_btn.visible = p_supported

# Campos estándar de XEP-0077 derivados de lo que el usuario completó.
func registration_fields() -> Dictionary:
	var cfg = config()
	var jid: String = cfg["jid"]
	var at = jid.find("@")
	var username = jid.substr(0, at) if at > 0 else jid
	var fields = {"username": username, "password": cfg["pass"]}
	if str(cfg["email"]) != "":
		fields["email"] = cfg["email"]
	return fields

# Precarga desde una config guardada (no pisa la contraseña si viene vacía).
func prefill(p_cfg: Dictionary) -> void:
	if p_cfg.has("jid"):
		_jid.text = str(p_cfg["jid"])
	if p_cfg.has("host"):
		_host.text = str(p_cfg["host"])
	if p_cfg.has("port"):
		_port.text = str(p_cfg["port"])
	if p_cfg.has("cafile"):
		_cafile.text = str(p_cfg["cafile"])
	if p_cfg.has("password") and str(p_cfg["password"]) != "":
		_pass.text = str(p_cfg["password"])

func _on_connect() -> void:
	var cfg = config()
	if cfg["jid"] == "" or cfg["pass"] == "":
		set_status("JID y contraseña son obligatorios.")
		return
	set_status("")
	emit_signal("connect_requested", cfg)

func _on_register() -> void:
	var cfg = config()
	if cfg["jid"] == "" or cfg["pass"] == "":
		set_status("JID y contraseña son obligatorios para crear la cuenta.")
		return
	set_status("Creando cuenta…")
	emit_signal("register_requested", cfg)

# --- Vista "Yo": ajustes de la cuenta ---
# Sonido, vibración, animación y tamaño de letra viven acá (antes en el pie del
# roster / sidebar). Persisten en user://xat_settings.json vía juice.

func _make_yo() -> VBoxContainer:
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 8)
	var title = Label.new()
	title.text = "Yo"
	title.align = Label.ALIGN_CENTER
	title.add_color_override("font_color", P.TEXT)
	title.add_font_override("font", XatTheme.font(P.FONT_BOLD, P.FONT_SIZE + 2))
	v.add_child(title)
	_yo_sound = _setting_toggle("Sonido", "sound_enabled")
	v.add_child(_yo_sound)
	_yo_haptic = _setting_toggle("Vibración", "haptics_enabled")
	v.add_child(_yo_haptic)
	_yo_motion = _setting_toggle("Animación", "motion_enabled")
	v.add_child(_yo_motion)
	v.add_child(_font_row())
	v.add_child(HSeparator.new())
	v.add_child(_yo_action("Cambiar foto de perfil", "_on_yo_avatar"))
	v.add_child(_yo_action("Privacidad y soporte", "_on_yo_about"))
	v.add_child(_yo_action("Buscar actualizaciones", "_on_yo_updates"))
	return v

# Toggle grande (>=44 px) que escribe el ajuste y avisa con un toast.
func _setting_toggle(p_label: String, p_key: String) -> Button:
	var b = Button.new()
	b.text = p_label
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.align = Button.ALIGN_LEFT
	b.rect_min_size = Vector2(0, 48)
	b.add_stylebox_override("normal", XatTheme.box(P.BG2, 10, 14, 8))
	b.add_stylebox_override("hover", XatTheme.box(P.BG2.lightened(0.12), 10, 14, 8))
	b.add_stylebox_override("pressed", XatTheme.box(P.USER.darkened(0.45), 10, 14, 8))
	b.add_stylebox_override("focus", XatTheme.box(P.BG2, 10, 14, 8))
	b.connect("toggled", self, "_on_setting_toggled", [p_key])
	return b

func _font_row() -> HBoxContainer:
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 6)
	var l = Label.new()
	l.text = "Tamaño de letra"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.rect_min_size = Vector2(0, 48)
	l.valign = Label.VALIGN_CENTER
	h.add_child(l)
	var smaller = _square("A−", "Achicar la letra")
	smaller.connect("pressed", self, "_on_font_smaller")
	h.add_child(smaller)
	_font_label = Label.new()
	_font_label.align = Label.ALIGN_CENTER
	_font_label.valign = Label.VALIGN_CENTER
	_font_label.rect_min_size = Vector2(56, 48)
	h.add_child(_font_label)
	var bigger = _square("A+", "Agrandar la letra")
	bigger.connect("pressed", self, "_on_font_bigger")
	h.add_child(bigger)
	return h

func _square(p_text: String, p_tip: String) -> Button:
	var b = Button.new()
	b.text = p_text
	b.hint_tooltip = p_tip
	b.focus_mode = Control.FOCUS_NONE
	b.rect_min_size = Vector2(52, 48)
	b.add_stylebox_override("normal", XatTheme.box(P.BG2, 10, 8, 8))
	b.add_stylebox_override("hover", XatTheme.box(P.BG2.lightened(0.12), 10, 8, 8))
	b.add_stylebox_override("pressed", XatTheme.box(P.USER.darkened(0.45), 10, 8, 8))
	b.add_stylebox_override("focus", XatTheme.box(P.BG2, 10, 8, 8))
	return b

func _yo_action(p_label: String, p_method: String) -> Button:
	var b = Button.new()
	b.text = p_label
	b.focus_mode = Control.FOCUS_NONE
	b.align = Button.ALIGN_LEFT
	b.rect_min_size = Vector2(0, 48)
	b.connect("pressed", self, p_method)
	return b

func _on_setting_toggled(p_on: bool, p_key: String) -> void:
	if _juice == null:
		return
	_juice.set_setting(p_key, p_on)
	var n = {"sound_enabled": "Sonido", "haptics_enabled": "Vibración", "motion_enabled": "Animación"}.get(p_key, "")
	if n != "":
		_juice.toast("%s %s" % [n, "activado" if p_on else "desactivado"])

# Conecta juice (ajustes) y sincroniza el estado de los toggles.
func set_juice(p_juice) -> void:
	_juice = p_juice
	for pair in [[_yo_sound, "sound_enabled"], [_yo_haptic, "haptics_enabled"], [_yo_motion, "motion_enabled"]]:
		if pair[0] != null and _juice != null:
			pair[0].pressed = bool(_juice.settings.get(pair[1], true))

# main llama acá tras aplicar el zoom para reflejar el % actual.
func set_font_label(p_scale: float) -> void:
	if _font_label != null:
		_font_label.text = "%d%%" % int(round(p_scale * 100.0))

func _on_font_smaller() -> void:
	emit_signal("font_scale_requested", -1)

func _on_font_bigger() -> void:
	emit_signal("font_scale_requested", 1)

func _on_yo_avatar() -> void:
	emit_signal("avatar_requested")

func _on_yo_updates() -> void:
	emit_signal("updates_requested")

func _on_yo_about() -> void:
	_open_url(XatXmpp.PRIVACY_URL)
