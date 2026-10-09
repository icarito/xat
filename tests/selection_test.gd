extends SceneTree

# Selección de texto por pulsación larga: el label siempre tiene la selección
# habilitada y `begin_selection` lo pone a consumir el arrastre (STOP);
# `end_selection` restaura el filtro según plataforma.

var _fail := 0

func _init():
	var Bubble = load("res://addons/xat_xmpp/ui/bubble.gd")
	var root = get_root()
	var b = Bubble.new()
	b.set_record({"body": "hola mundo", "direction": "in", "timestamp": "2026-01-01T00:00:00Z"}, true, false, 0, false)
	root.add_child(b)
	check(b._label.selection_enabled, "selección habilitada (incluido táctil)")
	var idle = Control.MOUSE_FILTER_IGNORE if OS.has_touchscreen_ui_hint() else Control.MOUSE_FILTER_PASS
	check(b._label.mouse_filter == idle, "sin seleccionar, el arrastre pasa")
	b.begin_selection()
	check(b._label.mouse_filter == Control.MOUSE_FILTER_STOP, "seleccionando consume el arrastre")
	var t = b.selected_text()
	check(t == "" or t.find("hola") >= 0, "selected_text no rompe")
	b.end_selection()
	check(b._label.mouse_filter == idle, "al salir restaura el filtro")
	check(b.is_text_visible(), "texto visible con selección soportada")
	b.queue_free()
	if _fail == 0:
		print("SELECTION_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
