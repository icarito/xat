extends SceneTree

# Sonda de registro XEP-0077 contra un servidor real (no es parte de la suite).
# Verifica el flujo pre-auth completo: abre el stream, negocia STARTTLS, manda
# el IQ de registro y muestra la respuesta del servidor.
#
# Variables: XAT_REG_JID, XAT_REG_HOST, XAT_REG_SECONDS.
# Correr con XAT_AUTOCONNECT=0 para no conectar además la cuenta guardada.

const Session = preload("res://addons/xat_xmpp/xmpp/session.gd")

var _s = null
var _started := false
var _done := false
var _t0 := 0
var _budget := 20000

func _idle(_d: float) -> bool:
	if not _started:
		_start()
		return false
	if _done:
		quit()
		return true
	if OS.get_ticks_msec() - _t0 > _budget:
		print("REGISTER_TIMEOUT")
		quit()
		return true
	return false

func _start() -> void:
	_started = true
	_t0 = OS.get_ticks_msec()
	var secs = int(OS.get_environment("XAT_REG_SECONDS"))
	if secs > 0:
		_budget = secs * 1000
	var jid = OS.get_environment("XAT_REG_JID")
	if jid == "":
		jid = "xat-regcheck-9f3a@hablar.fuentelibre.org"
	var host = OS.get_environment("XAT_REG_HOST")
	if host == "":
		host = "hablar.fuentelibre.org"
	_s = Session.new()
	_s.name = "S"
	get_root().add_child(_s)
	_s.connect("register_result", self, "_on_result")
	var rc = _s.register_account(jid, "probando-123456", host, 5222, "")
	print("REGISTER_START rc=%d jid=%s host=%s" % [rc, jid, host])

func _on_result(ok: bool, msg: String) -> void:
	_done = true
	if ok:
		print("REGISTER_RESULT ok=true")
	else:
		print("REGISTER_RESULT ok=false msg=%s" % msg)
