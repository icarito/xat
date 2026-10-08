extends SceneTree

# Agregación de presencia por bare JID entre recursos.

var _fail := 0

func _init():
	var Presence = load("res://addons/xat_xmpp/xmpp/presence.gd")
	var p = Presence.new()

	check(Presence.bare_of("a@b/c") == "a@b", "bare_of")
	check(Presence.bare_of("a@b") == "a@b", "bare_of sin recurso")

	p.update("agente@host/phone", "", "", 0, "en el celular")
	p.update("agente@host/desktop", "", "away", 5, "en la compu")
	check(p.is_online("agente@host"), "online con dos recursos")
	var best = p.best("agente@host")
	check(best != null and best["status"] == "en la compu", "mejor por prioridad")

	# Igual prioridad: gana el show más disponible ("" > away).
	p.update("agente@host/tablet", "", "", 5, "tablet")
	best = p.best("agente@host")
	check(best["status"] == "tablet", "empate de prioridad -> show")

	# Un recurso se va: sigue online por los otros.
	p.remove("agente@host/tablet")
	p.remove("agente@host/desktop")
	check(p.is_online("agente@host"), "sigue online con un recurso")
	check(p.best("agente@host")["status"] == "en el celular", "queda el único")

	# unavailable no cuenta como online.
	p.update("solo@host/x", "unavailable", "", 0, "")
	check(not p.is_online("solo@host"), "unavailable no es online")
	check(p.best("solo@host") == null, "sin best si no hay disponible")

	# remove deja offline.
	p.remove("agente@host/phone")
	check(not p.is_online("agente@host"), "offline tras remover todo")
	check(p.best("agente@host") == null, "best null sin recursos")

	if _fail == 0:
		print("PRESENCE_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
