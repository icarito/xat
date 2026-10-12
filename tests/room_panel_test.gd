extends SceneTree

# Pane de participantes de sala: filas por ocupante, orbe/estado para agentes y
# resolución ocupante->bare (jid real o nick). Headless.

var _fail := 0
var _picked := []

func _on_pick(p_nick, p_bare) -> void:
	_picked.append([p_nick, p_bare])

func _init():
	var RoomPanel = load("res://addons/xat_xmpp/ui/room_panel.gd")
	var root = get_root()
	var r = RoomPanel.new()
	root.add_child(r)
	r.connect("occupant_selected", self, "_on_pick")

	r.set_room("sala@conference.h", "yo", [
		{"nick": "yo", "jid": "me@h/x", "affiliation": "owner", "role": "moderator"},
		{"nick": "bot", "jid": "bot@h/phone", "affiliation": "member", "role": "participant"},
	])
	check(r.occupant_count() == 2, "dos ocupantes")
	check(r._title.text.find("(2)") >= 0, "título con conteo")
	check(r._rows.get_child_count() == 2, "dos filas")
	check(not r._empty.visible, "sin vacío con ocupantes")

	# Estado de agente por jid real.
	r.set_agent("bot@h", {"activity": "processing"}, true)
	var bot_row = null
	for row in r._rows.get_children():
		if str(row.get_meta("bare")) == "bot@h":
			bot_row = row
	check(bot_row != null and bool(bot_row.get_meta("agent")), "bot resuelto por jid y es agente")

	# Ocupante sin jid (sala anónima): se resuelve por nick contra agentes.
	r.update_occupants([{"nick": "foo", "jid": "", "affiliation": "", "role": "participant"}])
	r.set_agent("foo@h", {"activity": "busy"}, true)
	var foo_row = null
	for row in r._rows.get_children():
		if str(row.get_meta("nick")) == "foo":
			foo_row = row
	check(foo_row != null and str(foo_row.get_meta("bare")) == "foo@h", "oculto sin jid resuelve por nick")
	check(bool(foo_row.get_meta("agent")), "resuelto por nick => agente")

	# Selección: emite el bare.
	r._on_row("foo", "foo@h")
	check(_picked.size() == 1 and _picked[0][1] == "foo@h", "selección emite bare")

	# Vacío.
	r.update_occupants([])
	check(r._empty.visible and r._rows.get_child_count() == 0, "vacío sin ocupantes")

	r.queue_free()
	if _fail == 0:
		print("ROOM_PANEL_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
