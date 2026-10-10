extends Reference

# Modelo y (de)serialización de <message>: parseo de XEPs 0085 (chat states),
# 0184 (recibos), 0280 (carbons), 0203 (delay), 0308 (correcciones), 0359
# (origin-id/stanza-id), 0313 (MAM), y de los items inline de OpenClaw
# (comandos ad-hoc + quick responses). Helper puro, testeable headless.

const Stanza = preload("res://addons/xat_xmpp/xmpp/stanza.gd")
const NS = preload("res://addons/xat_xmpp/xmpp/namespaces.gd")

const CHAT_STATES := ["active", "composing", "paused", "inactive", "gone"]

# Parsea una stanza <message> (o su texto) y devuelve un Dictionary normalizado.
# Desenvuelve carbons (sent/received) y MAM (result > forwarded > message).
static func parse(p_message) -> Dictionary:
	var stanza = p_message
	if p_message is String:
		stanza = Stanza.parse(p_message)
	var out := {
		"from": "",
		"to": "",
		"type": "",
		"id": "",
		"body": "",
		"subject": "",
		"timestamp": "",
		"delayed": false,
		"chat_state": "",
		"receipt_request": false,
		"received_id": "",
		"carbon": "",
		"replace_id": "",
		"origin_id": "",
		"stanza_id": "",
		"retract_id": "",
		"reply_to": "",
		"reply_quote": "",
		"fallback": "",
		"reactions": [],
		"reactions_target": "",
		"is_mam": false,
		"mam_id": "",
		"mam_queryid": "",
		"oob_url": "",
		"oob_desc": "",
		"commands": [],
		"quick_responses": [],
	}
	if stanza == null:
		return out

	# Carbons: <sent|received xmlns='urn:xmpp:carbons:2'><forwarded>...
	var carbon_node = stanza.get_child("sent", NS.CARBONS)
	if carbon_node == null:
		carbon_node = stanza.get_child("received", NS.CARBONS)
	if carbon_node != null:
		out["carbon"] = carbon_node.name
		var fwd = carbon_node.get_child("forwarded", NS.FORWARD)
		var inner = fwd.get_child("message") if fwd != null else null
		if inner != null:
			stanza = inner

	# MAM: <result xmlns='urn:xmpp:mam:2' queryid id><forwarded><message>...
	var result = stanza.get_child("result", NS.MAM)
	if result != null:
		out["is_mam"] = true
		out["mam_id"] = result.get_attr("id", "")
		out["mam_queryid"] = result.get_attr("queryid", "")
		var fwd2 = result.get_child("forwarded", NS.FORWARD)
		if fwd2 != null:
			var delay_node = fwd2.get_child("delay", NS.DELAY)
			if delay_node != null:
				out["timestamp"] = delay_node.get_attr("stamp", "")
				out["delayed"] = true
			var inner2 = fwd2.get_child("message")
			if inner2 != null:
				stanza = inner2

	if out["from"] == "":
		out["from"] = stanza.get_attr("from", "")
	if out["to"] == "":
		out["to"] = stanza.get_attr("to", "")
	out["type"] = stanza.get_attr("type", "")
	out["id"] = stanza.get_attr("id", "")

	var body_node = stanza.get_child("body")
	if body_node != null:
		out["body"] = body_node.get_text()
	# Sujeto de sala (XEP-0045 §7.2): llega como groupchat sin body.
	var subject_node = stanza.get_child("subject")
	if subject_node != null:
		out["subject"] = subject_node.get_text()

	var delay = stanza.get_child("delay", NS.DELAY)
	if delay != null:
		out["timestamp"] = delay.get_attr("stamp", "")
		out["delayed"] = true

	for child in stanza.children:
		if child is String:
			continue
		var ns = child.get_attr("xmlns", "")
		if ns == NS.CHATSTATES and CHAT_STATES.has(child.name):
			out["chat_state"] = child.name
		elif ns == NS.RECEIPTS and child.name == "request":
			out["receipt_request"] = true
		elif ns == NS.RECEIPTS and child.name == "received":
			out["received_id"] = child.get_attr("id", "")
		elif ns == NS.CORRECT and child.name == "replace":
			out["replace_id"] = child.get_attr("id", "")
		elif ns == NS.RETRACT and child.name == "retract":
			out["retract_id"] = child.get_attr("id", "")
		elif ns == NS.REPLY and child.name == "reply":
			out["reply_to"] = child.get_attr("id", "")
			var rq = child.get_child("quote")
			if rq != null:
				out["reply_quote"] = rq.get_text()
		elif ns == NS.FALLBACK and child.name == "fallback":
			out["fallback"] = child.get_attr("for", "")
		elif ns == NS.REACTIONS and child.name == "reactions":
			out["reactions_target"] = child.get_attr("id", "")
			for r in child.get_children("reaction"):
				out["reactions"].append(r.get_text())
		elif ns == NS.SID and child.name == "origin-id":
			out["origin_id"] = child.get_attr("id", "")
		elif ns == NS.SID and child.name == "stanza-id":
			out["stanza_id"] = child.get_attr("id", "")
		elif ns == NS.OOB and child.name == "x":
			var oob_url = child.get_child("url")
			if oob_url != null:
				out["oob_url"] = oob_url.get_text().strip_edges()
			var oob_desc = child.get_child("desc")
			if oob_desc != null:
				out["oob_desc"] = oob_desc.get_text()

	out["commands"] = parse_inline_commands(stanza)
	out["quick_responses"] = parse_quick_responses(stanza)
	return out

