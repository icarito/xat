extends Node

# Imagen del portapapeles (escritorio). Godot 3 no expone imágenes del
# portapapeles, así que en Linux se lee con wl-paste (Wayland) o xclip (X11) y
# se vuelca a un PNG temporal. La lectura bloquea, así que va en un Thread y la
# señal se emite en el hilo principal.

signal pasted(path)

var _thread: Thread
var _running := false

static func available() -> bool:
	match OS.get_name():
		"Linux":
			return _which("wl-paste") != "" or _which("xclip") != ""
	return false

static func _which(p_bin: String) -> String:
	var out := []
	if OS.execute("which", [p_bin], true, out) == 0 and out.size() > 0:
		return str(out[0]).strip_edges()
	return ""

func request() -> void:
	if _running or not available():
		return
	_running = true
	_thread = Thread.new()
	_thread.start(self, "_run", null)

func _run(_arg) -> void:
	var path := _read()
	call_deferred("_finish", path)

func _finish(p_path: String) -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_running = false
	emit_signal("pasted", p_path)

func _read() -> String:
	match OS.get_name():
		"Linux":
			return _linux()
	return ""

func _linux() -> String:
	var out_path := "user://clip_paste.png"
	var abs_path := ProjectSettings.globalize_path(out_path)
	var f = File.new()
	if f.file_exists(out_path):
		Directory.new().remove(out_path)
	var cmd := ""
	if _which("wl-paste") != "":
		cmd = "wl-paste --type image/png > \"%s\" 2>/dev/null" % abs_path
	elif _which("xclip") != "":
		cmd = "xclip -selection clipboard -t image/png -o > \"%s\" 2>/dev/null" % abs_path
	else:
		return ""
	OS.execute("sh", ["-c", cmd], true)
	if not f.file_exists(out_path) or f.open(out_path, File.READ) != OK:
		return ""
	var size = f.get_len()
	f.close()
	return out_path if size > 0 else ""
