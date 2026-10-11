extends SceneTree

# Prueba end-to-end de OMEMO contra un servidor real (Prosody). NO es parte de
# la suite. Usa las credenciales guardadas (user://account.json) o el entorno.
#
# Pasos:
#   1. Conectar (TLS + SASL) y publicar device-list + bundle propios por PEP.
#   2. Pedir la lista/bundle propios al servidor (round-trip de PEP).
#   3. Enviarse un mensaje CIFRADO a sí mismo y descifrarlo al recibirlo: valida
#      X3DH + Double Ratchet + payload + SCE sobre el servidor real.
#   4. Si XAT_OMEMO_PEER (por defecto operator@…) publica bundle, mandarle un
#      mensaje cifrado a ver si responde.
#
# Variables: XAT_E2E_JID/PASS/HOST/PORT/CAFILE, XAT_OMEMO_PEER, XAT_OMEMO_SECONDS.

const Session = preload("res://addons/xat_xmpp/xmpp/session.gd")

var _s = null
var _started := false
var _t0 := 0
var _budget := 45000
var _peer := ""
var _own_bare := ""
var _own_dev := -1
var _self_sent := false
var _self_body := ""
var _self_ok := false
var _peer_sent := false
var _peer_ok := false
var _peer_devs := []
var _logs := []
var _reported := false

func _idle(_d: float) -> bool:
	if not _started:
		_start()
		return false
	if _reported:
		quit()
		return true
	_tick()
	if (OS.get_ticks_msec() - _t0 > _budget) or (_self_ok and _peer_ok):
		_report()
		quit()
		return true
	return false

func _start() -> void:
	_started = true
	_t0 = OS.get_ticks_msec()
	var secs = int(OS.get_environment("XAT_OMEMO_SECONDS"))
	if secs > 0:
		_budget = secs * 1000
	var cfg = load("res://addons/xat_xmpp/xmpp/credentials.gd").new().load_with_env("user://account.json")
	var jid = OS.get_environment("XAT_E2E_JID")
	if jid == "":
		jid = str(cfg.get("jid", ""))
	var p = OS.get_environment("XAT_E2E_PASS")
	if p == "":
		p = str(cfg.get("password", cfg.get("pass", "")))
	var host = OS.get_environment("XAT_E2E_HOST")
	if host == "":
		host = str(cfg.get("host", ""))
	var port = int(OS.get_environment("XAT_E2E_PORT"))
	if port <= 0:
		port = int(cfg.get("port", 5222))
	var caf = OS.get_environment("XAT_E2E_CAFILE")
	if caf == "":
		caf = str(cfg.get("cafile", "/etc/ssl/certs/ca-certificates.crt"))
	_peer = OS.get_environment("XAT_OMEMO_PEER")
	if _peer == "":
		_peer = "operator@hablar.fuentelibre.org"
	_s = Session.new()
	_s.name = "S"
	get_root().add_child(_s)
	_s.connect("state_changed", self, "_on_state")
	_s.connect("message_received", self, "_on_msg")
	_s.connect("log_message", self, "_on_log")
	print("OMEMO-E2E: conectando %s vía %s:%d (peer %s)" % [jid, host, port, _peer])
	_s.connect_account(jid, p, host, port, caf)

func _on_state(p_state: int) -> void:
	if p_state == 2: # State.CONNECTED
		_own_bare = _s._bare
		_own_dev = _s.omemo_device_id()
		print("OMEMO-E2E: conectado como %s; device propio=%d omemo=%s" % [_own_bare, _own_dev, str(_s.omemo_available())])
		# Round-trip de PEP: leer nuestros propios items.
		_s.request_omemo_devices(_own_bare)
		_s.request_omemo_devices(_peer)

func _tick() -> void:
	if _own_dev < 0:
		return
	# Enviarse un cifrado a sí mismo una vez que el servidor devolvió nuestro bundle.
	if not _self_sent and not _s.omemo_peer_devices(_own_bare).empty():
		_self_sent = true
		_self_body = "OMEMO e2e self %d" % OS.get_ticks_msec()
		var rc = _s.send_message(_own_bare, _self_body)
		print("OMEMO-E2E: self-encrypt -> %s (rc=%d)" % [_self_body, rc])
	# Intentar con el peer si publica dispositivos.
	if not _peer_sent:
		var devs = _s.omemo_peer_devices(_peer)
		if not devs.empty():
			_peer_sent = true
			_peer_devs = devs
			var rc2 = _s.send_message(_peer, "OMEMO e2e desde xat (%d)" % OS.get_ticks_msec())
			print("OMEMO-E2E: peer-encrypt -> %s devs=%s rc=%d" % [_peer, str(devs), rc2])

func _on_msg(p_rec) -> void:
	var body = str(p_rec.get("body", ""))
	if _self_body != "" and body == _self_body:
		_self_ok = true
		print("OMEMO-E2E: SELF OK (descifrado el propio mensaje)")
	elif _peer != "" and str(p_rec.get("from", "")).begins_with(_peer):
		_peer_ok = true
		print("OMEMO-E2E: PEER REPLAY encrypted=%s body=%s" % [str(p_rec.get("encrypted", false)), body])

func _on_log(_level: int, p_msg: String) -> void:
	var low = p_msg.to_lower()
	if low.find("error") >= 0 or low.find("fail") >= 0 or low.find("not-authorized") >= 0:
		_logs.append(p_msg)

func _report() -> void:
	_reported = true
	print("OMEMO-E2E RESULT:")
	print("  self_publish_roundtrip=%s (dispositivos propios vistos=%s)" % [str(not _s.omemo_peer_devices(_own_bare).empty()), str(_s.omemo_peer_devices(_own_bare))])
	print("  self_encrypt_roundtrip=%s" % str(_self_ok))
	print("  peer=%s peer_devices=%s peer_reply=%s" % [_peer, str(_peer_devs), str(_peer_ok)])
	if not _logs.empty():
		print("  logs: %s" % str(_logs.slice(0, 5)))
	if _self_ok:
		print("OMEMO_E2E_SELF_OK")