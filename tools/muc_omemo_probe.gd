extends SceneTree

# Sonda MUC+OMEMO: conecta con la cuenta guardada, se une a la sala y deja que
# session.gd loguee cada mensaje cifrado (stanza cruda + resultado). No es parte
# de la suite.

const Session = preload("res://addons/xat_xmpp/xmpp/session.gd")

var _s = null
var _started := false
var _t0 := 0
var _budget := 50000
var _room := "xispa@conference.hablar.fuentelibre.org"

func _idle(_d: float) -> bool:
	if not _started:
		_start()
		return false
	if OS.get_ticks_msec() - _t0 > _budget:
		print("MUC_PROBE_DONE")
		quit()
		return true
	return false

func _start() -> void:
	_started = true
	_t0 = OS.get_ticks_msec()
	var secs = int(OS.get_environment("XAT_PROBE_SECONDS"))
	if secs > 0:
		_budget = secs * 1000
	_room = OS.get_environment("XAT_PROBE_ROOM") if OS.get_environment("XAT_PROBE_ROOM") != "" else _room
	var cfg = load("res://addons/xat_xmpp/xmpp/credentials.gd").new().load_with_env("user://account.json")
	_s = Session.new()
	_s.name = "S"
	get_root().add_child(_s)
	_s.connect("state_changed", self, "_on_state")
	_s.connect("message_received", self, "_on_msg")
	_s.connect("muc_joined", self, "_on_joined")
	print("MUC_PROBE: conectando %s" % str(cfg.get("jid", "")))
	_s.connect_account(cfg["jid"], cfg.get("password", cfg.get("pass", "")), cfg.get("host", ""), int(cfg.get("port", 5222)), cfg.get("cafile", ""))

func _on_state(p_state: int) -> void:
	if p_state == 2:
		print("MUC_PROBE: conectado, entrando a %s" % _room)
		_s.join_room(_room, _s.bare().split("@")[0])

func _on_msg(p_rec) -> void:
	if str(p_rec.get("type", "")) == "groupchat":
		print("MUC_MSG enc=%s from=%s body=%s" % [str(p_rec.get("encrypted", false)), str(p_rec.get("from", "")), str(p_rec.get("body", ""))])

var _ping_sent := false

func _on_joined(p_room: String) -> void:
	if _ping_sent:
		return
	_ping_sent = true
	print("MUC_PROBE: unido a %s" % p_room)
	if OS.get_environment("XAT_PROBE_PING") == "1":
		_s.send_groupchat(p_room, "ping omemo desde xat")
