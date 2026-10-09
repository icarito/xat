extends Reference

# XEP-0045 (MUC): builders de join/leave/groupchat y parsers de presencia de
# sala e invitaciones. Helper puro, testeable headless. La política (estado de
# ocupantes, autojoin, dedupe del eco propio) vive en session/store.
#
# Mención: en esta iteración un `@nick ` es texto plano (interopera con el
# plugin de OpenClaw y con cualquier cliente); XEP-0372 queda como refuerzo.

const Stanza = preload("res://addons/xat_xmpp/xmpp/stanza.gd")
const NS = preload("res://addons/xat_xmpp/xmpp/namespaces.gd")

# --- Builders ---

# Presencia de entrada a una sala: `to=room/nick` con `<x xmlns=muc>` y, si
# `p_history_max >= 0`, `<history maxstanzas=.../>` para abrir con historial.
static func build_join(p_room_bare: String, p_nick: String, p_history_max: int = 20):
	var p = Stanza.new("presence")
	p.set_attr("to", p_room_bare + "/" + p_nick)
	var x = Stanza.new("x")
	x.set_attr("xmlns", NS.MUC)
	if p_history_max >= 0:
		var history = Stanza.new("history")
		history.set_attr("maxstanzas", str(p_history_max))
		x.add_child_stanza(history)
	p.add_child_stanza(x)
	return p

# Salida de una sala: presencia `type=unavailable` a `room/nick`.
static func build_leave(p_room_bare: String, p_nick: String):
	var p = Stanza.new("presence")
	p.set_attr("to", p_room_bare + "/" + p_nick)
	p.set_attr("type", "unavailable")
	return p

# Mensaje de sala: `type=groupchat` con body y origin-id (XEP-0359); SIN
# recibos ni chat states (las salas no los usan).
static func build_groupchat(p_room_bare: String, p_body: String, p_id: String = "", p_origin_id: String = ""):
	var m = Stanza.new("message")
	m.set_attr("to", p_room_bare)
	m.set_attr("type", "groupchat")
	if p_id != "":
		m.set_attr("id", p_id)
	if p_origin_id != "":
		var oid = Stanza.new("origin-id")
		oid.set_attr("xmlns", NS.SID)
		oid.set_attr("id", p_origin_id)
		m.add_child_stanza(oid)
	var body = Stanza.new("body")
	body.append_text(p_body)
	m.add_child_stanza(body)
	return m

# --- Parsers ---

# Presencia de sala -> estado normalizado. `from` es `room/nick`.
# Códigos XEP-0045 §4.2: 110 self, 201 sala creada, 210 nick renombrado,
# 307 expulsado, 301 vetado. `occupant_jid` sólo viene en salas no anónimas.
static func parse_presence(p_presence) -> Dictionary:
	var out := {
		"room": "",
		"nick": "",
		"full": "",
		"occupant_jid": "",
		"unavailable": false,
		"is_self": false,
		"renamed": false,
		"created": false,
		"kicked": false,
		"banned": false,
		"affiliation": "",
		"role": "",
		"item_nick": "",
		"reason": "",
		"status_codes": [],
	}
	if p_presence == null:
		return out
	var full = p_presence.get_attr("from", "")
	out["full"] = full
	var slash = full.find("/")
	out["room"] = full if slash < 0 else full.substr(0, slash)
	out["nick"] = "" if slash < 0 else full.substr(slash + 1)
	out["unavailable"] = p_presence.get_attr("type", "") == "unavailable"
	var x = p_presence.get_child("x", NS.MUC_USER)
	if x == null:
		return out
	var item = x.get_child("item")
	if item != null:
		out["affiliation"] = item.get_attr("affiliation", "")
		out["role"] = item.get_attr("role", "")
		out["occupant_jid"] = item.get_attr("jid", "")
		out["item_nick"] = item.get_attr("nick", "")
		var reason = item.get_child("reason")
		if reason != null:
			out["reason"] = reason.get_text()
	for st in x.get_children("status"):
		var code = st.get_attr("code", "")
		out["status_codes"].append(code)
		if code == "110":
			out["is_self"] = true
		elif code == "210":
			out["renamed"] = true
		elif code == "201":
			out["created"] = true
		elif code == "307":
			out["kicked"] = true
		elif code == "301":
			out["banned"] = true
	return out

