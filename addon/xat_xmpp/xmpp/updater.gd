extends Node

const Platform = preload("res://addons/xat_xmpp/xmpp/platform.gd")

# Actualizaciones in-app desde los GitHub Releases de xat.
#   check()            -> consulta releases/latest y compara versiones
#   download()         -> baja el asset de esta plataforma a user://updates/
#   install(path)      -> Android: instalador nativo (XatMedia.install_apk)
#                         Linux: reemplaza el binario en ejecución
#
# El asset se elige por plataforma (apk / ipa / macos.zip / linux). En Android
# la instalación la abre el plugin nativo del fork; en Linux se hace un
# auto-reemplazo del binario; en macOS/iOS `can_install()` es false y la vista
# abre el paquete descargado.

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
	var asset = _platform_asset(rel.get("assets", []))
	if ver == "" or asset.empty():
		emit_signal("check_failed", "el release no trae binario para %s" % OS.get_name())
		return
	latest = {
		"version": ver, "tag": tag, "notes": str(rel.get("body", "")),
		"url": str(asset.get("url", "")), "size": int(asset.get("size", 0)),
		"name": str(asset.get("name", "")), "kind": str(asset.get("kind", "")),
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
	# HTTPRequest necesita `download_file` ANTES de request() para escribir a
	# disco; si no, deja el cuerpo en memoria y el archivo nunca existe.
	_dl.download_file = _dl_path
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

# --- Instalación ---

func can_install() -> bool:
	# Android: instalador nativo (XatMedia). Linux: auto-reemplazo del binario.
	# Los JNISingleton exponen métodos sólo vía call(); has_method da false.
	return Engine.has_singleton("XatMedia") or _linux_self_update()

func install(p_path: String) -> bool:
	if p_path == "":
		return false
	if Engine.has_singleton("XatMedia"):
		var m = Engine.get_singleton("XatMedia")
		return bool(m.call("install_apk", p_path))
	if _linux_self_update():
		return _install_linux(p_path)
	return false

# --- Actualización en Linux (escritorio) ---

# Sólo tiene sentido en un build exportado (no en el editor, donde el
# ejecutable es el propio Godot).
func _linux_self_update() -> bool:
	if not Platform.is_linux() or not OS.has_feature("standalone"):
		return false
	return OS.get_executable_path() != ""

# Reemplaza el binario en ejecución con la descarga ya copiada en p_path.
func _install_linux(p_path: String) -> bool:
	var exe = OS.get_executable_path()
	if exe == "":
		return false
	return _replace_binary(p_path, exe)

# Copia p_src sobre p_dest de forma atómica: staging en el mismo directorio y
# rename encima. En Linux el rename sobre un binario en uso es permitido; el
# proceso sigue con el inodo viejo hasta reiniciar.
func _replace_binary(p_src: String, p_dest: String) -> bool:
	var d = Directory.new()
	var staging = p_dest.get_base_dir() + "/." + p_dest.get_file() + ".new"
	if d.copy(p_src, staging) != OK:
		return false
	# chmod +x best-effort: algunos sistemas no traen chmod en PATH.
	OS.execute("chmod", ["+x", staging], true)
	if d.rename(staging, p_dest) != OK:
		d.remove(staging)
		return false
	return true

# Elige el asset del release para la plataforma actual. p_platform permite
# forzarla en tests (por defecto OS.get_name()).
func _platform_asset(p_assets, p_platform := "") -> Dictionary:
	var plat = p_platform if p_platform != "" else OS.get_name()
	var want = "linux"
	match plat:
		"Android":
			want = "android"
		"iOS":
			want = "ios"
		"macOS", "OSX":
			want = "macos"
		"Windows", "UWP":
			want = "windows"
	for a in p_assets:
		if not (a is Dictionary):
			continue
		var name = str(a.get("name", ""))
		if _asset_kind(name) == want:
			return {
				"url": str(a.get("browser_download_url", "")),
				"size": int(a.get("size", 0)),
				"name": name,
				"kind": want,
			}
	return {}

# Clasifica el nombre de un asset por plataforma ("" si no se reconoce).
func _asset_kind(p_name: String) -> String:
	var n = p_name.to_lower()
	if n.ends_with(".apk"):
		return "android"
	if n.ends_with(".ipa"):
		return "ios"
	if n.ends_with(".dmg") or n.ends_with(".pkg"):
		return "macos"
	if n.ends_with(".exe") or n.ends_with(".msi"):
		return "windows"
	if n.ends_with(".zip"):
		if "macos" in n or "osx" in n:
			return "macos"
		if "windows" in n:
			return "windows"
		return ""
	if "linux" in n:
		return "linux"
	return ""

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
