extends SceneTree

# XEP-0045 MUC: builders de join/leave/groupchat, parseo de presencia de sala
# (códigos 110/201/210/307/301) e invitaciones, y estado de ocupantes.

var _fail := 0

func _init():
	var Muc = load("res://addons/xat_xmpp/xmpp/muc.gd")
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")

	# Join con historial.
	var join = Muc.build_join("sala@conference.h", "ale", 20)
	var jx = join.to_xml()
	check(join.name == "presence", "join es presence")
	check(join.get_attr("to") == "sala@conference.h/ale", "join to room/nick")
	check(jx.find('<x xmlns="http://jabber.org/protocol/muc">') >= 0, "join x muc")
	check(jx.find('<history maxstanzas="20"/>') >= 0, "join history maxstanzas")

	# Join sin historial.
	var join0 = Muc.build_join("sala@conference.h", "ale", -1)
	check(join0.to_xml().find("history") < 0, "join sin history")

	# Leave.
	var leave = Muc.build_leave("sala@conference.h", "ale")
	check(leave.get_attr("to") == "sala@conference.h/ale" and leave.get_attr("type") == "unavailable", "leave unavailable")

	# Groupchat: sin recibos ni chat states.
	var g = Muc.build_groupchat("sala@conference.h", "hola", "m1", "o1")
	var gx = g.to_xml()
	check(g.get_attr("type") == "groupchat" and g.get_attr("to") == "sala@conference.h", "groupchat attrs")
	check(gx.find("<body>hola</body>") >= 0, "groupchat body")
	check(gx.find('xmlns="urn:xmpp:sid:0"') >= 0, "groupchat origin-id 0359")
	check(gx.find("receipts") < 0 and gx.find("chatstates") < 0, "groupchat sin recibos/estados")

	# parse_presence: entrada normal de otro ocupante (sala no anónima).
	var p1 = Stanza.parse('<presence from="sala@conference.h/joe" to="yo@h/x"><x xmlns="http://jabber.org/protocol/muc#user"><item affiliation="member" role="participant" jid="joe@h/phone"/></x></presence>')
	var r1 = Muc.parse_presence(p1)
	check(r1["room"] == "sala@conference.h" and r1["nick"] == "joe", "presence room/nick")
	check(not r1["unavailable"] and r1["occupant_jid"] == "joe@h/phone", "presence ocupante jid")
	check(r1["affiliation"] == "member" and r1["role"] == "participant", "presence affiliation/role")
	check(not r1["is_self"], "presence no self")

	# Presencia propia con código 110.
	var p2 = Stanza.parse('<presence from="sala@conference.h/ale" to="yo@h/x"><x xmlns="http://jabber.org/protocol/muc#user"><item affiliation="owner" role="moderator" jid="yo@h/x"/><status code="110"/><status code="201"/></x></presence>')
	var r2 = Muc.parse_presence(p2)
	check(r2["is_self"] and r2["created"], "presence self+created")
	check(r2["status_codes"].has("110") and r2["status_codes"].has("201"), "presence status codes")

	# Renombrado 210.
	var r3 = Muc.parse_presence(Stanza.parse('<presence from="sala@conference.h/ale2"><x xmlns="http://jabber.org/protocol/muc#user"><item nick="ale2" affiliation="owner" role="moderator"/><status code="210"/></x></presence>'))
	check(r3["renamed"] and r3["item_nick"] == "ale2", "presence renamed 210")

	# Salida (unavailable) simple.
	var r4 = Muc.parse_presence(Stanza.parse('<presence from="sala@conference.h/joe" type="unavailable"><x xmlns="http://jabber.org/protocol/muc#user"><item affiliation="none" role="none"/></x></presence>'))
	check(r4["unavailable"], "presence unavailable")

	# Expulsión 307 con razón y actor.
	var r5 = Muc.parse_presence(Stanza.parse('<presence from="sala@conference.h/joe" type="unavailable"><x xmlns="http://jabber.org/protocol/muc#user"><item affiliation="none" role="none"><actor jid="mod@h"/><reason>spam</reason></item><status code="307"/></x></presence>'))
	check(r5["kicked"] and r5["reason"] == "spam", "presence kicked 307")

	# Veto 301.
	var r6 = Muc.parse_presence(Stanza.parse('<presence from="sala@conference.h/joe" type="unavailable"><x xmlns="http://jabber.org/protocol/muc#user"><item affiliation="outcast" role="none"/><status code="301"/></x></presence>'))
	check(r6["banned"] and r6["affiliation"] == "outcast", "presence banned 301")

	# Invitación mediada XEP-0045 §7.8.
	var inv1 = Muc.parse_invite(Stanza.parse('<message from="sala@conference.h" to="yo@h/x"><x xmlns="http://jabber.org/protocol/muc#user"><invite from="agente@h"><reason>pasa</reason></invite></x></message>'))
	check(inv1["mediated"] and inv1["room"] == "sala@conference.h" and inv1["from"] == "agente@h" and inv1["reason"] == "pasa", "invitación mediada")

	# Invitación directa XEP-0249.
	var inv2 = Muc.parse_invite(Stanza.parse('<message from="agente@h/x" to="yo@h/x"><x xmlns="jabber:x:conference" jid="sala@conference.h" reason="ven"/></message>'))
	check(not inv2["mediated"] and inv2["room"] == "sala@conference.h" and inv2["from"] == "agente@h/x" and inv2["reason"] == "ven", "invitación directa")

	# Estado de ocupantes: alta, rename y salida.
	var state = {}
	Muc.apply_presence(state, r1)
	check(state.has("joe") and state["joe"]["jid"] == "joe@h/phone", "apply ocupante")
	var renamed = Muc.parse_presence(Stanza.parse('<presence from="sala@conference.h/joe2"><x xmlns="http://jabber.org/protocol/muc#user"><item nick="joe2" role="participant"/></x></presence>'))
	Muc.apply_presence(state, renamed)
	check(state.has("joe2") and state.has("joe"), "apply rename deja ambos lapsos (session limpia viejo)")
	check(Muc.remove(state, "joe"), "remove ocupante")
	check(not state.has("joe") and not Muc.remove(state, "nadie"), "remove idempotente")
	check(Muc.occupant_nicks(state) == ["joe2"], "occupant_nicks")

	# Discovery.
	check(Muc.disco_has_muc(Stanza.parse('<iq type="result"><query xmlns="http://jabber.org/protocol/disco#info"><feature var="http://jabber.org/protocol/muc"/></query></iq>')), "disco_has_muc true")
	check(not Muc.disco_has_muc(Stanza.parse('<iq type="result"><query xmlns="http://jabber.org/protocol/disco#info"><feature var="jabber:iq:roster"/></query></iq>')), "disco_has_muc false")

	# Config del dueño: get y submit preservando los defaults del servidor.
	var cget = Muc.build_owner_config_get("sala@conference.h", "c1")
	check(cget.get_attr("type") == "get" and cget.get_attr("to") == "sala@conference.h" and cget.get_attr("id") == "c1", "owner config get attrs")
	check(cget.to_xml().find('xmlns="http://jabber.org/protocol/muc#owner"') >= 0, "owner config get ns")
	var cform = Stanza.parse('<iq type="result" id="c1"><query xmlns="http://jabber.org/protocol/muc#owner"><x xmlns="jabber:x:data" type="form"><field var="FORM_TYPE" type="hidden"><value>http://jabber.org/protocol/muc#roomconfig</value></field><field var="muc#roomconfig_membersonly" type="boolean"><value>1</value></field><field var="muc#roomconfig_roomname" type="text"><value>Prueba</value></field></x></query></iq>')
	var fields = Muc.parse_owner_config_form(cform)
	check(fields.size() == 3 and fields[1]["var"] == "muc#roomconfig_membersonly" and fields[1]["values"] == ["1"], "parse owner form")
	var csub = Muc.build_owner_config_submit("sala@conference.h", "c2", fields)
	var subxml = csub.to_xml()
	check(csub.get_attr("type") == "set", "owner submit set")
	check(subxml.find('FORM_TYPE" type="hidden"><value>http://jabber.org/protocol/muc#roomconfig</value>') >= 0, "submit FORM_TYPE roomconfig")
	check(subxml.find('muc#roomconfig_membersonly" type="boolean"><value>1</value>') >= 0, "submit preserva membersonly")
	check(subxml.find("Prueba") >= 0, "submit preserva roomname")

	# Presencia de error (join rechazado): condición a detectar.
	var perr = Muc.parse_error(Stanza.parse('<presence type="error" from="sala@conference.h/x"><error type="cancel"><item-not-found xmlns="urn:ietf:params:xml:ns:xmpp-stanzas"/></error></presence>'))
	check(perr["is_error"] and perr["type"] == "cancel" and perr["condition"] == "item-not-found", "parse_error")
	check(not Muc.parse_error(Stanza.parse('<presence from="sala@conference.h/x"><x xmlns="http://jabber.org/protocol/muc#user"><item role="participant"/></x></presence>'))["is_error"], "parse_error false")

	# Moderación: muc#admin set (afiliación con jid, rol con nick) y get.
	var aset = Muc.build_admin_set("sala@conference.h", "a1", [{"jid": "joe@h", "affiliation": "member"}, {"nick": "joe", "role": "none", "reason": "bye"}])
	check(aset.get_attr("type") == "set" and aset.get_attr("to") == "sala@conference.h", "admin set attrs")
	var axml = aset.to_xml()
	check(axml.find('xmlns="http://jabber.org/protocol/muc#admin"') >= 0, "admin set ns")
	check(axml.find('jid="joe@h" affiliation="member"') >= 0, "admin set afiliación")
	check(axml.find('nick="joe" role="none"') >= 0 and axml.find("<reason>bye</reason>") >= 0, "admin set rol+razón")
	var aget = Muc.build_admin_get("sala@conference.h", "a2", "member")
	check(aget.get_attr("type") == "get" and aget.to_xml().find('affiliation="member"') >= 0, "admin get")
	var alist = Muc.parse_admin_list(Stanza.parse('<iq type="result"><query xmlns="http://jabber.org/protocol/muc#admin"><item jid="joe@h" affiliation="member"/><item nick="ana" role="moderator"/></query></iq>'))
	check(alist.size() == 2 and alist[0]["jid"] == "joe@h" and alist[1]["role"] == "moderator", "parse admin list")

	# Invitación mediada, tema y destruir.
	var inv = Muc.build_invite("sala@conference.h", "joe@h", "vení")
	check(inv.get_attr("to") == "sala@conference.h" and inv.to_xml().find('xmlns="http://jabber.org/protocol/muc#user"') >= 0, "invite a la sala")
	check(inv.to_xml().find('<invite to="joe@h"><reason>vení</reason></invite>') >= 0, "invite to+reason")
	var subj = Muc.build_subject("sala@conference.h", "tema")
	check(subj.get_attr("type") == "groupchat" and subj.to_xml().find("<subject>tema</subject>") >= 0, "build_subject")
	var dst = Muc.build_destroy("sala@conference.h", "d1", "chau")
	check(dst.get_attr("type") == "set" and dst.to_xml().find('xmlns="http://jabber.org/protocol/muc#owner"') >= 0 and dst.to_xml().find("<destroy><reason>chau</reason></destroy>") >= 0, "build_destroy")

	if _fail == 0:
		print("MUC_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
