extends SceneTree

# El zoom desde _input: inyecta Ctrl+= / Ctrl+rueda por el viewport y verifica
# que main._input lo tome (no sólo la función _zoom).

var _fail := 0

func _init():
	var Main = preload("res://main.gd")
	var main = Main.new()
	get_root().add_child(main)
	var fz = get_root().get_node_or_null("FontZoom")
	check(fz != null, "FontZoom presente")

	var start = main._zoom_target
	var ev = InputEventKey.new()
	ev.scancode = KEY_EQUAL
	ev.control = true
	ev.pressed = true
	get_root().input(ev)
	check(main._zoom_target > start, "Ctrl+= llega a _input y sube el objetivo (%.2f -> %.2f)" % [start, main._zoom_target])

	var mid = main._zoom_target
	var wheel = InputEventMouseButton.new()
	wheel.button_index = BUTTON_WHEEL_DOWN
	wheel.control = true
	wheel.pressed = true
	main._input(wheel)
	check(main._zoom_target < mid, "Ctrl+rueda abajo baja el objetivo (%.2f -> %.2f)" % [mid, main._zoom_target])

	# Sin Ctrl no debe zoomear (rueda = scroll normal).
	var plain = main._zoom_target
	var w2 = InputEventMouseButton.new()
	w2.button_index = BUTTON_WHEEL_UP
	w2.pressed = true
	get_root().input(w2)
	check(is_equal_approx(main._zoom_target, plain), "rueda sin Ctrl no zoomea")

	# Ctrl++ con layout donde '+' tiene scancode propio.
	var before_plus = main._zoom_target
	var plus = InputEventKey.new()
	plus.scancode = KEY_PLUS
	plus.control = true
	plus.shift = true
	plus.pressed = true
	main._input(plus)
	check(main._zoom_target > before_plus, "Ctrl++ (KEY_PLUS) también zoomea")

	# macOS: Cmd (meta) también debe zoomear con ± y con rueda.
	var before_meta = main._zoom_target
	var cmd = InputEventKey.new()
	cmd.scancode = KEY_EQUAL
	cmd.meta = true
	cmd.pressed = true
	main._input(cmd)
	check(main._zoom_target > before_meta, "Cmd+= (meta) zoomea en macOS")
	var before_meta_wheel = main._zoom_target
	var mw = InputEventMouseButton.new()
	mw.button_index = BUTTON_WHEEL_DOWN
	mw.meta = true
	mw.pressed = true
	main._input(mw)
	check(main._zoom_target < before_meta_wheel, "Cmd+rueda (meta) zoomea en macOS")

	# Trackpad: pan con Ctrl/Cmd zoomea; sin modificador no.
	var before_pan = main._zoom_target
	var pan = InputEventPanGesture.new()
	pan.delta = Vector2(0, 5)
	pan.control = true
	main._input(pan)
	check(main._zoom_target < before_pan, "pan + Ctrl zoomea")
	var plain_pan = main._zoom_target
	var pan2 = InputEventPanGesture.new()
	pan2.delta = Vector2(0, 5)
	main._input(pan2)
	check(is_equal_approx(main._zoom_target, plain_pan), "pan sin modificador no zoomea")

	# Botones de la UI (roster y sidebar) y su handler.
	check(main._roster.has_signal("font_scale_requested"), "roster expone font_scale_requested")
	check(main._sb_font_smaller != null and main._sb_font_bigger != null, "sidebar tiene botones de tamaño de letra")
	var before_btn = main._zoom_target
	main._on_font_scale_requested(1)
	check(main._zoom_target > before_btn, "botón A+ sube el objetivo")
	var before_btn2 = main._zoom_target
	main._on_font_scale_requested(-1)
	check(main._zoom_target < before_btn2, "botón A− baja el objetivo")

	# El mínimo permite achicar bastante (fuentes gigantes en macOS).
	main.set_zoom(0.55)
	check(fz.scale <= 0.56 and fz.scale >= 0.54, "se puede reducir a ~0.55 (antes tope 0.7)")

	main.free()
	if _fail == 0:
		print("ZOOM_INPUT_CHECK_OK")
	quit()

func check(p_ok: bool, p_label: String) -> void:
	if p_ok:
		print("ok %s" % p_label)
	else:
		_fail += 1
		print("FAIL %s" % p_label)
		OS.exit_code = 1
