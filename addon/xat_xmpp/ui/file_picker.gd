extends Node

# Selector de archivos nativo para escritorio. El FileDialog de Godot se dibuja
# a mano y "se ve raro" en GNOME/KDE, así que en Linux se delega en zenity
# (GNOME) o kdialog (KDE); en macOS osascript; en Windows PowerShell. Si no hay
# backend disponible emite `unavailable` para que el llamador use su fallback.
#
# La ejecución va en un Thread (OS.execute bloquea): al terminar se emite la
# señal en el hilo principal vía call_deferred.

signal picked(path)
signal cancelled()
signal unavailable()

var _thread: Thread
var _running := false

# `p_filters`: display strings en formato zenity, p. ej.
# ["Imágenes | *.png *.jpg", "Todos | *"]. En macOS/Windows se usan sólo los
# patrones (lo que venga tras el "|").
func open(p_title: String = "Elegir archivo", p_filters: Array = []) -> void:
	if _running:
		return
	if not has_native():
		emit_signal("unavailable")
		return
	_running = true
	_thread = Thread.new()
	_thread.start(self, "_run", {"title": p_title, "filters": p_filters})

static func has_native() -> bool:
	match OS.get_name():
		"Linux":
			return _which("zenity") != "" or _which("kdialog") != ""
		"macOS":
			return _which("osascript") != ""
		"Windows":
			return true
	return false

static func _which(p_bin: String) -> String:
	var out := []
	if OS.execute("which", [p_bin], true, out) == 0 and out.size() > 0:
		return str(out[0]).strip_edges()
	return ""

func _run(p_args: Dictionary) -> void:
	var path := _native(p_args)
	call_deferred("_finish", path)

func _finish(p_path: String) -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_running = false
	if p_path == "":
		emit_signal("cancelled")
	else:
		emit_signal("picked", p_path)

func _native(p_args: Dictionary) -> String:
	match OS.get_name():
		"Linux":
			return _linux(p_args)
		"macOS":
			return _macos(p_args)
		"Windows":
			return _windows(p_args)
	return ""

func _linux(p_args: Dictionary) -> String:
	var title = str(p_args.get("title", "Elegir archivo"))
	var out := []
	if _which("zenity") != "":
		var argv := ["--file-selection", "--title=" + title]
		for f in p_args.get("filters", []):
			argv.append("--file-filter=" + str(f))
		var rc = OS.execute("zenity", argv, true, out)
		return str(out[0]).strip_edges() if rc == 0 and out.size() > 0 else ""
	if _which("kdialog") != "":
		var pattern = "*"
		var filters = p_args.get("filters", [])
		if filters.size() > 0:
			var parts = str(filters[0]).split("|")
			if parts.size() > 1:
				pattern = str(parts[1]).strip_edges()
		var argv2 := ["--getopenfilename", OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS), pattern, "--title", title]
		var rc2 = OS.execute("kdialog", argv2, true, out)
		return str(out[0]).strip_edges() if rc2 == 0 and out.size() > 0 else ""
	return ""

func _macos(p_args: Dictionary) -> String:
	var out := []
	var script = 'POSIX path of (choose file with prompt "%s")' % str(p_args.get("title", "Elegir archivo"))
	var rc = OS.execute("osascript", ["-e", script], true, out)
	return str(out[0]).strip_edges() if rc == 0 and out.size() > 0 else ""

func _windows(p_args: Dictionary) -> String:
	var out := []
	var ps = 'Add-Type -AssemblyName System.Windows.Forms;' + \
		'$d=New-Object System.Windows.Forms.OpenFileDialog;' + \
		'if($d.ShowDialog() -eq "OK"){Write-Output $d.FileName}'
	var rc = OS.execute("powershell", ["-NoProfile", "-Command", ps], true, out)
	return str(out[0]).strip_edges() if rc == 0 and out.size() > 0 else ""
