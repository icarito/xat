extends Reference

# Último estado conocido de cada agente, por bare JID: telemetría + hooks.
# Puro (sin nodos); la sesión lo alimenta y la UI lo lee. Ver docs/ui.md.

var _agents := {}

func has_agent(p_bare: String) -> bool:
	return _agents.has(p_bare)

func get_state(p_bare: String) -> Dictionary:
	if not _agents.has(p_bare):
		_agents[p_bare] = {
			"activity": "", "availability": "", "context": {}, "tokens": {},
			"cost": {}, "session_cost": {}, "day_cost": {}, "model": "",
			"tool": "", "session_status": "",
			"progress": {}, # último hook progress {state start|end, detail}
			"approvals": {}, # approvalId -> último hook approval
		}
	return _agents[p_bare]

func apply_telemetry(p_bare: String, p_tel: Dictionary) -> Dictionary:
	var st = get_state(p_bare)
	for k in p_tel:
		st[k] = p_tel[k]
	return st

func apply_hook(p_bare: String, p_hook: Dictionary) -> Dictionary:
	var st = get_state(p_bare)
	match str(p_hook.get("event", "")):
		"activity":
			st["activity"] = str(p_hook.get("state", st["activity"]))
		"progress":
			st["progress"] = p_hook
		"approval":
			var id = str(p_hook.get("approvalId", ""))
			if id != "":
				st["approvals"][id] = p_hook
	return st

# Aprobaciones en estado pending y no vencidas a `p_now_ms`.
func pending_approvals(p_bare: String, p_now_ms: int) -> Array:
	var out := []
	for a in get_state(p_bare)["approvals"].values():
		if str(a.get("state", "")) != "pending":
			continue
		var expires = a.get("expiresAtMs")
		if expires != null and int(expires) > 0 and int(expires) <= p_now_ms:
			continue
		out.append(a)
	return out
