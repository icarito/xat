extends Reference

# XEP-0163 (PEP): eventos de avatar (XEP-0084) y telemetría de OpenClaw
# (`urn:openclaw:telemetry:0`, payload XML empaquetado). Puro, testeable.

const NS = preload("res://addons/xat_xmpp/xmpp/namespaces.gd")

# Evento PEP genérico: <message><event xmlns='...#event'><items node><item id>...
static func parse_event(p_message) -> Dictionary:
	var out := {"node": "", "item_id": "", "retract": false, "payload": null}
	if p_message == null:
		return out
	var event = p_message.get_child("event", NS.PEP)
	if event == null:
		return out
	var items = event.get_child("items")
	if items == null:
		return out
	out["node"] = items.get_attr("node", "")
	var retract = items.get_child("retract")
	if retract != null:
		out["retract"] = true
		out["item_id"] = retract.get_attr("id", "")
		return out
	var item = items.get_child("item")
	if item != null:
		out["item_id"] = item.get_attr("id", "")
		for child in item.children:
			if not (child is String):
				out["payload"] = child
				break
	return out

# XEP-0084 metadata: <metadata xmlns='urn:xmpp:avatar:metadata'><info id bytes type/></metadata>
static func parse_avatar_metadata(p_event: Dictionary) -> Dictionary:
	var out := {"id": "", "bytes": 0, "type": ""}
	var payload = p_event.get("payload")
	if payload == null:
		return out
	var info = payload.get_child("info")
	if info == null:
		return out
	out["id"] = info.get_attr("id", "")
	out["bytes"] = int(info.get_attr("bytes", "0"))
	out["type"] = info.get_attr("type", "")
	return out

# XEP-0084 data: <data xmlns='urn:xmpp:avatar:data'>BASE64</data>
static func parse_avatar_data(p_event: Dictionary) -> Dictionary:
	var out := {"id": p_event.get("item_id", ""), "base64": ""}
	var payload = p_event.get("payload")
	if payload == null or payload.name != "data":
		return out
	out["base64"] = payload.get_text()
	return out

# Telemetría OpenClaw.
static func parse_telemetry(p_event: Dictionary) -> Dictionary:
	var out := {
		"activity": "", "availability": "",
		"context": {}, "tokens": {}, "cost": {}, "session_cost": {}, "day_cost": {},
		"model": "", "tool": "", "session_status": "",
	}
	var payload = p_event.get("payload")
	if payload == null or payload.name != "telemetry":
		return out
	out["activity"] = payload.get_attr("activity", "")
	out["availability"] = payload.get_attr("availability", "")
	var context = payload.get_child("context")
	if context != null:
		out["context"] = {
			"used": int(context.get_attr("used", "0")),
			"max": int(context.get_attr("max", "0")),
			"scope": context.get_attr("scope", ""),
			"max_source": context.get_attr("maxSource", ""),
		}
	var tokens = payload.get_child("tokens")
	if tokens != null:
		out["tokens"] = {
			"total": int(tokens.get_attr("total", "0")),
			"input": int(tokens.get_attr("input", "0")),
			"output": int(tokens.get_attr("output", "0")),
			"requests": int(tokens.get_attr("requests", "0")),
			"scope": tokens.get_attr("scope", ""),
		}
	var cost = payload.get_child("cost")
	if cost != null:
		out["cost"] = {"usd": _to_float(cost.get_attr("usd", "0")), "scope": cost.get_attr("scope", "")}
	var session_cost = payload.get_child("session-cost")
	if session_cost != null:
		out["session_cost"] = {"usd": _to_float(session_cost.get_attr("usd", "0"))}
	var day_cost = payload.get_child("day-cost")
	if day_cost != null:
		out["day_cost"] = {"usd": _to_float(day_cost.get_attr("usd", "0"))}
	var model = payload.get_child("model")
	if model != null:
		out["model"] = model.get_text()
	var tool = payload.get_child("tool")
	if tool != null:
		out["tool"] = tool.get_text()
	var session = payload.get_child("session")
	if session != null:
		out["session_status"] = session.get_attr("status", "")
	return out

# Hooks OpenClaw (`urn:openclaw:hooks:<kind>:0`): JSON como texto de un
# elemento cuyo xmlns es el nodo. Devuelve {} si no es un hook válido.
static func parse_hook(p_event: Dictionary) -> Dictionary:
	var node = str(p_event.get("node", ""))
	var payload = p_event.get("payload")
	if payload == null or not node.begins_with("urn:openclaw:hooks:") or payload.get_attr("xmlns", "") != node:
		return {}
	var parsed = JSON.parse(payload.get_text())
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = parsed.result
	if not out.has("event"):
		out["event"] = node.split(":")[3]
	return out

static func _to_float(p_text: String) -> float:
	return float(p_text) if p_text.is_valid_float() else 0.0
