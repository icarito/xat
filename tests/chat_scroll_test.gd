extends SceneTree

# Regresión: con UNA sola burbuja muy grande la lista debe poder desplazarse, y
# un arrastre vertical táctil sobre el chat debe activar el scroll suave (antes
# el gesto se perdía si el texto cubría toda la zona visible).

var _fail := 0

func _init():
	var Main = load("res://main.gd")
	var m = Main.new()
	get_root().add_child(m)
	m._account.visible = false
	m._split.visible = true
	for i in range(6):
		yield(self, "idle_frame")

	m._chat.set_peer("a@h")
	var big := ""
	for i in range(80):
		big += "linea %d de un mensaje enorme para forzar alto\n" % i
	m._chat.add_message({"from": "a@h", "body": big, "direction": "in", "timestamp": "2026-01-01T10:00:00Z", "id": "big1", "commands": [], "quick_responses": []})
	for i in range(10):
		yield(self, "idle_frame")

	var sb = m._chat._scroll.get_v_scrollbar()
	var extent = sb.max_value - sb.page
	check(extent > 0.0, "una burbuja grande deja contenido desplazable (extent=%.0f)" % extent)

	# Al fondo y arrastre vertical hacia abajo (ver el inicio del mensaje): el
	# scroll debe subir (scroll_vertical disminuye).
	m._chat._scroll.scroll_vertical = int(extent)
	yield(self, "idle_frame")
	var rect = m._chat._scroll.get_global_rect()
	var c = rect.position + rect.size * 0.5
	var touch = InputEventScreenTouch.new()
	touch.index = 0
	touch.position = c
	touch.pressed = true
	m._chat._input(touch)
	check(m._chat._press, "press registrado en el cuerpo del chat")

	var drag = InputEventScreenDrag.new()
	drag.index = 0
	drag.position = c + Vector2(0, 40)
	drag.relative = Vector2(0, 40)
	m._chat._input(drag)
	check(m._chat._smooth.is_active() or abs(m._chat._smooth._vel) > 0.01, "arrastre vertical activa el scroll suave")

	var before = m._chat._scroll.scroll_vertical
	for i in range(30):
		yield(self, "idle_frame")
	check(m._chat._scroll.scroll_vertical < before, "el arrastre vertical mueve la lista hacia arriba (%d -> %d)" % [before, m._chat._scroll.scroll_vertical])

	# macOS: el scroll del trackpad llega como PanGesture; debe scrollear igual.
	m._chat._scroll.scroll_vertical = int(extent)
	yield(self, "idle_frame")
	var pan = InputEventPanGesture.new()
	pan.position = c
	pan.delta = Vector2(0, -1.0)
	var before_pan = m._chat._scroll.scroll_vertical
	m._chat._input(pan)
	check(m._chat._smooth.is_active() or abs(m._chat._smooth._vel) > 0.01, "PanGesture activa el scroll (trackpad)")
	for i in range(30):
		yield(self, "idle_frame")
	check(m._chat._scroll.scroll_vertical != before_pan, "PanGesture mueve la lista")

	m.free()
	if _fail == 0:
		print("CHAT_SCROLL_CHECK_OK")
	quit()

func check(p_ok: bool, p_label: String) -> void:
	if p_ok:
		print("ok %s" % p_label)
	else:
		_fail += 1
		print("FAIL %s" % p_label)
		OS.exit_code = 1
