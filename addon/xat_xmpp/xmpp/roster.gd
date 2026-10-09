extends Reference

# Modelo del roster (`jabber:iq:roster`). Helper puro, testeable headless.
# Parsea el resultado de un IQ de roster (o un roster push del servidor) y
# mantiene un índice por bare JID; además construye las stanzas de alta/baja.

const NS := "jabber:iq:roster"

const Stanza = preload("res://addons/xat_xmpp/xmpp/stanza.gd")

var items := {} # bare JID -> {name, subscription, groups:Array}

func apply_roster_result(p_iq) -> void:
	var query = p_iq.get_child("query", NS)
	if query == null:
		return
	for item in query.get_children("item"):
		var jid = item.get_attr("jid", "")
		if jid == "":
			continue
		# Roster push de baja: `<item subscription="remove"/>` sale del roster.
		if item.get_attr("subscription", "") == "remove":
			remove_item(jid)
			continue
		set_item(jid, item.get_attr("name", ""), item.get_attr("subscription", "none"), _groups_of(item))

func set_item(p_jid: String, p_name: String, p_subscription: String, p_groups: Array) -> void:
	items[p_jid] = {
		"name": p_name,
		"subscription": p_subscription,
		"groups": p_groups,
	}

func remove_item(p_jid: String) -> void:
	items.erase(p_jid)

func get_item(p_jid: String):
	return items.get(p_jid, null)

func bare_jids() -> Array:
	var out := items.keys()
	out.sort()
	return out

func _groups_of(p_item) -> Array:
	var groups := []
	for g in p_item.get_children("group"):
		groups.append(g.get_text())
	return groups

# --- Builders (IQ set de roster) ---

# Alta/actualización de un item del roster propio: `<iq type='set'>` con
# `<item jid name>` bajo `jabber:iq:roster`.
static func build_set_item(p_id: String, p_jid: String, p_name: String = "", p_groups: Array = []):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "set")
	iq.set_attr("id", p_id)
	var query = Stanza.new("query")
	query.set_attr("xmlns", NS)
	var item = Stanza.new("item")
	item.set_attr("jid", p_jid)
	if p_name != "":
		item.set_attr("name", p_name)
	for g in p_groups:
		var grp = Stanza.new("group")
		grp.append_text(str(g))
		item.add_child_stanza(grp)
	query.add_child_stanza(item)
	iq.add_child_stanza(query)
	return iq

# Baja del roster: `<item jid subscription='remove'/>`.
static func build_remove_item(p_id: String, p_jid: String):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "set")
	iq.set_attr("id", p_id)
	var query = Stanza.new("query")
	query.set_attr("xmlns", NS)
	var item = Stanza.new("item")
	item.set_attr("jid", p_jid)
	item.set_attr("subscription", "remove")
	query.add_child_stanza(item)
	iq.add_child_stanza(query)
	return iq

# ACK de un roster push (`<iq type='set'>` del servidor).
static func build_push_result(p_id: String, p_to: String):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "result")
	iq.set_attr("id", p_id)
	if p_to != "":
		iq.set_attr("to", p_to)
	return iq