# Invitación a sala -> {room, from, reason, mediated}. Mediada XEP-0045 §7.8
# (`<x xmlns=muc#user><invite>`) o directa XEP-0249 (`jabber:x:conference`).
static func parse_invite(p_message) -> Dictionary:
	var out := {"room": "", "from": "", "reason": "", "mediated": false}
	if p_message == null:
		return out
	var x = p_message.get_child("x", NS.MUC_USER)
	if x != null:
		var invite = x.get_child("invite")
		if invite != null:
			out["mediated"] = true
			out["from"] = invite.get_attr("from", p_message.get_attr("from", ""))
			var reason = invite.get_child("reason")
			if reason != null:
				out["reason"] = reason.get_text()
			out["room"] = p_message.get_attr("from", "")
			return out
	var direct = p_message.get_child("x", NS.CONFERENCE_INVITE)
	if direct != null:
		out["room"] = direct.get_attr("jid", "")
		out["from"] = p_message.get_attr("from", "")
		out["reason"] = direct.get_attr("reason", "")
	return out

# --- Configuración del dueño (XEP-0045 §10.2) ---

# Un servidor puede "bloquear" una sala recién creada hasta que el dueño envíe
# su configuración inicial (Prosody: muc_room_locking=true). Sin esto, nadie más
# puede entrar (recibe item-not-found). Pedimos el formulario al crear la sala.

static func build_owner_config_get(p_room_bare: String, p_id: String):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "get")
	iq.set_attr("to", p_room_bare)
	iq.set_attr("id", p_id)
	var q = Stanza.new("query")
	q.set_attr("xmlns", NS.MUC_OWNER)
	iq.add_child_stanza(q)
	return iq

# Reescribe el formulario recibido tal cual (conserva los defaults del server) y
# lo reenvía: eso dispara `muc-config-submitted` y desbloquea la sala.
static func build_owner_config_submit(p_room_bare: String, p_id: String, p_fields: Array):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "set")
	iq.set_attr("to", p_room_bare)
	iq.set_attr("id", p_id)
	var q = Stanza.new("query")
	q.set_attr("xmlns", NS.MUC_OWNER)
	var x = Stanza.new("x")
	x.set_attr("xmlns", NS.DATA_FORMS)
	x.set_attr("type", "submit")
	x.add_child_stanza(_field_value("FORM_TYPE", "hidden", [NS.MUC_ROOMCONFIG]))
	for f in p_fields:
		var var_name = str(f.get("var", ""))
		if var_name == "" or var_name == "FORM_TYPE":
			continue
		x.add_child_stanza(_field_value(var_name, str(f.get("type", "")), f.get("values", [])))
	q.add_child_stanza(x)
	iq.add_child_stanza(q)
	return iq

static func _field_value(p_var: String, p_type: String, p_values: Array):
	var f = Stanza.new("field")
	f.set_attr("var", p_var)
	if p_type != "":
		f.set_attr("type", p_type)
	for val in p_values:
		var v = Stanza.new("value")
		v.append_text(str(val))
		f.add_child_stanza(v)
	return f

# Campos del formulario muc#owner -> [{var, type, values}].
static func parse_owner_config_form(p_iq) -> Array:
	var out := []
	if p_iq == null:
		return out
	var q = p_iq.get_child("query", NS.MUC_OWNER)
	if q == null:
		return out
	var x = q.get_child("x", NS.DATA_FORMS)
	if x == null:
		return out
	for f in x.get_children("field"):
		var vals := []
		for v in f.get_children("value"):
			vals.append(v.get_text())
		out.append({"var": f.get_attr("var", ""), "type": f.get_attr("type", ""), "values": vals})
	return out

# Presencia de sala con error (join rechazado): {type, condition}. Sirve para no
# tratarla como un alta de ocupante y avisar del fallo.
static func parse_error(p_stanza) -> Dictionary:
	var out := {"is_error": false, "type": "", "condition": ""}
	if p_stanza == null or p_stanza.get_attr("type", "") != "error":
		return out
	out["is_error"] = true
	var err = p_stanza.get_child("error")
	if err != null:
		out["type"] = err.get_attr("type", "")
		for c in err.get_children():
			if str(c.name) != "text":
				out["condition"] = str(c.name)
				break
	return out

# --- Moderación / afiliaciones (XEP-0045 §8–9) ---

# Cambia afiliación (`member`/`admin`/`outcast`/`none`) de un JID y/o rol
# (`moderator`/`participant`/`visitor`/`none`) de un nick. Cada item lleva `jid`
# o `nick`, `affiliation` o `role`, y una razón opcional.
static func build_admin_set(p_room_bare: String, p_id: String, p_items: Array):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "set")
	iq.set_attr("to", p_room_bare)
	iq.set_attr("id", p_id)
	var q = Stanza.new("query")
	q.set_attr("xmlns", NS.MUC_ADMIN)
	for it in p_items:
		var item = Stanza.new("item")
		if str(it.get("jid", "")) != "":
			item.set_attr("jid", str(it["jid"]))
		if str(it.get("nick", "")) != "":
			item.set_attr("nick", str(it["nick"]))
		if str(it.get("affiliation", "")) != "":
			item.set_attr("affiliation", str(it["affiliation"]))
		if str(it.get("role", "")) != "":
			item.set_attr("role", str(it["role"]))
		if str(it.get("reason", "")) != "":
			var reason = Stanza.new("reason")
			reason.append_text(str(it["reason"]))
			item.add_child_stanza(reason)
		q.add_child_stanza(item)
	iq.add_child_stanza(q)
	return iq

