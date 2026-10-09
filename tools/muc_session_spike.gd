extends SceneTree

# Spike 2 (live): valida la API de Session para salas — join, ocupantes,
# send_groupchat con dedupe del eco propio en el store, MAM de sala y leave.
# NO es parte de la suite: requiere credenciales reales.
#
# Uso (aislando el XDG_DATA_HOME para no tocar el history.db real):
#   XAT_E2E_JID=... XAT_E2E_PASS=... XAT_E2E_SECONDS=30 \
#     bin/godot-xat --no-window --path app -s "$PWD/tools/muc_session_spike.gd"

const Session = preload("res://addons/xat_xmpp/xmpp/session.gd")
const Stanza = preload("res://addons/xat_xmpp/xmpp/stanza.gd")

var _s = null
var _started := false
var _start_ms := 0
var _budget_ms := 30000
var _room := "xattest@conference.hablar.fuentelibre.org"
var _nick := "ale"
var _joined_ms := 0
var _sent := false
var _asked_mam := false
var _rows := -1
var _seen := []
var _final := ""
var _stay := false
var _admin_add := ""
var _say := "hola desde session %d"
var _admin_done := false

func _idle(_delta: float) -> bool:
	if not _started:
		_start()
		return false
	var now = OS.get_ticks_msec()
	if _joined_ms > 0 and not _sent and now - _joined_ms > 1500:
		_sent = true
		var body = (_say % now) if _say.find("%d") >= 0 else _say
		var rc = _s.send_groupchat(_room, body)
		print("SSPIKE: send_groupchat rc=%d last_sent_id=%s" % [rc, _s.last_sent_id])
	if _joined_ms > 0 and _admin_add != "" and not _admin_done and now - _joined_ms > 800:
		_admin_done = true
		_grant_membership(_admin_add)
	if _sent and not _asked_mam and now - _joined_ms > 4000:
		_asked_mam = true
		print("SSPIKE: ocupantes=%s" % str(_s.muc_occupants(_room).size()))
		_s.load_history(_room)
	if _rows >= 0 and not _stay and now - _joined_ms > 5500:
		_s.leave_room(_room)
		_final = "ok"
	if _final != "" or now - _start_ms > _budget_ms:
		_report()
		quit()
		return true
	return false

func _start() -> void:
	_started = true
	_start_ms = OS.get_ticks_msec()
	_stay = OS.get_environment("XAT_MUC_STAY") == "1"
	if _stay:
		# Sin leave ni condición de _rows: sólo esperar el presupuesto.
		pass
	var secs = int(OS.get_environment("XAT_E2E_SECONDS"))
	if secs > 0:
		_budget_ms = secs * 1000
	var room = OS.get_environment("XAT_MUC_ROOM")
	if room != "":
		_room = room
	var nick = OS.get_environment("XAT_MUC_NICK")
	if nick != "":
		_nick = nick
	_admin_add = OS.get_environment("XAT_MUC_ADMIN_ADD")
	var say = OS.get_environment("XAT_MUC_SAY")
	if say != "":
		_say = say
	var jid = OS.get_environment("XAT_E2E_JID")
	var p = OS.get_environment("XAT_E2E_PASS")
	if jid == "":
		var cfg = load("res://addons/xat_xmpp/xmpp/credentials.gd").new().load_with_env("user://account.json")
		jid = str(cfg.get("jid", ""))
		p = str(cfg.get("password", ""))
	_s = Session.new()
	_s.name = "S"
	get_root().add_child(_s)
	_s.connect("state_changed", self, "_on_state")
	_s.connect("muc_joined", self, "_on_joined")
	_s.connect("muc_left", self, "_on_left")
	_s.connect("muc_subject", self, "_on_subject")
	_s.connect("muc_occupants_changed", self, "_on_occ")
	_s.connect("message_received", self, "_on_msg")
	_s.connect("history_fetched", self, "_on_history")
	if OS.get_environment("XAT_MUC_RAW") == "1":
		_s._transport.connect("stanza", self, "_on_raw")
	print("SSPIKE: conectando %s..." % jid)
	_s.connect_account(jid, p, "", 5222)

func _on_raw(p_xml: String) -> void:
	if p_xml.find("conference") >= 0 or p_xml.find("xate2e") >= 0 or p_xml.find("muc#") >= 0:
		print("RAW: %s" % p_xml)

func _on_state(p_state: int) -> void:
	print("SSPIKE: state -> %d" % p_state)
	if p_state == Session.State.CONNECTED and not _s.is_room(_room):
		_s.join_room(_room, _nick)

func _on_joined(p_room: String) -> void:
	print("SSPIKE: muc_joined %s" % p_room)
	if p_room == _room:
		_joined_ms = OS.get_ticks_msec()

# El dueño de la sala agrega a otro JID como miembro (salas members_only).
func _grant_membership(p_jid: String) -> void:
	var iq = Stanza.new("iq")
	iq.set_attr("type", "set")
	iq.set_attr("to", _room)
	iq.set_attr("id", "admin-add")
	var q = Stanza.new("query")
	q.set_attr("xmlns", "http://jabber.org/protocol/muc#admin")
	var item = Stanza.new("item")
	item.set_attr("jid", p_jid)
	item.set_attr("affiliation", "member")
	q.add_child_stanza(item)
	iq.add_child_stanza(q)
	_s._transport.send(iq.to_xml())
	print("SSPIKE: muc#admin set member %s" % p_jid)

func _on_left(p_room: String, _reason: String) -> void:
	print("SSPIKE: muc_left %s final=%s" % [p_room, _final])

func _on_subject(p_room: String, p_subject: String) -> void:
	print("SSPIKE: subject %s = %s" % [p_room, p_subject])

func _on_occ(p_room: String) -> void:
	print("SSPIKE: occupants_changed %s -> %d" % [p_room, _s.muc_occupants(p_room).size()])

func _on_msg(rec: Dictionary) -> void:
	if rec.get("muc", false):
		_seen.append({"body": rec.get("body", ""), "direction": rec.get("direction", ""), "from": rec.get("from", "")})
		print("SSPIKE: muc msg dir=%s from=%s body=%s" % [rec.get("direction", ""), rec.get("from", ""), rec.get("body", "")])

func _on_history(p_bare: String, p_rows: Array, _complete: bool) -> void:
	if p_bare == _room:
		_rows = p_rows.size()
		print("SSPIKE: history %s rows=%d" % [p_bare, _rows])

func _report() -> void:
	var stored = _s.get_recent_history(_room, 20)
	var self_rows = 0
	for r in stored:
		if r.get("direction", "") == "out" and str(r.get("body", "")).find("session") >= 0:
			self_rows += 1
	print("SSPIKE RESULT: joined=%s sent=%s mam_rows=%d store_rows=%d self_rows=%d occupants=%d seen=%s final=%s" % [
		str(_joined_ms > 0), str(_sent), _rows, stored.size(), self_rows, _s.muc_occupants(_room).size(), str(_seen), _final
	])
