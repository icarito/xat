extends SceneTree

# OMEMO a través de session.gd: send_message cifra, el otro extremo descifra al
# recibir la stanza. Con transporte falso y SQLite en memoria (sin _ready).

var _fail := 0
var _last := {}

func _init():
	if not ClassDB.class_exists("SQLiteBinding") or not ClassDB.class_exists("XatOmemo"):
		print("FAIL: faltan clases nativas")
		OS.exit_code = 1
		quit()
		return
	var Session = load("res://addons/xat_xmpp/xmpp/session.gd")
	var Store = load("res://addons/xat_xmpp/xmpp/store.gd")
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")
	var bare_a := "alice@h"
	var bare_b := "bob@h"

	var s_a = Session.new()
	var s_b = Session.new()
	_setup(s_a, Store, bare_a)
	_setup(s_b, Store, bare_b)
	check(s_a.omemo_available() and s_b.omemo_available(), "OMEMO habilitado en ambas sesiones")

	# Descubrimiento (PEP): cada lado conoce lista y bundle del otro.
	s_a._omemo_engine.set_peer_devices(bare_b, [s_b.omemo_device_id()])
	s_a._omemo_engine.set_peer_bundle(bare_b, s_b.omemo_device_id(), s_b._omemo_device.bundle())
	s_b._omemo_engine.set_peer_devices(bare_a, [s_a.omemo_device_id()])
	s_b._omemo_engine.set_peer_bundle(bare_a, s_a.omemo_device_id(), s_a._omemo_device.bundle())

	s_b.connect("message_received", self, "_on_msg")

	# A -> B.
	var rc = s_a.send_message(bare_b, "hola desde A")
	var fake_a = s_a._transport
	check(rc == 0 and fake_a.sent.size() == 1, "A envía una stanza")
	var enc_a = _encrypted_of(fake_a.sent)
	check(enc_a != "" and enc_a.find("urn:xmpp:omemo:2") >= 0, "la stanza va cifrada")
	var el_a = Stanza.parse(enc_a)
	el_a.set_attr("from", bare_a)
	s_b._on_stanza(el_a.to_xml())
	check(_last.get("body") == "hola desde A" and _last.get("encrypted", false), "B descifra por session.gd")

	# B -> A (respuesta). B pudo haber mandado antes un recibo; tomar la cifrada.
	var fake_b = s_b._transport
	s_b.send_message(bare_a, "respuesta de B")
	s_a.connect("message_received", self, "_on_msg")
	var el_b = Stanza.parse(_encrypted_of(fake_b.sent))
	el_b.set_attr("from", bare_b)
	s_a._on_stanza(el_b.to_xml())
	check(_last.get("body") == "respuesta de B", "A descifra la respuesta")

	s_a.free()
	s_b.free()
	if _fail == 0:
		print("SESSION_OMEMO_CHECK_OK")
	quit()

func _setup(p_session, p_store_script, p_bare: String) -> void:
	var st = p_store_script.new()
	st.open(":memory:")
	p_session.store = st
	p_session._bare = p_bare
	p_session._transport = FakeTransport.new()
	p_session.enable_omemo()

func _on_msg(p_rec) -> void:
	_last = p_rec

func _encrypted_of(p_sent: Array) -> String:
	for x in p_sent:
		if str(x).find("urn:xmpp:omemo:2") >= 0:
			return str(x)
	return ""

func check(p_ok: bool, p_label: String) -> void:
	if p_ok:
		print("ok %s" % p_label)
	else:
		_fail += 1
		print("FAIL %s" % p_label)
		OS.exit_code = 1

class FakeTransport:
	var sent = []
	func send(p_xml):
		sent.append(p_xml)
		return 0
