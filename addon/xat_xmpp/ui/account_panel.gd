extends PanelContainer

# Diálogo de cuenta. Panel de conexión con validación-before-persist: emite la
# configuración y muestra el estado; no guarda credenciales por sí sola.

signal connect_requested(cfg)

var _jid: LineEdit
var _pass: LineEdit
var _host: LineEdit
var _port: LineEdit
var _cafile: LineEdit
var _status: Label
var _button: Button

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
	v.add_child(HSeparator.new())
	_button = Button.new()
	_button.text = "Conectar"
	_button.connect("pressed", self, "_on_connect")
	v.add_child(_button)
	_status = Label.new()
	_status.autowrap = true
	v.add_child(_status)
	return v

func _title() -> Label:
	var l = Label.new()
	l.text = "xat — conectar"
	l.align = Label.ALIGN_CENTER
	return l

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
	}

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