# Items de comando inline anunciados en el cuerpo del mensaje (OpenClaw).
static func parse_inline_commands(p_stanza) -> Array:
	var out := []
	for query in p_stanza.children:
		if query is String:
			continue
		if query.get_attr("xmlns", "") != NS.DISCO_ITEMS:
			continue
		for item in query.get_children("item"):
			if item.get_attr("jid", "") == "" or item.get_attr("node", "") == "":
				continue
			out.append({
				"jid": item.get_attr("jid", ""),
				"node": item.get_attr("node", ""),
				"name": item.get_attr("name", ""),
				"style": item.get_attr("style", ""),
				"expires_at_ms": int(item.get_attr("expires-at-ms", "0")),
			})
	return out

# Botones de respuesta rápida (XEP-0439 y su variante tmp/legacy).
static func parse_quick_responses(p_stanza) -> Array:
	var out := []
	for child in p_stanza.children:
		if child is String:
			continue
		var ns = child.get_attr("xmlns", "")
		if child.name == "response" and (ns == NS.QUICK_RESPONSE or ns == NS.QUICK_RESPONSE_0):
			out.append({
				"value": child.get_attr("value", ""),
				"label": child.get_attr("label", child.get_attr("value", "")),
				"style": child.get_attr("style", ""),
				"expires_at_ms": int(child.get_attr("expires-at-ms", "0")),
			})
		elif child.name == "reference" and child.get_attr("type", "") == "action":
			var ref_body = child.get_child("body")
			if ref_body != null:
				out.append({"value": ref_body.get_text(), "label": ref_body.get_text(), "style": "", "expires_at_ms": 0})
	return out

# --- Builders ---

static func build_chat(p_to: String, p_body: String, p_id: String = "", p_origin_id: String = "", p_request_receipt: bool = true):
	var m = Stanza.new("message")
	m.set_attr("to", p_to)
	m.set_attr("type", "chat")
	if p_id != "":
		m.set_attr("id", p_id)
	var active = Stanza.new("active")
	active.set_attr("xmlns", NS.CHATSTATES)
	m.add_child_stanza(active)
	if p_request_receipt:
		var req = Stanza.new("request")
		req.set_attr("xmlns", NS.RECEIPTS)
		m.add_child_stanza(req)
	if p_origin_id != "":
		var oid = Stanza.new("origin-id")
		oid.set_attr("xmlns", NS.SID)
		oid.set_attr("id", p_origin_id)
		m.add_child_stanza(oid)
	var body = Stanza.new("body")
	body.append_text(p_body)
	m.add_child_stanza(body)
	return m

static func build_chat_state(p_to: String, p_state: String):
	var m = Stanza.new("message")
	m.set_attr("to", p_to)
	m.set_attr("type", "chat")
	var st = Stanza.new(p_state)
	st.set_attr("xmlns", NS.CHATSTATES)
	m.add_child_stanza(st)
	return m

static func build_receipt(p_to: String, p_id: String):
	var m = Stanza.new("message")
	m.set_attr("to", p_to)
	m.set_attr("type", "chat")
	var rec = Stanza.new("received")
	rec.set_attr("xmlns", NS.RECEIPTS)
	rec.set_attr("id", p_id)
	m.add_child_stanza(rec)
	return m

