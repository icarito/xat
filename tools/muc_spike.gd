extends SceneTree

# Spike headless de MUC (XEP-0045) contra un servidor real. NO es parte de la
# suite. Conecta, descubre el componente de salas, entra a una sala (la crea si
# el servidor lo permite), manda un groupchat, observa el eco propio, lista
# ocupantes y sale. Imprime las stanzas crudas para documentar los formatos
# reales (atributo vs texto, códigos de estado) antes de escribir la UI.
#
# Variables de entorno:
#   XAT_E2E_JID    (opcional) si falta usa user://account.json
#   XAT_E2E_PASS   (opcional)
#   XAT_E2E_HOST   (opcional)
#   XAT_E2E_PORT   (opcional, default 5222)
#   XAT_E2E_CAFILE (opcional)
#   XAT_MUC_ROOM   (opcional, default xattest@conference.<dominio>)
#   XAT_MUC_NICK   (opcional, default ale)
#   XAT_E2E_SECONDS (opcional, default 25)
#
# Uso:
#   bin/godot-xat --no-window --path app -s "$PWD/tools/muc_spike.gd"

const Stanza = preload("res://addons/xat_xmpp/xmpp/stanza.gd")
const Muc = preload("res://addons/xat_xmpp/xmpp/muc.gd")
const Media = preload("res://addons/xat_xmpp/xmpp/media.gd")

var _conn = null
var _started := false
var _start_ms := 0
var _budget_ms := 25000
var _jid := ""
var _pass := ""
var _host := ""
var _port := 5222
var _cafile := ""
var _room_cfg := ""
var _room := ""
var _nick := "ale"
var _bound := ""
var _domain := ""
var _conference := ""
var _occupants := {}
var _connected_ms := 0
var _joined_ms := 0
var _join_sent := false
var _joined := false
var _sent := false
var _left := false
var _echo := false
var _final := ""

func _idle(_delta: float) -> bool:
	if not _started:
		_start()
		return false
	if _final != "" or OS.get_ticks_msec() - _start_ms > _budget_ms:
		_report()
		quit()
		return true
	_advance(OS.get_ticks_msec())
	return false

func _start() -> void:
	_started = true
	_start_ms = OS.get_ticks_msec()
	_jid = OS.get_environment("XAT_E2E_JID")
	_pass = OS.get_environment("XAT_E2E_PASS")
	_host = OS.get_environment("XAT_E2E_HOST")
	_port = int(OS.get_environment("XAT_E2E_PORT"))
	_cafile = OS.get_environment("XAT_E2E_CAFILE")
	_room_cfg = OS.get_environment("XAT_MUC_ROOM")
	var nick_env = OS.get_environment("XAT_MUC_NICK")
	if nick_env != "":
		_nick = nick_env
	var secs = int(OS.get_environment("XAT_E2E_SECONDS"))
	if secs > 0:
		_budget_ms = secs * 1000
	if _jid == "":
		var cfg = load("res://addons/xat_xmpp/xmpp/credentials.gd").new().load_with_env("user://account.json")
		_jid = str(cfg.get("jid", ""))
		_pass = str(cfg.get("password", ""))
		if _host == "":
			_host = str(cfg.get("host", ""))
		if _port <= 0:
			_port = int(cfg.get("port", 5222))
	if _port <= 0:
		_port = 5222
	if _cafile == "":
		_cafile = "/etc/ssl/certs/ca-certificates.crt"
	if not ClassDB.class_exists("XmppConnection"):
		_final = "sin módulo nativo"
		return
	var at = _jid.find("@")
	_domain = _jid.substr(at + 1) if at >= 0 else _jid
	_conference = "conference." + _domain
	_room = _room_cfg if _room_cfg != "" else _conference + "/xattest"
	# Formato de sala: bare@conference (sin nick). El nick va aparte.
	_room = _room.substr(0, _room.find("/")) if _room.find("/") >= 0 else _room
	if _room.find("@") < 0:
		_room = "xattest@" + _conference
	_conn = ClassDB.instance("XmppConnection")
	get_root().add_child(_conn)
	_conn.connect("connected", self, "_on_connected")
	_conn.connect("disconnected", self, "_on_disconnected")
	_conn.connect("stanza_received", self, "_on_stanza")
	print("SPIKE: conectando %s vía %s:%d..." % [_jid, _host, _port])
	_conn.open(_jid, _pass, _host, _port, _cafile)

