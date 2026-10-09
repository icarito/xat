extends SceneTree

# Sesión MUC: la presencia de sala no contamina `presence_model`; los eventos
# propios (join/left/subject/invite) se emiten; los groupchat se enrutan por la
# sala con dedupe del eco propio. Sin _ready: no toca la red real.

var _fail := 0
var _joined := []
var _left := []
var _subjects := []
var _occupants := 0
var _invites := []
var _msgs := []
var _hist := []
var _errors := []
var _configs := []

func _init():
	var SessionScript = load("res://addons/xat_xmpp/xmpp/session.gd")
	var s = SessionScript.new()
	s.connect("muc_joined", self, "_on_joined")
	s.connect("muc_left", self, "_on_left")
	s.connect("muc_subject", self, "_on_subject")
	s.connect("muc_occupants_changed", self, "_on_occupants")
	s.connect("muc_invite", self, "_on_invite")
	s.connect("message_received", self, "_on_msg")
	s.connect("history_fetched", self, "_on_hist")
	s.connect("muc_error", self, "_on_error")
	s.connect("muc_config_form", self, "_on_config")
	var fake = FakeTransport.new()
	s._transport = fake
	s._bare = "me@h"
	s.state = SessionScript.State.CONNECTED
	if ClassDB.class_exists("SQLiteBinding"):
		var Store = load("res://addons/xat_xmpp/xmpp/store.gd")
		s.store = Store.new()
		s.store.open(":memory:")

	# Unir la sala envía la presencia de join y no toca la presencia de contactos.
	check(s.join_room("sala@conference.h", "me") == 0, "join_room rc=0")
	check(s.is_room("sala@conference.h"), "is_room")
	check(fake.sent.size() == 1 and fake.sent[0].find('to="sala@conference.h/me"') >= 0, "join envía presence a room/nick")
	check(s.room_nick("sala@conference.h") == "me", "room_nick")

	# Presencia propia de sala (110+201): joined, y NO contamina presence_model.
	s._on_stanza('<presence from="sala@conference.h/me" to="me@h/x"><x xmlns="http://jabber.org/protocol/muc#user"><item affiliation="owner" role="moderator" jid="me@h/x"/><status code="201"/><status code="110"/></x></presence>')
	check(_joined == ["sala@conference.h"], "muc_joined")
	check(not s.presence_model.is_online("sala@conference.h"), "presencia de sala NO contamina presence_model")
	check(s.presence_model.best("sala@conference.h") == null, "sala no es contacto online")

	# Crear la sala (201) dispara la config inicial del dueño (desbloquea).
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")
	var getid = ""
	for x in fake.sent:
		if str(x).find('type="get"') >= 0 and str(x).find("muc#owner") >= 0:
			getid = Stanza.parse(str(x)).get_attr("id", "")
	check(getid != "", "403/201: pide config muc#owner")
	var sent_before = fake.sent.size()
	s._on_stanza('<iq type="result" id="%s"><query xmlns="http://jabber.org/protocol/muc#owner"><x xmlns="jabber:x:data" type="form"><field var="FORM_TYPE" type="hidden"><value>http://jabber.org/protocol/muc#roomconfig</value></field><field var="muc#roomconfig_membersonly" type="boolean"><value>1</value></field></x></query></iq>' % getid)
	var submitted = false
	for x in fake.sent:
		if str(x).find('type="set"') >= 0 and str(x).find("muc#owner") >= 0 and str(x).find("muc#roomconfig") >= 0:
			submitted = true
	check(submitted and fake.sent.size() > sent_before, "config inicial reenviada (desbloquea)")

	# Nuestra afiliación/rol propios (para habilitar moderación).
	check(s.muc_affiliation("sala@conference.h") == "owner", "muc_affiliation owner")
	check(s.muc_role("sala@conference.h") == "moderator", "muc_role moderator")
	check(s.muc_is_owner("sala@conference.h") and s.muc_can_moderate("sala@conference.h"), "muc_is_owner/can_moderate")

	# Moderación: afiliación (jid), rol (nick), invitación, tema, destruir.
	fake.sent = []
	s.muc_set_affiliation("sala@conference.h", "joe@h", "member")
	check(fake.sent.back().find('muc#admin') >= 0 and fake.sent.back().find('jid="joe@h" affiliation="member"') >= 0, "muc_set_affiliation")
	s.muc_kick("sala@conference.h", "joe")
	check(fake.sent.back().find('nick="joe" role="none"') >= 0, "muc_kick")
	s.muc_ban("sala@conference.h", "joe@h")
	check(fake.sent.back().find('affiliation="outcast"') >= 0, "muc_ban")
	s.muc_invite("sala@conference.h", "joe@h", "vení")
	check(fake.sent.back().find('to="sala@conference.h"') >= 0 and fake.sent.back().find('<invite to="joe@h">') >= 0, "muc_invite")
	s.muc_set_subject("sala@conference.h", "nuevo tema")
	check(fake.sent.back().find('type="groupchat"') >= 0 and fake.sent.back().find("<subject>nuevo tema</subject>") >= 0, "muc_set_subject")

	# Config para la UI: pedirla emite muc_config_form con el formulario.
	fake.sent = []
	s.muc_request_config("sala@conference.h")
	var reqid = Stanza.parse(fake.sent.back()).get_attr("id", "")
	check(reqid.begins_with("mucowner-"), "muc_request_config envía get")
	s._on_stanza('<iq type="result" id="%s"><query xmlns="http://jabber.org/protocol/muc#owner"><x xmlns="jabber:x:data" type="form"><title>Sala</title><field var="FORM_TYPE" type="hidden"><value>http://jabber.org/protocol/muc#roomconfig</value></field><field var="muc#roomconfig_membersonly" type="boolean" label="Solo miembros"><value>1</value></field></x></query></iq>' % reqid)
	check(_configs.size() == 1 and _configs[0][0] == "sala@conference.h" and _configs[0][1].get("fields").size() == 2, "muc_config_form emitido")

	# Otro ocupante entra.
	s._on_stanza('<presence from="sala@conference.h/ana" to="me@h/x"><x xmlns="http://jabber.org/protocol/muc#user"><item affiliation="member" role="participant" jid="ana@h/p"/></x></presence>')
	check(s.muc_occupants("sala@conference.h").size() == 2, "dos ocupantes")
	check(_occupants >= 1, "muc_occupants_changed")

	# Un contacto normal sí entra al modelo de presencia.
	s._on_stanza('<presence from="joe@h/phone"><show>chat</show><priority>5</priority></presence>')
	check(s.presence_model.is_online("joe@h"), "contacto normal a presence_model")

	# Groupchat entrante: se emite por la sala con muc=true.
	s._on_stanza('<message type="groupchat" from="sala@conference.h/ana" to="me@h/x" id="a1"><body>hola</body></message>')
	check(_msgs.back().get("muc", false) and _msgs.back()["body"] == "hola", "groupchat entrante emitido")
	check(_msgs.back()["direction"] == "in", "groupchat entrante in")

	# Sujeto de sala (groupchat sin body) -> muc_subject y sin burbuja.
	var before = _msgs.size()
	s._on_stanza('<message type="groupchat" from="sala@conference.h" to="me@h/x"><subject>tema nuevo</subject></message>')
	check(_subjects == ["tema nuevo"], "muc_subject")
	check(_msgs.size() == before, "sujeto no es burbuja")
	check(s.room_subject("sala@conference.h") == "tema nuevo", "room_subject guardado")

	# Eco propio: se dedupea contra la fila optimista (por id de stanza).
	var rc = s.send_groupchat("sala@conference.h", "mio")
	check(rc == 0, "send_groupchat rc=0")
	var mid = s.last_sent_id
	check(mid != "", "last_sent_id seteado")
	var seen = _msgs.size()
	s._on_stanza('<message type="groupchat" from="sala@conference.h/me" to="me@h/x" id="%s"><origin-id xmlns="urn:xmpp:sid:0" id="%s"/><body>mio</body></message>' % [mid, mid])
	check(_msgs.size() == seen, "eco propio deduplicado")
	if s.store != null:
		check(s.store.has_request_id("sala@conference.h", mid), "fila optimista guardada")

	# MAM de sala: la query va a la sala SIN `with`; el IQ id es el queryid y el
	# `<fin>` (que en sala puede llegar como <message>) cierra y avisa al main.
	s.load_history("sala@conference.h")
	var miq = Stanza.parse(fake.sent.back())
	check(miq.get_attr("to") == "sala@conference.h", "MAM sala to=room")
	var qid = miq.get_attr("id", "")
	check(qid.begins_with("mam-"), "MAM iq id = queryid")
	var qnode = miq.get_child("query", "urn:xmpp:mam:2")
	check(qnode != null and qnode.get_attr("queryid", "") == qid, "MAM queryid = iq id")
	check(miq.to_xml().find('var="with"') < 0, "MAM sala sin with")
	s._on_stanza('<message from="sala@conference.h" to="me@h/x"><fin xmlns="urn:xmpp:mam:2" queryid="%s" complete="true"/></message>' % qid)
	check(_hist.size() == 1 and _hist[0][0] == "sala@conference.h", "MAM sala fin -> history_fetched")

	# Invitación mediada (la envía la sala; el invitador va en el atributo from).
	s._on_stanza('<message type="chat" from="sala@conference.h" to="me@h/x"><x xmlns="http://jabber.org/protocol/muc#user"><invite from="bot@h"><reason>vení</reason></invite></x></message>')
	check(_invites.size() == 1 and _invites[0][0] == "sala@conference.h" and _invites[0][1] == "bot@h" and _invites[0][2] == "vení", "muc_invite")

	# Join rechazado (presencia de error): no se agrega ocupante y se avisa.
	s.join_room("otra@conference.h", "yo2")
	s._on_stanza('<presence type="error" from="otra@conference.h/yo2"><error type="cancel"><item-not-found xmlns="urn:ietf:params:xml:ns:xmpp-stanzas"/></error></presence>')
	check(_errors.size() == 1 and _errors[0][1] == "item-not-found", "join rechazado -> muc_error")
	check(not s.is_room("otra@conference.h"), "sala rechazada se descarta")

	# Salida propia: muc_left y deja de ser sala.
	s._on_stanza('<presence type="unavailable" from="sala@conference.h/me" to="me@h/x"><x xmlns="http://jabber.org/protocol/muc#user"><item role="none" affiliation="owner" jid="me@h/x"/><status code="110"/></x></presence>')
	check(_left.back() == "sala@conference.h", "muc_left")
	check(not s.is_room("sala@conference.h"), "deja de ser sala")

	# Destruir (dueño): limpia el estado local y envía el set muc#owner/destroy.
	fake.sent = []
	s.join_room("dest@conference.h", "yo")
	s.muc_destroy("dest@conference.h", "chau")
	check(not s.is_room("dest@conference.h"), "destroy limpia la sala")
	check(fake.sent.back().find("muc#owner") >= 0 and fake.sent.back().find("<destroy><reason>chau</reason></destroy>") >= 0, "muc_destroy envía")

	s.free()
	if _fail == 0:
		print("MUC_SESSION_CHECK_OK")
	quit()

func _on_joined(p_room): _joined.append(p_room)
func _on_left(p_room, _r): _left.append(p_room)
func _on_subject(p_room, p_subject): _subjects.append(p_subject)
func _on_occupants(_p_room): _occupants += 1
func _on_invite(p_room, p_from, p_reason): _invites.append([p_room, p_from, p_reason])
func _on_msg(p_rec): _msgs.append(p_rec)
func _on_hist(p_bare, p_rows, _complete): _hist.append([p_bare, p_rows])
func _on_error(p_room, p_condition): _errors.append([p_room, p_condition])
func _on_config(p_room, p_form): _configs.append([p_room, p_form])

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
		return 0
