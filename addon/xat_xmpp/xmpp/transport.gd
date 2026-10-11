extends Node

# Adaptador de transporte sobre el nodo nativo `XmppConnection` (módulo xmpp).
# El nativo corre libstrophe en su propio hilo y emite señales al hilo
# principal; acá sólo normalizamos nombres y exponemos una API estable para el
# resto del addon. Si el binario no trae el módulo, `available()` es false y
# `open()` devuelve error (así los tests de parsers corren en cualquier 3.6).

signal stanza(xml)
signal connected(bound_jid)
signal disconnected(error)
signal register_result(ok, message)
signal log_message(level, msg)

var _impl = null
var _wired := false

func _init() -> void:
	if ClassDB.class_exists("XmppConnection"):
		_impl = ClassDB.instance("XmppConnection")

func _ready() -> void:
	_wire()

func _wire() -> void:
	if _wired or _impl == null:
		return
	_wired = true
	add_child(_impl)
	_impl.connect("stanza_received", self, "_on_stanza")
	_impl.connect("connected", self, "_on_connected")
	_impl.connect("disconnected", self, "_on_disconnected")
	_impl.connect("log", self, "_on_log")
	if _impl.has_signal("register_result"):
		_impl.connect("register_result", self, "_on_register_result")

func available() -> bool:
	return _impl != null

# Devuelve 0 si arrancó el hilo de conexión; los errores de red/auth llegan
# por la señal `disconnected`.
func open(jid: String, password: String, host: String = "", port: int = 5222, cafile: String = "") -> int:
	if _impl == null:
		return -1
	if not is_inside_tree():
		_wire()
	elif not _wired:
		_wire()
	return _impl.open(jid, password, host, port, cafile)

func close() -> void:
	if _impl != null:
		_impl.close()

# XEP-0077: registro en banda (pre-auth). El resultado llega por
# `register_result(ok, message)`.
func register_account(jid: String, password: String, host: String = "", port: int = 5222, cafile: String = "") -> int:
	if _impl == null:
		return -1
	if not is_inside_tree():
		_wire()
	elif not _wired:
		_wire()
	if not _impl.has_method("register_account"):
		return -2
	return _impl.register_account(jid, password, host, port, cafile)

func send(xml: String) -> int:
	if _impl == null:
		return -1
	return _impl.send(xml)

func is_open() -> bool:
	return _impl != null and _impl.is_open()

func _on_stanza(xml: String) -> void:
	emit_signal("stanza", xml)

func _on_connected(bound_jid: String) -> void:
	emit_signal("connected", bound_jid)

func _on_disconnected(error: int) -> void:
	emit_signal("disconnected", error)

func _on_register_result(ok: bool, message: String) -> void:
	emit_signal("register_result", ok, message)

func _on_log(level: int, msg: String) -> void:
	emit_signal("log_message", level, msg)
