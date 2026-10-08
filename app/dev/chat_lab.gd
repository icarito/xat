extends Control

# Laboratorio visual del chat: tema + ChatPanel con conversación falsa.

const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")
const ChatPanel = preload("res://addons/xat_xmpp/ui/chat_panel.gd")

func _ready() -> void:
	theme = XatTheme.build()
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	var c = ChatPanel.new()
	add_child(c)
	c.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	c.set_peer("agente@xat.example")
	c.set_chat_state("escribiendo…")
	var today = ChatPanel.today_iso()
	var yday = OS.get_datetime_from_unix_time(OS.get_unix_time_from_datetime(ChatPanel._day_dict(today)) - 86400)
	var yiso = "%04d-%02d-%02d" % [yday.year, yday.month, yday.day]
	var h = [
		["in", "Buenas, dejé corriendo el **deploy** anoche", yiso, "21:40"],
		["out", "Gracias, lo reviso mañana", yiso, "21:41"],
		["in", "Cualquier cosa me avisas", yiso, "21:41"],
		["out", "Dale", yiso, "21:45"],
		["in", "Por cierto, rotaron las credenciales del staging", yiso, "22:10"],
		["in", "Las nuevas están en el vault, no las pegues en el chat", yiso, "22:10"],
		["out", "Entendido", yiso, "22:12"],
		["in", "Buenas noches", yiso, "22:30"],
		["in", "Hola, ¿en qué te ayudo hoy?", today, "10:00"],
		["out", "Necesito revisar el **deploy** de ayer", today, "10:01"],
		["out", "Y ver el estado de `main`", today, "10:01"],
		["in", "Claro. Esto es lo que encontré:\n\n- build verde\n- 3 tests lentos\n- `deploy.sh` sin cambios", today, "10:02"],
		["in", "Un párrafo largo para verificar el ajuste de línea: el agente suele responder con explicaciones extensas que deben envolverse dentro de la burbuja sin sobrepasar el setenta por ciento del ancho del panel, manteniendo el texto legible.", today, "10:02"],
		["out", "Perfecto, gracias", today, "10:03"],
	]
	c.set_history(_rows(h))
	c.mark_unread_from(5)
	yield(get_tree().create_timer(0.5), "timeout")
	# Estado "scrolleado arriba": los mensajes nuevos suman al contador del botón.
	c.add_message({"from": "a", "body": "veriifcando…", "direction": "in", "timestamp": today + "T10:04:00Z", "id": "x1"})
	c.apply_correction({"replace_id": "x1", "body": "Verificando **ahora**", "direction": "in", "timestamp": ""})
	c.add_message({"from": "a", "body": "Un momento más", "direction": "in", "timestamp": today + "T10:04:00Z", "id": "x2"})
	c.tool_started("bash", "git status && ./deploy.sh --dry-run")
	yield(get_tree().create_timer(1.2), "timeout")
	c.tool_finished(true)
	c.tool_started("read_file", "src/main.gd")
	c.add_message({"from": "a", "body": "¿Apruebo el cambio?", "direction": "in", "timestamp": today + "T10:05:00Z", "id": "q1",
		"commands": [{"node": "cmd:a:0", "name": "Allow"}, {"node": "cmd:a:1", "name": "Deny"}],
		"quick_responses": [{"value": "si", "label": "Sí"}, {"value": "no", "label": "No"}]})
	c.apply_approval_hook({"event": "approval", "state": "pending", "stanzaId": "q1", "command": "rm -rf build/", "expiresAtMs": float(OS.get_unix_time()) * 1000.0 + 45000.0})
	c.set_thinking(true)

func _rows(p_h: Array) -> Array:
	var r := []
	for x in p_h:
		r.append({"direction": x[0], "body": x[1], "ts": x[2] + "T" + x[3] + ":00Z", "request_id": "h%d" % r.size()})
	return r
