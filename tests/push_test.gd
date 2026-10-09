extends SceneTree

# XEP-0357 (push): builders del IQ de registro, parseo de error/disco, y la API
# de la sesión (con transporte falso). Restaura el store de push al terminar.

var _fail := 0
var _last_push := {}

class FakeTransport:
	extends Node
	var sent := []
	func send(xml: String) -> int:
		sent.append(xml)
		return 0
	func available() -> bool:
		return true

func _init():
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")
	var Push = load("res://addons/xat_xmpp/xmpp/push.gd")
	var Session = load("res://addons/xat_xmpp/xmpp/session.gd")

	# Backup del store real para no pisarlo.
	var file = File.new()
	var had = file.file_exists(Push.STORE_PATH)
	var backup := ""
	if had:
		file.open(Push.STORE_PATH, File.READ)
		backup = file.get_as_text()
		file.close()

	# --- Builders ---
	var en = Push.build_enable("e1", "push.h", "tok123").to_xml()
	check(en.find('type="set"') >= 0 and en.find('<enable xmlns="urn:xmpp:push:0"') >= 0, "enable: iq/enable ns")
	check(en.find('jid="push.h"') >= 0 and en.find('node="tok123"') >= 0, "enable: jid y node")
	check(en.find("jabber:x:data") < 0, "enable sin options no manda <x>")

	var eno = Push.build_enable("e2", "push.h", "tok", {"secret": "s3cr3t"}).to_xml()
	check(eno.find("pubsub#publish-options") >= 0 and eno.find("<value>s3cr3t</value>") >= 0, "enable con publish-options")

	# Filtros del servidor (Tigase), activados por el cliente.
	var enf = Push.build_enable("e3", "fcm-push.h", "tok", {}, {
		"ignore_unknown": true,
		"muted": ["m@h"],
		"groupchat": [{"jid": "sala@conf.h", "when": "mentioned", "nick": "yo"}],
	}).to_xml()
	check(enf.find("tigase:push:filter:ignore-unknown:0") >= 0, "enable: filtro ignore-unknown")
	check(enf.find("tigase:push:filter:muted:0") >= 0 and enf.find('<item jid="m@h"/>') >= 0, "enable: filtro muted")
	check(enf.find("tigase:push:filter:groupchat:0") >= 0 and enf.find('allow="mentioned"') >= 0 and enf.find('nick="yo"') >= 0, "enable: filtro groupchat")
	var enq = Push.build_enable("e4", "push.h", "tok").to_xml()
	check(enq.find("tigase:push:filter") < 0, "enable sin filtros no manda filtros")

	var dis = Push.build_disable("d1", "push.h", "tok").to_xml()
	check(dis.find('<disable xmlns="urn:xmpp:push:0"') >= 0 and dis.find('jid="push.h"') >= 0, "disable: jid/node")
	var disall = Push.build_disable("d2").to_xml()
	check(disall == '<iq type="set" id="d2"><disable xmlns="urn:xmpp:push:0"/></iq>', "disable all")

	# --- error_condition / service_from_disco ---
	check(Push.error_condition(Stanza.parse('<iq type="error"><error type="cancel"><not-allowed xmlns="urn:ietf:params:xml:ns:xmpp-stanzas"/></error></iq>')) == "not-allowed", "error_condition")
	check(Push.error_condition(Stanza.parse('<iq type="error"><error type="cancel"><text>x</text></error></iq>')) == "", "error_condition vacío")
	check(Push.service_from_disco(Stanza.parse('<iq from="push.h"><query xmlns="http://jabber.org/protocol/disco#info"><identity category="pubsub" type="push"/></query></iq>')) == "push.h", "service_from_disco")

	# --- Setting por proveedor del SO ---
	check(Push.setting_key("iOS") == "xat/push_service_ios", "setting_key iOS")
	check(Push.setting_key("Android") == "xat/push_service_android", "setting_key Android")
	check(Push.setting_key("Linux") == "xat/push_service_android", "setting_key default -> Android")

	# --- Persistencia ---
	Push.save(Push.STORE_PATH, "push.h", "tok")
	var loaded = Push.load(Push.STORE_PATH)
	check(loaded.get("service", "") == "push.h" and loaded.get("node", "") == "tok", "save/load")

	# --- Sesión: enable + resultado ---
	var session = Session.new()
	session.name = "Session"
	get_root().add_child(session)
	var fake = FakeTransport.new()
	session._transport = fake
	session.state = Session.State.CONNECTED
	session.connect("push_registration_changed", self, "_on_push")

	fake.sent.clear()
	check(session.enable_push("push.h", "tokX", {"ignore_unknown": true}) == 0, "enable_push rc")
	check(fake.sent.size() == 1 and fake.sent[0].find('node="tokX"') >= 0, "enable_push envía el IQ")
	check(fake.sent[0].find("tigase:push:filter:ignore-unknown:0") >= 0, "enable_push manda filtros")
	var id = session._push_ctx.keys()[0]
	session._on_iq(Stanza.parse('<iq type="result" id="%s"/>' % id))
	check(session.push_registered() and bool(_last_push.get("registered", false)), "result registra push")

	# --- Sesión: error marca fallido ---
	fake.sent.clear()
	session.enable_push()
	var id2 = session._push_ctx.keys()[0]
	session._on_iq(Stanza.parse('<iq type="error" id="%s"><error type="cancel"><not-allowed xmlns="urn:ietf:params:xml:ns:xmpp-stanzas"/></error></iq>' % id2))
	check(not session.push_registered() and _last_push.get("error", "") == "not-allowed", "error de push")

	# --- Re-registro al conectar ---
	session.configure_push("push.h", "tokZ")
	fake.sent.clear()
	session._on_connected("yo@h/xat")
	var joined = " ".join(fake.sent)
	check(joined.find('node="tokZ"') >= 0, "re-registra al conectar")

	# --- Sin token: no registra ---
	var s2 = Session.new()
	s2.name = "S2"
	get_root().add_child(s2)
	s2._transport = FakeTransport.new()
	s2.state = Session.State.CONNECTED
	s2._push_service = ""
	s2._push_token = ""
	check(s2.enable_push() == -2, "sin token devuelve -2")
	s2.free()

	session.free()

	# Restaurar el store real.
	if had:
		file.open(Push.STORE_PATH, File.WRITE)
		file.store_string(backup)
		file.close()
	else:
		Directory.new().remove(Push.STORE_PATH)

	if _fail == 0:
		print("PUSH_CHECK_OK")
	quit()

func _on_push(p_registered: bool, p_error: String) -> void:
	_last_push = {"registered": p_registered, "error": p_error}

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
