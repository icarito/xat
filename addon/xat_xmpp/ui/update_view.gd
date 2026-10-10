extends Control

# Vista integrada de actualizaciones: compara la versión instalada con el último
# GitHub Release de xat, muestra las notas y descarga/instala el APK (Android).

signal closed()

const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")

var _updater = null
var _version := ""
var _info := {}
var _status: Label
var _notes: RichTextLabel
var _size_l: Label
var _bar: ProgressBar
var _dl_btn: Button
var _open_btn: Button
var _check_btn: Button
var _card: PanelContainer

func _init() -> void:
	name = "UpdateView"
	anchor_right = 1.0
	anchor_bottom = 1.0
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center = CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = PanelContainer.new()
	_card.rect_min_size = Vector2(540, 0)
	_card.add_stylebox_override("panel", XatTheme.with_border(XatTheme.box(P.BG1, 14, 22, 20), P.LINE))
	center.add_child(_card)
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 12)
	_card.add_child(box)
	var title = Label.new()
	title.text = "Actualizaciones"
	title.add_font_override("font", XatTheme.font(P.FONT_BOLD, P.FONT_SIZE + 6))
	box.add_child(title)
	_status = Label.new()
	_status.autowrap = true
	_status.add_color_override("font_color", P.TEXT_DIM)
	box.add_child(_status)
	_notes = RichTextLabel.new()
	_notes.bbcode_enabled = true
	_notes.fit_content_height = false
	_notes.rect_min_size = Vector2(0, 190)
	_notes.scroll_active = true
	_notes.add_color_override("default_color", P.TEXT)
	box.add_child(_notes)
	_size_l = Label.new()
	_size_l.add_color_override("font_color", P.TEXT_DIM)
	box.add_child(_size_l)
	_bar = ProgressBar.new()
	_bar.min_value = 0
	_bar.max_value = 100
	_bar.value = 0
	_bar.visible = false
	_bar.rect_min_size = Vector2(0, 8)
	box.add_child(_bar)
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGN_END
	box.add_child(row)
	_check_btn = _button("Buscar de nuevo", P.BG2)
	_check_btn.connect("pressed", self, "_on_check")
	row.add_child(_check_btn)
	_open_btn = _button("Abrir en navegador", P.BG2)
	_open_btn.connect("pressed", self, "_on_open")
	row.add_child(_open_btn)
	_dl_btn = _button("Descargar e instalar", P.USER)
	_dl_btn.connect("pressed", self, "_on_download")
	row.add_child(_dl_btn)
	var close = _button("Cerrar", P.BG2)
	close.connect("pressed", self, "close")
	row.add_child(close)

func _button(p_text: String, p_bg: Color) -> Button:
	var b = Button.new()
	b.text = p_text
	b.focus_mode = Control.FOCUS_NONE
	b.add_stylebox_override("normal", XatTheme.box(p_bg, 10, 14, 8))
	b.add_stylebox_override("hover", XatTheme.box(p_bg.lightened(0.12), 10, 14, 8))
	b.add_stylebox_override("pressed", XatTheme.box(p_bg.darkened(0.1), 10, 14, 8))
	return b

func setup(p_updater, p_version: String) -> void:
	_updater = p_updater
	_version = p_version
	if _updater != null and not _updater.is_connected("update_available", self, "_on_available"):
		_updater.connect("update_available", self, "_on_available")
		_updater.connect("up_to_date", self, "_on_up_to_date")
		_updater.connect("check_failed", self, "_on_failed")
		_updater.connect("progress", self, "_on_progress")
		_updater.connect("downloaded", self, "_on_downloaded")
		_updater.connect("download_failed", self, "_on_dl_failed")

func open() -> void:
	visible = true
	_info = {}
	_notes.bbcode_text = ""
	_size_l.text = ""
	_bar.visible = false
	_dl_btn.disabled = true
	_open_btn.disabled = true
	if _updater == null:
		_status.text = "El updater no está disponible en esta plataforma."
		return
	_check_btn.disabled = true
	_status.text = "Versión instalada: %s\nBuscando actualizaciones…" % _version
	_updater.call("check", _version)

func close() -> void:
	visible = false
	emit_signal("closed")

func _on_check() -> void:
	open()

func _on_available(p_info: Dictionary) -> void:
	_info = p_info
	_check_btn.disabled = false
	var size_mb = float(p_info.get("size", 0)) / 1048576.0
	_status.text = "Versión instalada: %s\nNueva versión: %s" % [_version, p_info.get("version", "?")]
	_size_l.text = "%s · %.1f MB" % [p_info.get("name", ""), size_mb]
	var notes = str(p_info.get("notes", "")).strip_edges()
	if notes == "":
		notes = "_(sin notas de la versión)_"
	_notes.bbcode_text = notes
	_dl_btn.disabled = false
	_open_btn.disabled = false

func _on_up_to_date(p_version: String) -> void:
	_check_btn.disabled = false
	_status.text = "Versión instalada: %s\nEstás al día." % p_version

func _on_failed(p_reason: String) -> void:
	_check_btn.disabled = false
	_status.text = "Versión instalada: %s\nNo se pudo comprobar: %s" % [_version, p_reason]

func _on_download() -> void:
	if _updater == null:
		return
	_dl_btn.disabled = true
	_bar.visible = true
	_bar.value = 0
	_status.text = "Descargando…"
	_updater.call("download")

func _on_progress(p_done: int, p_total: int) -> void:
	if p_total > 0:
		_bar.value = int(100.0 * float(p_done) / float(p_total))
	else:
		_bar.value = 0

func _on_downloaded(p_path: String) -> void:
	_bar.value = 100
	if _updater != null and _updater.call("can_install"):
		_status.text = "Abriendo el instalador…"
		if not bool(_updater.call("install", p_path)):
			_status.text = "No se pudo abrir el instalador. Abrí el APK manualmente:\n%s" % p_path
	else:
		# Escritorio u otras plataformas: no hay instalador; abrir la descarga.
		_status.text = "APK descargado: %s" % p_path

func _on_dl_failed(p_reason: String) -> void:
	_bar.visible = false
	_dl_btn.disabled = false
	_status.text = "Falló la descarga: %s" % p_reason

func _on_open() -> void:
	var url = str(_info.get("url", ""))
	if url != "":
		OS.shell_open(url)
