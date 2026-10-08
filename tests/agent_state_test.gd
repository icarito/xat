extends SceneTree

# Estado por agente: telemetría + hooks (apply_telemetry/apply_hook/pending_approvals).

var _fail := 0

func _init():
	var AgentState = load("res://addons/xat_xmpp/xmpp/agent_state.gd")
	var st = AgentState.new()

	# apply_telemetry mergea campos sin perder los previos.
	st.apply_telemetry("bot@h", {"activity": "available", "model": "deepseek/x", "tokens": {"total": 5}})
	st.apply_telemetry("bot@h", {"availability": "available"})
	var s = st.get_state("bot@h")
	check(s["activity"] == "available" and s["model"] == "deepseek/x" and s["tokens"]["total"] == 5 and s["availability"] == "available", "apply_telemetry merge")

	# Hook activity setea "activity".
	st.apply_hook("bot@h", {"event": "activity", "state": "processing"})
	check(st.get_state("bot@h")["activity"] == "processing", "hook activity")

	# Hook progress se guarda en "progress".
	st.apply_hook("bot@h", {"event": "progress", "state": "start", "detail": "exec ls"})
	var prog = st.get_state("bot@h")["progress"]
	check(prog.get("state", "") == "start" and prog.get("detail", "") == "exec ls", "hook progress")

	# Hook approval indexado por approvalId.
	st.apply_hook("bot@h", {"event": "approval", "approvalId": "a1", "state": "pending", "expiresAtMs": 2000})
	st.apply_hook("bot@h", {"event": "approval", "approvalId": "a2", "state": "pending"})
	st.apply_hook("bot@h", {"event": "approval", "approvalId": "a3", "state": "resolved"})
	var approvals = st.get_state("bot@h")["approvals"]
	check(approvals.has("a1") and approvals["a1"]["state"] == "pending" and approvals.has("a2") and approvals.has("a3"), "hook approval por approvalId")

	# pending_approvals a now=2000: excluye a1 vencida y a3 resuelta, incluye a2 sin expiresAtMs.
	var pend = st.pending_approvals("bot@h", 2000)
	check(pend.size() == 1 and pend[0]["approvalId"] == "a2", "pending_approvals excluye resuelto/vencido")

	# a1 todavía pending antes de vencer.
	check(st.pending_approvals("bot@h", 1000).size() == 2, "pending_approvals antes de vencer")

	if _fail == 0:
		print("AGENT_STATE_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
