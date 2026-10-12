extends SceneTree

# Zoom global: la ruta set_zoom -> FontZoom -> UiScale debe reescalar fuentes y
# geometría, y _zoom (coalescido) debe aplicar en _process.

var _fail := 0

func _init():
	var Main = preload("res://main.gd")
	var main = Main.new()
	get_root().add_child(main)
	var fz = get_root().get_node_or_null("FontZoom")
	check(fz != null, "FontZoom autoload presente")
	if fz == null:
		quit()
		return

	var start = fz.scale
	# Default sugerido según pantalla (DPI/diagonal): acotado y nunca mayor a 1.
	var FZScript = load("res://addons/xat_xmpp/ui/font_zoom.gd")
	var ds = FZScript.default_scale()
	check(ds >= FZScript.MIN and ds <= FZScript.DEFAULT, "default_scale acotado (%.2f)" % ds)
	main.set_zoom(start + 0.2)
	check(abs(fz.scale - (start + 0.2)) < 0.001, "set_zoom aplica el factor (%.2f)" % fz.scale)
	check(main._zoom_target > start, "set_zoom fija el objetivo")

	# _zoom coalescido: cambia el objetivo y _process lo aplica.
	var before = fz.scale
	main._zoom(1)
	check(main._zoom_target > before, "_zoom sube el objetivo coalescido")
	main._process(0.016)
	check(fz.scale > before, "_process aplica el zoom pendiente (%.2f)" % fz.scale)

	main.set_zoom(1.0)
	check(abs(fz.scale - 1.0) < 0.001, "reset a 1.0")

	main.free()
	if _fail == 0:
		print("ZOOM_CHECK_OK")
	quit()

func check(p_ok: bool, p_label: String) -> void:
	if p_ok:
		print("ok %s" % p_label)
	else:
		_fail += 1
		print("FAIL %s" % p_label)
		OS.exit_code = 1