static func build_correction(p_to: String, p_body: String, p_target_id: String, p_new_id: String = ""):
	var m = build_chat(p_to, p_body, p_new_id)
	m.set_attr("id", p_new_id)
	var rep = Stanza.new("replace")
	rep.set_attr("xmlns", NS.CORRECT)
	rep.set_attr("id", p_target_id)
	m.add_child_stanza(rep)
	return m

# Elimina un mensaje propio (XEP-0424). El body es un fallback para clientes sin
# soporte (regla del XEP: texto plano explicando que se eliminó). Sin body, la
# stanza es un evento para el peer que soporta retract.
static func build_retraction(p_to: String, p_target_id: String, p_new_id: String = "", p_fallback: String = "Este mensaje fue eliminado"):
	var m = Stanza.new("message")
	m.set_attr("to", p_to)
	m.set_attr("type", "chat")
	if p_new_id != "":
		m.set_attr("id", p_new_id)
	var retract = Stanza.new("retract")
	retract.set_attr("xmlns", NS.RETRACT)
	retract.set_attr("id", p_target_id)
	m.add_child_stanza(retract)
	if p_fallback != "":
		var body = Stanza.new("body")
		body.append_text(p_fallback)
		m.add_child_stanza(body)
	var fb = Stanza.new("fallback")
	fb.set_attr("xmlns", NS.FALLBACK)
	fb.set_attr("for", NS.RETRACT)
	m.add_child_stanza(fb)
	return m

# Respuesta a un mensaje (XEP-0461) con fallback XEP-0428.
static func build_reply(p_to: String, p_body: String, p_reply_to: String, p_quote: String = "", p_id: String = "", p_origin_id: String = ""):
	var m = build_chat(p_to, p_body, p_id, p_origin_id)
	var rep = Stanza.new("reply")
	rep.set_attr("xmlns", NS.REPLY)
	rep.set_attr("to", p_to)
	rep.set_attr("id", p_reply_to)
	if p_quote != "":
		var q = Stanza.new("quote")
		q.append_text(p_quote)
		rep.add_child_stanza(q)
	m.add_child_stanza(rep)
	# Fallback: cita la línea original para clientes sin 0461.
	if p_quote != "":
		var fb = Stanza.new("fallback")
		fb.set_attr("xmlns", NS.FALLBACK)
		fb.set_attr("for", NS.REPLY)
		m.add_child_stanza(fb)
	return m

# Reacciones (XEP-0444): reemplaza el set completo de emojis de un mensaje con
# una lista; vacía, las quita.
static func build_reactions(p_to: String, p_target_id: String, p_emojis: Array, p_id: String = ""):
	var m = Stanza.new("message")
	m.set_attr("to", p_to)
	m.set_attr("type", "chat")
	if p_id != "":
		m.set_attr("id", p_id)
	var re = Stanza.new("reactions")
	re.set_attr("xmlns", NS.REACTIONS)
	re.set_attr("id", p_target_id)
	for e in p_emojis:
		var r = Stanza.new("reaction")
		r.append_text(str(e))
		re.add_child_stanza(r)
	m.add_child_stanza(re)
	return m

# Adjunto (XEP-0363 + XEP-0066): el link va en el body (para clientes sin OOB)
# y en <x xmlns='jabber:x:oob'><url/></x>. Un pie de foto opcional encabeza el
# body; el link siempre queda en una línea propia para poder quitarlo al
# renderizar la media.
static func build_media(p_to: String, p_url: String, p_caption: String = "", p_id: String = "", p_origin_id: String = "", p_request_receipt: bool = true):
	var caption = p_caption.strip_edges()
	var body_text = p_url if caption == "" else caption + "\n" + p_url
	var m = build_chat(p_to, body_text, p_id, p_origin_id, p_request_receipt)
	var x = Stanza.new("x")
	x.set_attr("xmlns", NS.OOB)
	var url = Stanza.new("url")
	url.append_text(p_url)
	x.add_child_stanza(url)
	if caption != "":
		var desc = Stanza.new("desc")
		desc.append_text(caption)
		x.add_child_stanza(desc)
	m.add_child_stanza(x)
	return m
