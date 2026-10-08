extends Reference

# Modelo del roster (`jabber:iq:roster`). Helper puro, testeable headless.
# Parsea el resultado de un IQ de roster y mantiene un índice por bare JID.

var items := {} # bare JID -> {name, subscription, groups:Array}

func apply_roster_result(p_iq) -> void:
	var query = p_iq.get_child("query", "jabber:iq:roster")
	if query == null:
		return
	for item in query.get_children("item"):
		var jid = item.get_attr("jid", "")
		if jid == "":
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
