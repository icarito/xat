extends SceneTree

# Diagnóstico de la capa Session: conecta con las credenciales del entorno y
# registra transiciones de estado + logs relevantes de libstrophe (errores,
# stream, resume/SM, conflicto). Uso:
#   XAT_E2E_JID=... XAT_E2E_PASS=... bin/godot-xat --no-window --path app \
#     -s "$PWD/tools/session_probe.gd"

const Session = preload("res://addons/xat_xmpp/xmpp/session.gd")

var _s = null
var _started := false
var _start_ms := 0
var _budget_ms := 20000
var _states := []

func _idle(_delta: float) -> bool:
	if not _started:
		_start()
		return false
	if OS.get_ticks_msec() - _start_ms > _budget_ms:
		print("SESSION RESULT: states=%s connected=%s" % [str(_states), str(_s.is_connected_to_server())])
		quit()
		return true
	return false

func _start() -> void:
	_started = true
	_start_ms = OS.get_ticks_msec()
	var secs = int(OS.get_environment("XAT_E2E_SECONDS"))
	if secs > 0:
		_budget_ms = secs * 1000
	var jid = OS.get_environment("XAT_E2E_JID")
	var p = OS.get_environment("XAT_E2E_PASS")
	var host = OS.get_environment("XAT_E2E_HOST")
	var port = int(OS.get_environment("XAT_E2E_PORT"))
	if jid == "":
		# Sin env: credenciales guardadas por la app (archivo 0600).
		var cfg = load("res://addons/xat_xmpp/xmpp/credentials.gd").new().load_with_env("user://account.json")
		jid = str(cfg.get("jid", ""))
		p = str(cfg.get("password", cfg.get("pass", "")))
		host = str(cfg.get("host", ""))
		port = int(cfg.get("port", 5222))
	if port <= 0:
		port = 5222
	_s = Session.new()
	_s.name = "S"
	get_root().add_child(_s)
	_s.connect("state_changed", self, "_on_state")
	_s.connect("log_message", self, "_on_log")
	_s.connect("agent_state_changed", self, "_on_agent_state")
	_s.connect("agent_hook", self, "_on_agent_hook")
	print("SESSION: conectando %s (host='%s' port=%d)" % [jid, host, port])
	_s.connect_account(jid, p, host, port)

func _on_state(p_state: int) -> void:
	_states.append(p_state)
	print("SESSION STATE -> %d" % p_state)

func _on_log(_level: int, p_msg: String) -> void:
	var low = p_msg.to_lower()
	if low.find("error") >= 0 or low.find("fail") >= 0 or low.find("stream") >= 0 or low.find("resume") >= 0 or low.find("conflict") >= 0 or low.find("sm ") >= 0 or low.find("disconnect") >= 0 or low.find("not-authorized") >= 0:
		print("SESSION LOG: " + p_msg)

func _on_agent_state(p_bare: String, p_state: Dictionary) -> void:
	print("AGENT %s %d activity=%s model=%s tool=%s ctx=%s" % [p_bare, OS.get_ticks_msec() - _start_ms, p_state.get("activity"), p_state.get("model"), p_state.get("tool"), str(p_state.get("context"))])

func _on_agent_hook(p_bare: String, p_hook: Dictionary) -> void:
	print("HOOK %s %s" % [p_bare, JSON.print(p_hook)])
