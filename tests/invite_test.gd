extends SceneTree

# Invitaciones a sala: mediada (XEP-0045 §7.8, sin body) y directa (XEP-0249).
# Deben emitir `muc_invite` en cualquiera de sus formas.

var _fail := 0
var _invites := []

func _init():
	var SessionScript = load("res://addons/xat_xmpp/xmpp/session.gd")
	var s = SessionScript.new()
	s.connect("muc_invite", self, "_on_invite")
	var fake = FakeTransport.new()
	s._transport = fake
	s._bare = "me@h"
	s.state = SessionScript.State.CONNECTED

	# Mediada sin atributo type (formato típico del servidor).
	s._on_stanza('<message from="sala@conference.h" to="me@h/x"><x xmlns="http://jabber.org/protocol/muc#user"><invite from="ana@h"><reason>vení</reason></invite></x></message>')
	check(_invites.size() == 1 and _invites[0][0] == "sala@conference.h" and _invites[0][1] == "ana@h" and _invites[0][2] == "vení", "mediada sin type")

	# Mediada type=normal.
	s._on_stanza('<message type="normal" from="sala2@conference.h" to="me@h/x"><x xmlns="http://jabber.org/protocol/muc#user"><invite from="ana@h"/></x></message>')
	check(_invites.size() == 2 and _invites[1][0] == "sala2@conference.h", "mediada type=normal")

	# Directa XEP-0249 sin type.
	s._on_stanza('<message from="ana@h/x" to="me@h/x"><x xmlns="jabber:x:conference" jid="sala3@conference.h" reason="dale"/></message>')
	check(_invites.size() == 3 and _invites[2][0] == "sala3@conference.h" and _invites[2][2] == "dale", "directa 0249 sin type")

	# Directa XEP-0249 type=normal.
	s._on_stanza('<message type="normal" from="ana@h/x" to="me@h/x"><x xmlns="jabber:x:conference" jid="sala4@conference.h"/></message>')
	check(_invites.size() == 4 and _invites[3][0] == "sala4@conference.h", "directa 0249 type=normal")

	# Mediada CON body de cortesía: también es invitación (antes se descartaba).
	s._on_stanza('<message from="sala5@conference.h" to="me@h/x"><body>ana te invita a sala5</body><x xmlns="http://jabber.org/protocol/muc#user"><invite from="ana@h"/></x></message>')
	check(_invites.size() == 5 and _invites[4][0] == "sala5@conference.h", "mediada con body")

	# Invitación reenviada por carbons de otro recurso (antes se perdía).
	s._on_stanza('<message from="me@h" to="me@h/x"><received xmlns="urn:xmpp:carbons:2"><forwarded xmlns="urn:xmpp:forward:0"><message from="sala6@conference.h" to="me@h"><x xmlns="http://jabber.org/protocol/muc#user"><invite from="ana@h"><reason>carbon</reason></invite></x></message></forwarded></received></message>')
	check(_invites.size() == 6 and _invites[5][0] == "sala6@conference.h" and _invites[5][2] == "carbon", "mediada por carbons")

	# Saliente: invitación mediada (la que envía xat al invitar desde una sala).
	fake.sent = []
	s.muc_invite("sala@conference.h", "ana@h", "vení")
	var out = str(fake.sent.back())
	check(out.find('to="sala@conference.h"') >= 0 and out.find("<invite") >= 0 and out.find('to="ana@h"') >= 0 and out.find("<reason>vení</reason>") >= 0, "invitación saliente mediada")

	s.free()
	if _fail == 0:
		print("INVITE_CHECK_OK")
	quit()

func _on_invite(p_room, p_from, p_reason):
	_invites.append([p_room, p_from, p_reason])

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1

class FakeTransport:
	var sent = []
	func send(p_xml):
		sent.append(p_xml)
