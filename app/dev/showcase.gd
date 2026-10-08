extends Control

# Showcase end-to-end: main.tscn real con una sesión simulada. La telemetría y
# los hooks entran como XML PEP por session._on_stanza (mismo camino que la red);
# los mensajes se inyectan directo a main (sin tocar el historial SQLite).
# SHOWCASE_STEP=n congela tras el paso n (para screenshots); sin él, recorre todo.

const AGENT := "kangurito@hablar.fuentelibre.org"
const EV := '<message from="%s/oc" type="headline"><event xmlns="http://jabber.org/protocol/pubsub#event"><items node="%s"><item id="current">%s</item></items></event></message>'

var _m

func _ready() -> void:
	_m = load("res://main.tscn").instance()
	add_child(_m)
	_m._on_state_changed(_m.SessionScript.State.CONNECTED)
	var peers = [AGENT, "lazaro@hablar.fuentelibre.org", "ana@hablar.fuentelibre.org"]
	_m._roster.set_peers(peers)
	for p in [AGENT, "lazaro@hablar.fuentelibre.org", "ana@hablar.fuentelibre.org"]:
		_m.session.presence_model.update(p + "/oc", "", "", 0, "")
		_m._on_presence_changed(p)
	_tel("lazaro@hablar.fuentelibre.org", "available", 9000, "", "")
	_tel(AGENT, "available", 12000, "", "")
	_m._roster.select(AGENT)
	_m._on_peer_selected(AGENT)
	var stop = int(OS.get_environment("SHOWCASE_STEP")) if OS.get_environment("SHOWCASE_STEP") != "" else 99
	for i in range(min(stop, 6) + 1):
		_step(i)
		if stop == 99:
			yield(get_tree().create_timer(1.6), "timeout")

func _step(i: int) -> void:
	match i:
		0:
			_msg("out", "¿Podés limpiar el build y correr los tests?", "m1")
			_m._on_delivery("m1", AGENT)
		1:
			_tel(AGENT, "processing", 30500, "", "")
			_msg("in", "Dale, primero miro el estado del repo.", "a1")
		2:
			_tel(AGENT, "processing", 52000, "exec", "")
		3:
			_tel(AGENT, "processing", 61000, "read_file", "")
		4:
			_tel(AGENT, "pending", 78000, "", "")
			var rec = _msg("in", "Para limpiar necesito borrar `build/`. ¿Apruebo?", "a2")
			rec["quick_responses"] = [{"label": "Sí", "value": "si"}, {"label": "No", "value": "no"}]
			_m._chat.set_actions(rec)
			_hook("approval", {"event": "approval", "state": "pending", "approvalId": "ap1", "stanzaId": "a2", "command": "rm -rf build/", "expiresAtMs": OS.get_unix_time() * 1000 + 45000})
		5:
			_m._chat._on_decided("quick", "si") if _m._chat.has_method("_on_decided") else null
			_tel(AGENT, "processing", 88000, "exec", "")
		6:
			_tel(AGENT, "available", 93000, "", "")
			_hook("progress", {"event": "progress", "state": "end"})
			_msg("in", "Listo: **build limpio**, 42 tests en verde ✔", "a3")

func _tel(p_bare: String, p_act: String, p_used: int, p_tool: String, _x) -> void:
	var t = '<telemetry xmlns="urn:openclaw:telemetry:0" activity="%s" availability="available"><context used="%d" max="131072"/><tokens total="%d" input="%d" output="%d" requests="4"/><cost usd="0.0021"/><session-cost usd="0.0384"/><day-cost usd="1.27"/><model>deepseek/deepseek-v4-pro</model><tool>%s</tool><session status="running"/></telemetry>'
	_m.session._on_stanza(EV % [p_bare, "urn:openclaw:telemetry:0", t % [p_act, p_used, p_used / 3, p_used / 4, p_used / 12, p_tool]])

func _hook(p_kind: String, p_payload: Dictionary) -> void:
	var node = "urn:openclaw:hooks:%s:0" % p_kind
	_m.session._on_stanza(EV % [AGENT, node, '<event xmlns="%s" version="1">%s</event>' % [node, JSON.print(p_payload).xml_escape()]])

func _msg(p_dir: String, p_body: String, p_id: String) -> Dictionary:
	var rec = {"from": AGENT if p_dir == "in" else "sebastian@hablar.fuentelibre.org", "to": AGENT if p_dir == "out" else "",
		"body": p_body, "direction": p_dir, "timestamp": Time.get_datetime_string_from_system(true) + "Z", "id": p_id,
		"commands": [], "quick_responses": []}
	if p_dir == "out":
		_m._chat.add_message(rec)
	else:
		_m._on_message_received(rec)
	return rec
