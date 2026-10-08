extends SceneTree

# Fase 3: la UI se construye y se conecta a la sesión. Se instancia el main
# headless y se ejercitan los paneles directamente (sin red).

var _fail := 0

func _init():
	var Main = load("res://main.gd")
	var m = Main.new()
	get_root().add_child(m)

	check(m.session != null, "sesión creada")
	check(m._account != null and m._roster != null and m._chat != null, "paneles creados")
	check(m._split != null and not m._split.visible, "vista de cuenta al inicio")

	# Validación de cuenta (sin conectar).
	m._account._jid.text = "agente@h"
	m._account._pass.text = "secreto"
	m._account._host.text = "h"
	m._account._port.text = "5222"
	var cfg = m._account.config()
	check(cfg["jid"] == "agente@h" and cfg["pass"] == "secreto" and cfg["port"] == 5222, "config de cuenta")

	# Roster.
	m._roster.set_peers(["a@h", "b@h"])
	m._roster.set_online("a@h", true)
	check(m._roster._peers.size() == 2, "roster con dos peers")
	m._roster.touch("b@h", "2026-10-08T10:00:00Z")
	check(m._roster._sorted()[0] == "b@h" and m._roster._box.get_child(0).get_meta("bare") == "b@h", "roster ordenado por actividad")

	# Chat: mensaje con markdown y botones de acción.
	m._chat.set_peer("a@h")
	m._chat.add_message({"from": "a@h", "body": "hola **mundo**", "direction": "in", "timestamp": "2026-01-01T10:00:00Z", "id": "m1", "commands": [], "quick_responses": []})
	check(m._chat._messages.size() == 1, "mensaje agregado")
	m._chat.set_actions({
		"commands": [{"jid": "bot@h/res", "node": "cmd:abc:0", "name": "Allow"}],
		"quick_responses": [{"value": "si", "label": "Sí"}],
	})
	check(m._chat._actions.get_child_count() == 2, "dos botones de acción")

	# Plegado de corrección en el render.
	m._chat.add_message({"from": "a@h", "body": "v1", "direction": "in", "timestamp": "2026-01-01T10:01:00Z", "id": "orig", "commands": [], "quick_responses": []})
	check(m._chat._messages.size() == 2, "segundo mensaje")
	m._chat.apply_correction({"from": "a@h", "body": "v2", "replace_id": "orig", "direction": "in", "timestamp": "", "id": "e1"})
	check(m._chat._messages.size() == 2 and m._chat._messages[1]["body"] == "v2", "corrección plegada sin nueva fila")

	# Agrupación: dos "in" seguidos -> sólo la última es group-last.
	check(m._chat._bubbles.size() == 2 and not m._chat._bubbles[0]._last and m._chat._bubbles[1]._last, "sólo la última del grupo lleva cola")
	m._chat.add_message({"from": "", "body": "yo", "direction": "out", "timestamp": "2026-01-01T10:02:00Z", "id": "o1"})
	check(m._chat._bubbles[1]._last and m._chat._bubbles[2]._last, "cambio de dirección abre grupo")
	check(m._chat._bubbles[1]._last and m._chat._bubbles[0]._last == false, "primer grupo intacto")
	check(m._chat._bubbles[1].rec.get("edited", false), "corrección marcada editado")
	m._chat.mark_delivered("o1")
	check(m._chat._messages[2].get("delivered", false) and m._chat._bubbles[2]._ticks.rect_min_size.x > 12, "mark_delivered pone ✓✓")

	# Separador por fecha: 2026-01-01 (primer día) y 2026-01-02.
	var pills = 0
	for ch in m._chat._list.get_children():
		if not ch is m._chat.Bubble:
			pills += 1
	m._chat.add_message({"from": "a@h", "body": "otro día", "direction": "in", "timestamp": "2026-01-02T09:00:00Z", "id": "d2"})
	var pills2 = 0
	for ch in m._chat._list.get_children():
		if not ch is m._chat.Bubble:
			pills2 += 1
	check(pills == 1 and pills2 == 2 and m._chat._last_day == "2026-01-02", "separador al cambiar de día")
	check(m._chat.day_label("2026-10-07", "2026-10-07") == "Hoy" and m._chat.day_label("2026-10-06", "2026-10-07") == "Ayer" and m._chat.day_label("2026-10-05", "2026-10-07") == "lun 5 oct", "etiquetas Hoy/Ayer/fecha")
	check(m._chat.near_bottom(820, 1000, 100) and not m._chat.near_bottom(700, 1000, 100) and m._chat.near_bottom(0, 50, 100), "near_bottom helper")
	# Marcador de no leídos: se quita al enviar.
	m._chat.mark_unread_from(-1)
	check(m._chat._unread_node != null and m._chat._unread_idx == m._chat._messages.size() - 1, "marcador Nuevos")
	m._chat._input.text = "hola"
	m._chat._on_send()
	check(m._chat._unread_node == null and m._chat._unread_idx == -1, "marcador se quita al enviar")
	m._chat.mark_unread_from(0)
	m._chat._on_scrolled(1000000.0)
	check(m._chat._unread_node == null, "marcador se quita al llegar al final")

	# Historial del store (vacío) no rompe.
	m._chat.set_history([])
	check(m._chat._messages.empty(), "set_history limpia")

	m.free()
	if _fail == 0:
		print("UI_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
