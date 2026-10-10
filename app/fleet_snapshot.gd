extends Reference

# JoeWork-specific projection decoder. Xat's XEP-0060 layer preserves payloads
# without interpreting them; this app consumes Projection.to_pubsub_xml().
const NODE_NAMESPACE := "urn:joework:monitoring:2"
const DEFAULT_NODE := "joework/monitoring/team"
const STALE_AFTER_SECONDS := 900

static func parse(p_root) -> Dictionary:
	var out := {"generated_at": "", "stale": false, "entities": [], "operations": [], "cost": []}
	if p_root == null:
		return out
	if str(p_root.name).to_lower() == "item":
		var payloads = p_root.get_children()
		p_root = payloads[0] if not payloads.empty() else null
	if p_root == null or str(p_root.name).to_lower() != "monitoring":
		return out
	var attrs = p_root.attrs
	if str(attrs.get("xmlns", "")) != NODE_NAMESPACE:
		return out
	out["generated_at"] = str(attrs.get("generated-at", ""))
	out["stale"] = str(attrs.get("stale", "false")).to_lower() in ["true", "1", "yes"]
	for instance in p_root.get_children("instance"):
		var entity = _parse_instance(instance)
		out["entities"].append(entity)
		var ops = entity.get("operational", {})
		if not ops.empty():
			var op_row = {"instance": entity.get("team", entity.get("id", "")), "entity-kind": entity.get("entity-kind", ""), "fields": ops}
			out["operations"].append(op_row)
		for metric in entity.get("metrics", []):
			var metric_name = str(metric.get("name", "")).to_lower()
			if metric_name.find("cost") >= 0 or metric_name.find("spend") >= 0:
				var cost_row = metric.duplicate()
				cost_row["instance"] = entity.get("team", entity.get("id", ""))
				out["cost"].append(cost_row)
	if _is_old(out["generated_at"]):
		out["stale"] = true
	return out

static func _parse_instance(p_instance) -> Dictionary:
	var out := {}
	for key in p_instance.attrs.keys():
		out[str(key).to_lower().replace("_", "-")] = p_instance.attrs[key]
	out["metrics"] = []
	out["operational"] = {}
	for child in p_instance.get_children():
		var key = str(child.name).to_lower().replace("_", "-")
		if key == "metrics":
			for metric in child.get_children("metric"):
				var record := {}
				for attr in metric.attrs.keys():
					record[str(attr).to_lower().replace("_", "-")] = metric.attrs[attr]
				out["metrics"].append(record)
		elif key == "operational":
			for field in child.get_children("field"):
				var field_name = str(field.get_attr("name", "field"))
				var value = field.get_attr("value", field.get_text().strip_edges())
				out["operational"][field_name] = str(value)
		elif child.get_children().empty():
			out[key] = child.get_text().strip_edges()
	# Surface the observed health first. Keep declared state and lifecycle in
	# separate fields so a hibernated instance never reads as a failed one.
	if str(out.get("lifecycle", "")).to_lower() == "hibernated":
		out["status"] = "hibernated"
	elif out.has("health") and str(out["health"]) != "":
		out["status"] = str(out["health"])
	elif out.has("state"):
		out["status"] = str(out["state"])
	elif out.has("lifecycle"):
		out["status"] = str(out["lifecycle"])
	return out

static func _is_old(p_value: String) -> bool:
	if p_value == "": return false
	if p_value.is_valid_integer():
		var stamp = int(p_value)
		if stamp > 100000000000: stamp = int(stamp / 1000)
		return OS.get_unix_time() - stamp > STALE_AFTER_SECONDS
	# Projection emits UTC in YYYY-MM-DDTHH:MM:SSZ form.
	if p_value.length() < 20 or p_value[4] != "-": return false
	var date = p_value.substr(0, 10).split("-")
	var clock = p_value.substr(11, 8).split(":")
	if date.size() != 3 or clock.size() != 3: return false
	var dt := {"year": int(date[0]), "month": int(date[1]), "day": int(date[2]), "hour": int(clock[0]), "minute": int(clock[1]), "second": int(clock[2])}
	var stamp = _utc_epoch(dt)
	return stamp > 0 and OS.get_unix_time() - stamp > STALE_AFTER_SECONDS

static func _utc_epoch(p_date: Dictionary) -> int:
	var year = int(p_date.year)
	var days = 0
	for y in range(1970, year): days += 366 if _leap(y) else 365
	var months = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if _leap(year): months[1] = 29
	for m in range(1, int(p_date.month)): days += months[m - 1]
	days += int(p_date.day) - 1
	return days * 86400 + int(p_date.hour) * 3600 + int(p_date.minute) * 60 + int(p_date.second)

static func _leap(p_year: int) -> bool:
	return p_year % 4 == 0 and (p_year % 100 != 0 or p_year % 400 == 0)
