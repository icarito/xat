extends Node

# Actualizaciones in-app desde los GitHub Releases de xat.
#   check()            -> consulta releases/latest y compara versiones
#   download()         -> baja el .apk a user://updates/ con progreso
#   install(path)      -> abre el instalador del sistema (XatMedia.install_apk)
#
# La instalación sólo existe en Android (plugin nativo del fork). En escritorio
# `can_install()` es false y la vista ofrece abrir la descarga en el navegador.

signal update_available(info)
signal up_to_date(version)
signal check_failed(reason)
signal progress(downloaded, total)
signal downloaded(path)
signal download_failed(reason)

const API_LATEST := "https://api.github.com/repos/icarito/xat/releases/latest"
const UA := "xat-updater"

var current_version := "0.0.0"
var latest := {}
var downloading := false

var _check: HTTPRequest
var _dl: HTTPRequest
var _dl_path := ""
var _body_size := 0

func _ready() -> void:
	_check = HTTPRequest.new()
	_check.use_threads = true
	add_child(_check)
	_check.connect("request_completed", self, "_on_check_done")
	_dl = HTTPRequest.new()
	_dl.use_threads = true
	add_child(_dl)
	_dl.connect("request_completed", self, "_on_dl_done")
	set_process(false)

func check(p_current: String) -> void:
	current_version = p_current if p_current != "" else "0.0.0"
	if _check.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var err = _check.request(API_LATEST, ["Accept: application/vnd.github+json", "User-Agent: " + UA], true, HTTPClient.METHOD_GET)
	if err != OK:
		emit_signal("check_failed", "no se pudo iniciar la consulta (%d)" % err)

func _on_check_done(result: int, code: int, _headers, body: PoolByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		emit_signal("check_failed", "fallo de red (%d)" % result)
		return
	if code == 404:
		emit_signal("check_failed", "no hay releases publicados")
		return
	if code != 200:
		emit_signal("check_failed", "HTTP %d" % code)
		return
	var parsed = JSON.parse(body.get_string_from_utf8())
	if parsed.error or not (parsed.result is Dictionary):
		emit_signal("check_failed", "respuesta inválida")
		return
	var rel = parsed.result
	var tag = str(rel.get("tag_name", ""))
	var ver = tag.trim_prefix("v")
	var url := ""
	var size := 0
	var name := ""
	for a in rel.get("assets", []):
		var an = str(a.get("name", ""))
		if an.ends_with(".apk"):
			url = str(a.get("browser_download_url", ""))
			size = int(a.get("size", 0))
			name = an
			break
	if ver == "" or url == "":
		emit_signal("check_failed", "el release no tiene APK")
		return
	latest = {
		"version": ver, "tag": tag, "notes": str(rel.get("body", "")),
		"url": url, "size": size, "name": name,
		"published_at": str(rel.get("published_at", "")),
	}
	if _is_newer(ver, current_version):
		emit_signal("update_available", latest)
	else:
		emit_signal("up_to_date", current_version)

func download() -> void:
	if latest.empty() or downloading:
		return
	var name = str(latest.get("name", "xat.apk"))
	_dl_path = "user://updates/%s" % name
	var dir = Directory.new()
	dir.make_dir_recursive("user://updates")
	_body_size = int(latest.get("size", 0))
	downloading = true
	var err = _dl.request(str(latest["url"]), ["User-Agent: " + UA])
	if err != OK:
		downloading = false
		emit_signal("download_failed", "no se pudo iniciar la descarga (%d)" % err)
		return
	set_process(true)

func _process(_delta: float) -> void:
	if not downloading:
		set_process(false)
		return
	var total = _body_size
	if total <= 0:
		total = _dl.get_body_size()
	emit_signal("progress", _dl.get_downloaded_bytes(), total)

func _on_dl_done(result: int, code: int, _headers, _body: PoolByteArray) -> void:
	downloading = false
	set_process(false)
	if result != HTTPRequest.RESULT_SUCCESS or (code != 200 and code != 0):
		emit_signal("download_failed", "descarga falló (result=%d code=%d)" % [result, code])
		return
	# `download_file` dejó el archivo en user://updates/<name>.
	emit_signal("downloaded", ProjectSettings.globalize_path(_dl_path))

# --- Instalación (Android nativo) ---

func can_install() -> bool:
	if not Engine.has_singleton("XatMedia"):
		return false
	var m = Engine.get_singleton("XatMedia")
	return m.has_method("install_apk")

func install(p_path: String) -> bool:
	if p_path == "" or not Engine.has_singleton("XatMedia"):
		return false
	var m = Engine.get_singleton("XatMedia")
	if not m.has_method("install_apk"):
		return false
	return bool(m.call("install_apk", p_path))

# Semver simple: ¿a es más nueva que b? (compara partes numéricas).
func _is_newer(a: String, b: String) -> bool:
	var pa = a.split(".")
	var pb = b.split(".")
	var n = int(max(pa.size(), pb.size()))
	for i in range(n):
		var na = int(pa[i]) if i < pa.size() and pa[i].is_valid_integer() else 0
		var nb = int(pb[i]) if i < pb.size() and pb[i].is_valid_integer() else 0
		if na != nb:
			return na > nb
	return false
