extends SceneTree

# Selección de texto: el label tiene la selección habilitada; la selección total
# es directa (`select_all`) y la parcial se hace inyectando mouse sintético
# (press/motion/release) al `_gui_input` del label. El filtro de mouse no cambia.

var _fail := 0

func _init():
	var Bubble = load("res://addons/xat_xmpp/ui/bubble.gd")
	var root = get_root()
	var b = Bubble.new()
	b.set_record({"body": "hola mundo largote", "direction": "in", "timestamp": "2026-01-01T00:00:00Z"}, true, false, 0, false)
	root.add_child(b)
	check(b._label.selection_enabled, "selección habilitada (incluido táctil)")
	var idle = Control.MOUSE_FILTER_IGNORE if OS.has_touchscreen_ui_hint() else Control.MOUSE_FILTER_PASS
	check(b._label.mouse_filter == idle, "sin seleccionar, el arrastre pasa")

	# Selección total.
	b.begin_selection()
	check(b.selected_text().find("hola") >= 0, "select_all selecciona el texto")
	check(b._label.mouse_filter == idle, "seleccionar no altera el filtro de mouse")
	b.end_selection()
	check(b.selected_text() == "", "end_selection limpia la selección")

	# Pulsación larga: selecciona la palabra bajo el dedo de inmediato (visible).
	var lab = b._label
	lab.rect_size = Vector2(300, 60)
	lab.set_size(Vector2(300, 60))
	lab.get_content_height()
	b.begin_selection_at(Vector2(6, 8))
	check(b.selected_text() != "", "pulsación larga selecciona la palabra")
	# Arrastrar extiende a una porción.
	b.drag_selection(Vector2(120, 8))
	b.end_selection_drag()
	check(b.selected_text().find("hola") >= 0, "arrastrar extiende la selección")
	# Tiradores: agarrar el más cercano y ajustar (incluso tras soltar).
	b.begin_handle_drag(Vector2(200, 8))
	check(b.is_handle_dragging(), "agarra un tirador al tocar la selección")
	b.drag_handle(Vector2(60, 8))
	check(b.selected_text().find("hola") >= 0, "ajuste por tirador mantiene la selección")
	b.end_selection_drag()
	check(not b.is_handle_dragging(), "soltar termina el ajuste")
	b.end_selection()
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
