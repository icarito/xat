extends PanelContainer

# Diálogo de cuenta. Panel de conexión con validación-before-persist: emite la
# configuración y muestra el estado; no guarda credenciales por sí sola.

signal connect_requested(cfg)
signal register_requested(cfg)

const XatXmpp = preload("res://addons/xat_xmpp/xat_xmpp.gd")

var _jid: LineEdit
var _pass: LineEdit
var _host: LineEdit
var _port: LineEdit
var _cafile: LineEdit
var _email: LineEdit
var _status: Label
var _button: Button
var _register_btn: Button

func _init() -> void:
	name = "AccountPanel"
	_build()

func _build() -> void:
	var margin = MarginContainer.new()
	margin.set("custom_constants/margin_left", 24)
	margin.set("custom_constants/margin_right", 24)
	margin.set("custom_constants/margin_top", 18)
	margin.add_child(_make_form())
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
