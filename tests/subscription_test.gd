extends SceneTree

# Contactos y suscripciones de presencia: builders de stanza, parseo de
# solicitudes, roster push y API de la sesión (con transporte falso).

var _fail := 0

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
	var Subscription = load("res://addons/xat_xmpp/xmpp/subscription.gd")
	var Roster = load("res://addons/xat_xmpp/xmpp/roster.gd")
	var Presence = load("res://addons/xat_xmpp/xmpp/presence.gd")
	var Session = load("res://addons/xat_xmpp/xmpp/session.gd")

	# --- Subscription: clasificación y builders ---
	check(Subscription.is_subscription_type("subscribe"), "subscribe es suscripción")
	check(Subscription.is_subscription_type("unsubscribed"), "unsubscribed es suscripción")
	check(not Subscription.is_subscription_type(""), "presencia normal no es suscripción")
	check(not Subscription.is_subscription_type("unavailable"), "unavailable no es suscripción")

	var sub = Subscription.build_presence("a@h", Subscription.SUBSCRIBE).to_xml()
	check(sub == '<presence to="a@h" type="subscribe"/>', "build subscribe")

	var req = Subscription.request_from(Stanza.parse('<presence from="a@h/res" type="subscribe"><status>hola</status></presence>'))
	check(req.get("jid", "") == "a@h" and req.get("status", "") == "hola", "parse solicitud")
	check(Subscription.request_from(Stanza.parse('<presence from="a@h" type="subscribed"/>')).empty(), "subscribed no es solicitud")
	check(Subscription.request_from(Stanza.parse('<message from="a@h"/>')).empty(), "message no es solicitud")

	# --- Roster: builders ---
	var set_iq = Roster.build_set_item("r1", "a@h", "Ana", ["Amigas"])
	var set_xml = set_iq.to_xml()
	check(set_xml.find('type="set"') >= 0 and set_xml.find('xmlns="jabber:iq:roster"') >= 0, "set item: iq/query")
	check(set_xml.find('jid="a@h"') >= 0 and set_xml.find('name="Ana"') >= 0 and set_xml.find("<group>Amigas</group>") >= 0, "set item: item/grupo")

	var rem_xml = Roster.build_remove_item("r2", "a@h").to_xml()
	check(rem_xml.find('subscription="remove"') >= 0 and rem_xml.find('jid="a@h"') >= 0, "remove item")

	var ack = Roster.build_push_result("x1", "h").to_xml()
	check(ack == '<iq type="result" id="x1" to="h"/>', "ack de roster push")

	# --- Roster: push de baja borra el item ---
	var r = Roster.new()
	r.set_item("a@h", "Ana", "both", [])
	r.apply_roster_result(Stanza.parse('<iq type="set"><query xmlns="jabber:iq:roster"><item jid="a@h" subscription="remove"/></query></iq>'))
	check(r.get_item("a@h") == null, "push remove borra el item")

	# --- Presencia: remove_bare ---
	var pm = Presence.new()
	pm.update("a@h/uno", "", "", 0, "")
	pm.update("a@h/dos", "", "", 0, "")
	pm.update("b@h/uno", "", "", 0, "")
	check(pm.is_online("a@h") and pm.is_online("b@h"), "dos bares online")
	pm.remove_bare("a@h")
	check(not pm.is_online("a@h") and pm.is_online("b@h"), "remove_bare sólo deja caer a@h")

	# --- Sesión con transporte falso ---
	var session = Session.new()
	session.name = "Session"
	get_root().add_child(session)
	var fake = FakeTransport.new()
	session._transport = fake
	session.state = Session.State.CONNECTED

	# Alta de contacto: roster set + presencia subscribe.
	check(session.add_contact("nueva@h", "Nueva") == 0, "add_contact rc")
	check(fake.sent.size() == 2, "add_contact envía 2 stanzas")
	check(fake.sent[0].find('jabber:iq:roster') >= 0 and fake.sent[0].find('name="Nueva"') >= 0, "add_contact: roster set con nombre")
	check(fake.sent[1].find('type="subscribe"') >= 0 and fake.sent[1].find('to="nueva@h"') >= 0, "add_contact: pide suscripción")
	check(session.add_contact("sin-arroba") == -2, "add_contact rechaza JID inválido")

	# Aceptar solicitud: subscribed + subscribe + roster set.
	fake.sent.clear()
	check(session.approve_subscription("pide@h") == 0, "approve rc")
	check(fake.sent.size() == 3, "approve envía 3 stanzas")
	check(fake.sent[0].find('type="subscribed"') >= 0, "approve autoriza")
	check(fake.sent[1].find('type="subscribe"') >= 0, "approve pide presencia")

	# Rechazar: sólo unsubscribed.
	fake.sent.clear()
	check(session.deny_subscription("pide@h") == 0, "deny rc")
	check(fake.sent.size() == 1 and fake.sent[0].find('type="unsubscribed"') >= 0, "deny envía unsubscribed")

	# Baja: remove + unsubscribe + unsubscribed.
	fake.sent.clear()
	check(session.remove_contact("pide@h") == 0, "remove rc")
	check(fake.sent.size() == 3 and fake.sent[0].find('subscription="remove"') >= 0, "remove quita y corta")

	# Señal de solicitud entrante; no entra al modelo de presencia.
	session.connect("subscription_request", self, "_on_subscription")
	session._on_presence(Stanza.parse('<presence from="quiere@h/x" type="subscribe"><status>hey</status></presence>'))
	check(_last_req.get("jid", "") == "quiere@h" and _last_req.get("status", "") == "hey", "señal subscription_request")
	check(not session.presence_model.is_online("quiere@h"), "solicitud no es presencia disponible")

	# Roster push aplicado y confirmado.
	var before = fake.sent.size()
	session._on_iq(Stanza.parse('<iq type="set" id="p1" from="h"><query xmlns="jabber:iq:roster"><item jid="otro@h" name="Otro" subscription="both"/></query></iq>'))
	check(session.roster_model.get_item("otro@h") != null, "roster push aplicado")
	check(fake.sent.size() == before + 1 and fake.sent.back().find('type="result"') >= 0, "roster push confirmado")

	session.free()
	if _fail == 0:
		print("SUBSCRIPTION_CHECK_OK")
	quit()

var _last_req := {}

func _on_subscription(p_bare: String, p_status: String) -> void:
	_last_req = {"jid": p_bare, "status": p_status}

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
