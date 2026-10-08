extends SceneTree

# Acciones pendientes: expiración, aprobaciones y preferencia.

var _fail := 0

func _init():
	var A = load("res://addons/xat_xmpp/xmpp/actions.gd")

	# Expiración explícita gana.
	check(A.effective_expiry(5000, 1000, false) == 5000, "expiry explícita")
	# Fallback no-aprobación: 15 min desde el mensaje.
	check(A.effective_expiry(0, 1000, false) == 1000 + 15 * 60 * 1000, "fallback 15 min")
	# Fallback aprobación: 30 min.
	check(A.effective_expiry(0, 1000, true) == 1000 + 30 * 60 * 1000, "fallback 30 min aprobación")

	check(A.is_expired(1000, 1001), "expirado")
	check(not A.is_expired(1001, 1000), "no expirado")

	# Heurística de aprobación.
	check(A.looks_like_approval("Allow Once", "cmd:abc:0", "Allow Once"), "allow es aprobación")
	check(A.looks_like_approval("", "cmd:x:1", "Denegar"), "denegar es aprobación")
	check(not A.looks_like_approval("Reset", "cmd:reset", "Reset"), "reset no es aprobación")
	check(not A.looks_like_approval("Compact", "cmd:compact", "Compact"), "compact no es aprobación")

	# Stale en restauración: 16 min viejo.
	var now = 100000000
	check(A.is_restored_stale(now - 16 * 60 * 1000, now), "restore 16 min stale")
	check(not A.is_restored_stale(now - 5 * 60 * 1000, now), "restore 5 min fresco")

	# filter_live: descarta expirados, conserva vivos.
	var items = [
		{"name": "Allow", "node": "cmd:a:0", "label": "Allow", "expires_at_ms": now - 1000},
		{"name": "Deny", "node": "cmd:a:1", "label": "Deny", "expires_at_ms": now + 100000},
		{"name": "X", "node": "cmd:x", "label": "X", "expires_at_ms": 0},
	]
	var live = A.filter_live(items, now, now)
	check(live.size() == 2, "filter_live deja 2")
	check(live[0]["name"] == "Deny", "conserva no expirado")

	# Preferencia: comandos sobre quick responses.
	var pref = A.preferred({"commands": [{"node": "cmd:1"}], "quick_responses": [{"value": "si"}]})
	check(pref["kind"] == "command", "prefiere comando")
	var pref2 = A.preferred({"commands": [], "quick_responses": [{"value": "si"}]})
	check(pref2["kind"] == "quick-response", "cae a quick response")

	if _fail == 0:
		print("ACTIONS_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
