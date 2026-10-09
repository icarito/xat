extends SceneTree

# E2E de administración de salas (XEP-0045) con DOS cuentas reales en un solo
# proceso: A (dueño) crea la sala y B (miembro invitado) entra; luego A cambia el
# tema, expulsa a B, lee el formulario de config y destruye la sala. NO es parte
# de la suite. Requiere credenciales/entorno.
#
#   XAT_E2E_JID / XAT_E2E_PASS        cuenta A (dueño)
#   XAT_E2E_JID_B / XAT_E2E_PASS_B    cuenta B (miembro)
#   XAT_E2E_HOST / XAT_E2E_CAFILE     opcional
#   XAT_MUC_ROOM                      opcional (default xatadm<epoch>@conference...)
#   XAT_E2E_SECONDS                   opcional (default 40)
#
#   bin/godot-xat --no-window --path app -s "$PWD/tools/muc_admin_spike.gd"

const Session = preload("res://addons/xat_xmpp/xmpp/session.gd")

var _a = null
var _b = null
var _started := false
var _start_ms := 0
var _budget_ms := 40000
var _host := ""
var _cafile := ""
var _room := ""
var _a_jid := ""
var _a_pass := ""
var _b_jid := ""
var _b_pass := ""

var _a_joined := false
var _b_joined := false
var _subject_seen := false
var _config_fields := -1
var _b_kicked := false
var _b_destroyed := false
var _b_rejoined := false
var _a_steps := 0
var _final := ""

func _idle(_delta: float) -> bool:
	if not _started:
		_start()
		return false
	var now = OS.get_ticks_msec()
	_drive_a(now)
	if _b_destroyed or now - _start_ms > _budget_ms:
		_report()
		quit()
		return true
	return false

func _start() -> void:
	_started = true
	_start_ms = OS.get_ticks_msec()
	var secs = int(OS.get_environment("XAT_E2E_SECONDS"))
	if secs > 0:
		_budget_ms = secs * 1000
	_host = OS.get_environment("XAT_E2E_HOST")
	_cafile = OS.get_environment("XAT_E2E_CAFILE")
	_a_jid = OS.get_environment("XAT_E2E_JID")
	_a_pass = OS.get_environment("XAT_E2E_PASS")
	_b_jid = OS.get_environment("XAT_E2E_JID_B")
	_b_pass = OS.get_environment("XAT_E2E_PASS_B")
	if _a_jid == "":
		var cfg = load("res://addons/xat_xmpp/xmpp/credentials.gd").new().load_with_env("user://account.json")
		_a_jid = str(cfg.get("jid", ""))
		_a_pass = str(cfg.get("password", ""))
		if _host == "":
			_host = str(cfg.get("host", ""))
	var at = _a_jid.find("@")
	var domain = _a_jid.substr(at + 1) if at >= 0 else _a_jid
	_room = OS.get_environment("XAT_MUC_ROOM")
	if _room == "":
		_room = "xatadm%d@conference.%s" % [int(OS.get_ticks_msec()), domain]
	_a = _mk_session("A", _a_jid, _a_pass)
	_b = _mk_session("B", _b_jid, _b_pass)
	print("SSPIKE: A=%s B=%s room=%s" % [_a_jid, _b_jid, _room])
	_a.connect_account(_a_jid, _a_pass, _host, 5222)

func _mk_session(p_name: String, p_jid: String, p_pass: String):
	var s = Session.new()
	s.name = p_name
	get_root().add_child(s)
	s.connect("state_changed", self, "_on_state", [p_name])
	s.connect("muc_joined", self, "_on_joined", [p_name])
	s.connect("muc_left", self, "_on_left", [p_name])
	s.connect("muc_subject", self, "_on_subject", [p_name])
	s.connect("muc_config_form", self, "_on_config")
	s.connect("muc_occupants_changed", self, "_on_occ", [p_name])
	return s

func _on_state(p_state: int, p_name: String) -> void:
	if p_state != Session.State.CONNECTED:
		return
	if p_name == "A":
		_a.join_room(_room, "ale")
	else:
		_b.join_room(_room, "bob")

func _on_joined(p_room: String, p_name: String) -> void:
	print("SSPIKE: %s joined %s (aff=%s)" % [p_name, p_room, _aff_of(p_name)])
	if p_name == "A":
		_a_joined = true
	elif p_name == "B":
		if _b_kicked:
			_b_rejoined = true
		else:
			_b_joined = true

func _on_left(p_room: String, p_reason: String, p_name: String) -> void:
	print("SSPIKE: %s left %s reason=%s" % [p_name, p_room, p_reason])
	if p_name == "B":
		if _b_joined and not _b_kicked:
			_b_kicked = true
		elif _b_rejoined:
			_b_destroyed = true

func _on_subject(p_room: String, p_subject: String, p_name: String) -> void:
	if p_subject == "tema-e2e":
		_subject_seen = true
		print("SSPIKE: %s vio el tema '%s'" % [p_name, p_subject])

func _on_config(p_room: String, p_form: Dictionary) -> void:
	_config_fields = p_form.get("fields", []).size()
	print("SSPIKE: config form recibido (%d campos)" % _config_fields)

func _on_occ(p_room: String, p_name: String) -> void:
	print("SSPIKE: %s ocupantes -> %d" % [p_name, (_a if p_name == "A" else _b).muc_occupants(p_room).size()])

func _aff_of(p_name: String) -> String:
	var s = _a if p_name == "A" else _b
	return s.muc_affiliation(_room)

# Secuencia de A: tema -> miembro+invitación -> conectar B -> expulsar -> config -> destruir.
func _drive_a(now: int) -> void:
	if not _a_joined:
		return
	var el = now - _start_ms
	if _a_steps == 0 and el > 1500:
		_a_steps = 1
		_a.muc_set_subject(_room, "tema-e2e")
	if _a_steps == 1 and el > 2500:
		_a_steps = 2
		_a.muc_set_affiliation(_room, _b_jid, "member")
		_a.muc_invite(_room, _b_jid, "vení a la sala")
		_b.connect_account(_b_jid, _b_pass, _host, 5222)
	if _a_steps == 2 and _b_joined and el > 5000:
		_a_steps = 3
		_a.muc_kick(_room, "bob")
	if _a_steps == 3 and _b_kicked and el > 6500:
		_a_steps = 4
		_b.join_room(_room, "bob2")
	if _a_steps == 4 and _b_rejoined and el > 8000:
		_a_steps = 5
		_a.muc_request_config(_room)
	if _a_steps == 5 and _config_fields >= 0 and el > 9500:
		_a_steps = 6
		_a.muc_destroy(_room, "fin del test")

func _report() -> void:
	print("SSPIKE RESULT: a_joined=%s b_joined=%s subject_seen=%s config_fields=%d b_kicked=%s b_destroyed=%s final=%s" % [
		str(_a_joined), str(_b_joined), str(_subject_seen), _config_fields, str(_b_kicked), str(_b_destroyed), _final
	])