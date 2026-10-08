extends SceneTree

# Sonda de integración TLS/SASL contra el gateway real. NO forma parte de la
# suite (requiere red). Objetivo: validar que el backend mbedTLS completa el
# handshake y la verificación de hostname; luego libstrophe llega a SASL y
# falla por credenciales inválidas (esperado). Si el error es de certificado,
# el backend está mal.
#
# Uso:
#   bin/godot-xat --no-window --path app -s "$PWD/tools/tls_probe.gd"

const HOST := "hablar.fuentelibre.org"
const PORT := 5222
const JID := "xat-probe@hablar.fuentelibre.org"
const PASS := "credencial-invalida-de-sonda"
const CAFILE := "/etc/ssl/certs/ca-certificates.crt"
var _conn = null
var _started := false
var _frames := 0
var _logs := []
var _result := "sin resultado"
var _done := false

func _idle(_delta: float) -> bool:
	_frames += 1
	if not _started:
		_start()
		return false
	if _done or _frames > 900: # ~15 s a 60 fps
		_report()
		quit()
		return true
	return false

func _start() -> void:
	_started = true
	if not ClassDB.class_exists("XmppConnection"):
		_result = "sin módulo nativo"
		_done = true
		return
	_conn = ClassDB.instance("XmppConnection")
	get_root().add_child(_conn)
	_conn.connect("connected", self, "_on_connected")
	_conn.connect("disconnected", self, "_on_disconnected")
	_conn.connect("log", self, "_on_log")
	print("PROBE: conectando a %s:%d ..." % [HOST, PORT])
	var cafile = OS.get_environment("XAT_PROBE_CAFILE")
	if cafile == "":
		cafile = CAFILE
	_conn.open(JID, PASS, HOST, PORT, cafile)

func _on_connected(p_jid: String) -> void:
	_result = "CONECTADO (inesperado con pass inválida): %s" % p_jid
	_done = true

func _on_disconnected(p_error: int) -> void:
	_result = "desconectado error=%d" % p_error
	_done = true

func _on_log(_level: int, p_msg: String) -> void:
	_logs.append(p_msg)

func _report() -> void:
	print("PROBE RESULT: %s" % _result)
	var tls_fail := false
	var reached_sasl := false
	var auth_rejected := false
	for m in _logs:
		var low = m.to_lower()
		if low.find("certificate verification failed") >= 0 or low.find("x509") >= 0 or low.find("bad certificate") >= 0 or low.find("-0x") >= 0:
			tls_fail = true
		if low.find("sasl plain") >= 0 or low.find("sasl") >= 0:
			reached_sasl = true
		if low.find("not-authorized") >= 0 or low.find("auth failed") >= 0:
			auth_rejected = true
	print("PROBE: logs=%d, tls_fail=%s, reached_sasl=%s, auth_rejected=%s" % [_logs.size(), str(tls_fail), str(reached_sasl), str(auth_rejected)])
	if reached_sasl and auth_rejected and not tls_fail:
		print("PROBE: TLS OK (handshake+verify); SASL alcanzado y rechazado por credencial inválida (esperado)")
	elif tls_fail:
		print("PROBE: FALLO DE TLS")
	else:
		print("PROBE: resultado ambiguo (revisar logs)")