func _advance(now_ms: int) -> void:
	if _joined_ms == 0:
		# Sin respuesta de disco#info, unirse igual (fallback por convención).
		if _connected_ms > 0 and now_ms - _connected_ms > 4000 and not _join_sent:
			_join()
		return
	var elapsed = now_ms - _joined_ms
	if not _sent and elapsed > 1500:
		_sent = true
		var mid = "spike-%d" % now_ms
		_conn.send(Muc.build_groupchat(_room, "hola sala desde el spike", mid, mid).to_xml())
		print("SPIKE: groupchat enviado id=%s" % mid)
	elif _sent and not _left and elapsed > 3500:
		_left = true
		print("SPIKE: ocupantes=%s" % str(Muc.occupant_nicks(_occupants)))
		_conn.send(Muc.build_leave(_room, _nick).to_xml())
		print("SPIKE: leave enviado")
	elif _left and elapsed > 5000:
		_final = "ok"

func _on_connected(p_bound: String) -> void:
	_bound = p_bound
	_connected_ms = OS.get_ticks_msec()
	print("SPIKE: conectado como %s" % p_bound)
	_conn.send(Stanza.new("presence").to_xml())
	_conn.send(Media.build_disco_items("spike-disco", _domain).to_xml())
	print("SPIKE: disco#items a %s" % _domain)

func _join() -> void:
	_join_sent = true
	print("SPIKE: join %s/%s" % [_room, _nick])
	_conn.send(Muc.build_join(_room, _nick, 20).to_xml())

func _on_stanza(p_xml: String) -> void:
	var s = Stanza.parse(p_xml)
	if s == null:
		return
	if s.name == "iq":
		var iq_id = s.get_attr("id", "")
		if iq_id == "spike-disco":
			var items = Media.parse_disco_items(s)
			print("SPIKE: disco items=%s" % str(items))
			for j in items:
				if str(j).find("conference") >= 0:
					_conference = str(j)
			_conn.send(Media.build_disco_info("spike-info", _conference).to_xml())
			print("SPIKE: disco#info a %s" % _conference)
		elif iq_id == "spike-info":
			print("SPIKE: disco#info result raw=%s" % s.to_xml())
			if not _join_sent:
				_join()
	elif s.name == "presence":
		_on_presence(s, p_xml)
	elif s.name == "message":
		_on_message(s, p_xml)

func _on_presence(s, p_xml: String) -> void:
	var full = s.get_attr("from", "")
	if full.find("/") < 0:
		return
	if full.find(_conference + "/") < 0:
		return
	var parsed = Muc.parse_presence(s)
	if parsed["is_self"] and not parsed["unavailable"] and not _joined:
		_joined = true
		_joined_ms = OS.get_ticks_msec()
		print("SPIKE: JOINED room=%s nick=%s codes=%s" % [parsed["room"], parsed["nick"], str(parsed["status_codes"])])
	Muc.apply_presence(_occupants, parsed)
	print("SPIKE: presence %s unavailable=%s self=%s affiliation=%s role=%s occ_jid=%s codes=%s raw=%s" % [
		full, str(parsed["unavailable"]), str(parsed["is_self"]), parsed["affiliation"], parsed["role"], parsed["occupant_jid"], str(parsed["status_codes"]), p_xml
	])

func _on_message(s, p_xml: String) -> void:
	if s.get_attr("type", "") != "groupchat":
		return
	var body_node = s.get_child("body")
	var body = body_node.get_text() if body_node != null else ""
	if body.find("spike") >= 0:
		_echo = true
	print("SPIKE: groupchat from=%s id=%s body=%s raw=%s" % [s.get_attr("from", ""), s.get_attr("id", ""), body, p_xml])

func _on_disconnected(p_error: int) -> void:
	if _final == "":
		_final = "desconectado error=%d" % p_error

func _report() -> void:
	print("SPIKE RESULT: bound=%s conference=%s room=%s joined=%s sent=%s echo=%s occupants=%s final=%s" % [
		_bound, _conference, _room, str(_joined), str(_sent), str(_echo), str(Muc.occupant_nicks(_occupants)), _final
	])
