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
