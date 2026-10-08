extends SceneTree

# Sonda end-to-end autenticada contra un servidor real (Prosody/gateway). NO es
# parte de la suite: requiere credenciales. Ejercita conexión -> roster ->
# mensaje -> (recibo/MAM) y resume un conteo.
#
# Variables de entorno:
#   XAT_E2E_JID     (requerido) ej. agente@hablar.fuentelibre.org
#   XAT_E2E_PASS    (requerido)
#   XAT_E2E_HOST    (opcional) default: dominio del JID
#   XAT_E2E_PORT    (opcional) default 5222
#   XAT_E2E_CAFILE  (opcional) default /etc/ssl/certs/ca-certificates.crt
#   XAT_E2E_PEER    (opcional) JID al que mandar un mensaje de prueba
#   XAT_E2E_SECONDS (opcional) presupuesto en segundos, default 30
#
# Uso:
#   XAT_E2E_JID=... XAT_E2E_PASS=... bin/godot-xat --no-window --path app \
#     -s "$PWD/tools/e2e_probe.gd"

const Stanza = preload("res://addons/xat_xmpp/xmpp/stanza.gd")

var _conn = null
var _started := false
var _start_ms := 0
var _budget_ms := 30000
var _jid := ""
var _pass := ""
var _host := ""
var _port := 5222
var _cafile := ""
var _peer := ""
var _bound := ""
var _roster_items := 0
var _messages := 0
var _receipts := 0
var _presences := 0
var _sent := false
var _final := ""

func _idle(_delta: float) -> bool:
	if not _started:
		_start()
		return false
	if _final != "" or OS.get_ticks_msec() - _start_ms > _budget_ms:
		_report()
		quit()
		return true
	return false

func _start() -> void:
	_started = true
	_start_ms = OS.get_ticks_msec()
	_jid = OS.get_environment("XAT_E2E_JID")
	_pass = OS.get_environment("XAT_E2E_PASS")
	_host = OS.get_environment("XAT_E2E_HOST")
	_port = int(OS.get_environment("XAT_E2E_PORT"))
	if _port <= 0:
		_port = 5222
	_cafile = OS.get_environment("XAT_E2E_CAFILE")
	if _cafile == "":
		_cafile = "/etc/ssl/certs/ca-certificates.crt"
	_peer = OS.get_environment("XAT_E2E_PEER")
	var secs = int(OS.get_environment("XAT_E2E_SECONDS"))
	if secs > 0:
		_budget_ms = secs * 1000

	if _jid == "" or _pass == "":
		_final = "faltan XAT_E2E_JID / XAT_E2E_PASS"
		return
	if not ClassDB.class_exists("XmppConnection"):
		_final = "sin módulo nativo"
		return
	_conn = ClassDB.instance("XmppConnection")
	get_root().add_child(_conn)
	_conn.connect("connected", self, "_on_connected")
	_conn.connect("disconnected", self, "_on_disconnected")
	_conn.connect("stanza_received", self, "_on_stanza")
	if _host == "":
		var at = _jid.find("@")
		_host = _jid.substr(at + 1) if at >= 0 else _jid
	print("E2E: conectando %s vía %s:%d ..." % [_jid, _host, _port])
	_conn.open(_jid, _pass, _host, _port, _cafile)

func _on_connected(p_bound: String) -> void:
	_bound = p_bound
	print("E2E: conectado como %s" % p_bound)
	# Roster.
	var iq = Stanza.new("iq")
	iq.set_attr("type", "get")
	iq.set_attr("id", "e2e-roster")
	var q = Stanza.new("query")
	q.set_attr("xmlns", "jabber:iq:roster")
	iq.add_child_stanza(q)
	_conn.send(iq.to_xml())

func _on_stanza(p_xml: String) -> void:
	var s = Stanza.parse(p_xml)
	if s == null:
		return
	match s.name:
		"iq":
			var q = s.get_child("query", "jabber:iq:roster")
			if q != null:
				_roster_items = q.get_children("item").size()
				print("E2E: roster con %d items" % _roster_items)
				if _peer != "" and not _sent:
					_send_test_message()
		"message":
			_messages += 1
			if s.get_child("received", "urn:xmpp:receipts") != null:
				_receipts += 1
		"presence":
			_presences += 1

func _send_test_message() -> void:
	_sent = true
	var m = Stanza.new("message")
	m.set_attr("to", _peer)
	m.set_attr("type", "chat")
	m.set_attr("id", "e2e-msg")
	var body = Stanza.new("body")
	body.append_text("xat e2e probe")
	m.add_child_stanza(body)
	var req = Stanza.new("request")
	req.set_attr("xmlns", "urn:xmpp:receipts")
	m.add_child_stanza(req)
	_conn.send(m.to_xml())
	print("E2E: mensaje enviado a %s" % _peer)

func _on_disconnected(p_error: int) -> void:
	if _final == "":
		_final = "desconectado error=%d" % p_error

func _report() -> void:
	print("E2E RESULT: bound=%s roster=%d presences=%d messages=%d receipts=%d sent=%s final=%s" % [
		_bound, _roster_items, _presences, _messages, _receipts, str(_sent), _final
	])
	if _bound != "":
		print("E2E: conexión+auth OK (roster recibido=%s)" % (_roster_items > 0))
	if _final != "":
		print("E2E: final=%s" % _final)