# Lista afiliados (`p_affiliation`) y/o roles (`p_role`) de la sala.
static func build_admin_get(p_room_bare: String, p_id: String, p_affiliation: String = "", p_role: String = ""):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "get")
	iq.set_attr("to", p_room_bare)
	iq.set_attr("id", p_id)
	var q = Stanza.new("query")
	q.set_attr("xmlns", NS.MUC_ADMIN)
	var item = Stanza.new("item")
	if p_affiliation != "":
		item.set_attr("affiliation", p_affiliation)
	if p_role != "":
		item.set_attr("role", p_role)
	q.add_child_stanza(item)
	iq.add_child_stanza(q)
	return iq

# Respuesta de muc#admin -> [{jid, nick, affiliation, role, reason}].
static func parse_admin_list(p_iq) -> Array:
	var out := []
	if p_iq == null:
		return out
	var q = p_iq.get_child("query", NS.MUC_ADMIN)
	if q == null:
		return out
	for item in q.get_children("item"):
		out.append({
			"jid": item.get_attr("jid", ""),
			"nick": item.get_attr("nick", ""),
			"affiliation": item.get_attr("affiliation", ""),
			"role": item.get_attr("role", ""),
		})
	return out

# Invitación mediada (XEP-0045 §7.8): se envía A LA SALA, que la reenvía.
static func build_invite(p_room_bare: String, p_to_jid: String, p_reason: String = ""):
	var m = Stanza.new("message")
	m.set_attr("to", p_room_bare)
	var x = Stanza.new("x")
	x.set_attr("xmlns", NS.MUC_USER)
	var inv = Stanza.new("invite")
	inv.set_attr("to", p_to_jid)
	if p_reason != "":
		var reason = Stanza.new("reason")
		reason.append_text(p_reason)
		inv.add_child_stanza(reason)
	x.add_child_stanza(inv)
	m.add_child_stanza(x)
	return m

# Cambio de tema (XEP-0045 §7.2.16): groupchat con <subject>.
static func build_subject(p_room_bare: String, p_subject: String):
	var m = Stanza.new("message")
	m.set_attr("to", p_room_bare)
	m.set_attr("type", "groupchat")
	var s = Stanza.new("subject")
	s.append_text(p_subject)
	m.add_child_stanza(s)
	return m

# Destruir la sala (sólo el dueño).
static func build_destroy(p_room_bare: String, p_id: String, p_reason: String = ""):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "set")
	iq.set_attr("to", p_room_bare)
	iq.set_attr("id", p_id)
	var q = Stanza.new("query")
	q.set_attr("xmlns", NS.MUC_OWNER)
	var d = Stanza.new("destroy")
	if p_reason != "":
		var reason = Stanza.new("reason")
		reason.append_text(p_reason)
		d.add_child_stanza(reason)
	q.add_child_stanza(d)
	iq.add_child_stanza(q)
	return iq

# --- Estado de ocupantes ---

# Aplica una presencia (resultado de `parse_presence`) al estado `p_state`
# (nick -> ocupante). Devuelve el ocupante afectado, o {} si fue una salida.
static func apply_presence(p_state: Dictionary, p_presence: Dictionary) -> Dictionary:
	var nick = p_presence.get("nick", "")
	if nick == "":
		return {}
	if p_presence.get("unavailable", false):
		p_state.erase(nick)
		return {}
	var occ = {
		"nick": nick,
		"jid": p_presence.get("occupant_jid", ""),
		"affiliation": p_presence.get("affiliation", ""),
		"role": p_presence.get("role", ""),
	}
	p_state[nick] = occ
	return occ

# Quita un nick del estado; true si existía.
static func remove(p_state: Dictionary, p_nick: String) -> bool:
	if not p_state.has(p_nick):
		return false
	p_state.erase(p_nick)
	return true

# Nicks del estado en orden alfabético estable (para mostrar/contar).
static func occupant_nicks(p_state: Dictionary) -> Array:
	var out = p_state.keys()
	out.sort()
	return out

# --- Discovery ---

# ¿El componente anuncia MUC en disco#info? (reusa los builders de Media).
static func disco_has_muc(p_stanza) -> bool:
	var q = p_stanza.get_child("query", NS.DISCO_INFO)
	if q == null:
		return false
	for f in q.get_children("feature"):
		if f.get_attr("var", "") == NS.MUC:
			return true
	return false
