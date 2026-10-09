extends Reference

# Captura de foto de cámara. Godot 3 no trae API de webcam: en escritorio Linux
# se delega en `ffmpeg`/`fswebcam` sobre V4L2; en Android/iOS no hay backend y se
# devuelve un motivo claro (haría falta un plugin nativo). Helper puro salvo el
# `OS.execute`, así que `backend()`/`error` son testeables por lectura.

const DEVICE := "/dev/video0"

const Media = preload("res://addons/xat_xmpp/xmpp/media.gd")

# Backend disponible: "ffmpeg", "fswebcam", "" (ninguno).
static func backend() -> String:
	if OS.get_name() != "Linux":
		return ""
	if _has_command("ffmpeg"):
		return "ffmpeg"
	if _has_command("fswebcam"):
		return "fswebcam"
	return ""

static func available() -> bool:
	return backend() != ""

# Captura a `p_dest` (jpg). Devuelve "" si salió bien, o un motivo.
static func capture(p_dest: String) -> String:
	match OS.get_name():
		"Android", "iOS":
			return "no-soportado"
	var be = backend()
	if be == "":
		return "sin-camara"
	var out := []
	var rc := 1
	if be == "ffmpeg":
		rc = OS.execute("ffmpeg", ["-hide_banner", "-loglevel", "error", "-y", "-f", "v4l2", "-i", DEVICE, "-frames:v", "1", "-q:v", "3", p_dest], true, out, true)
	elif be == "fswebcam":
		rc = OS.execute("fswebcam", ["-q", "--no-banner", "--device", DEVICE, p_dest], true, out, true)
	if rc != 0:
		return "captura-fallida"
	if Media.file_size(p_dest) <= 0:
		return "sin-imagen"
	return ""

static func _has_command(p_name: String) -> bool:
	var out := []
	return OS.execute("which", [p_name], true, out, false) == 0
