extends SceneTree

# X9 (JOE-82): agrupación de ocupantes por JID real (dedupe de recursos),
# secciones Agentes/Personas, roles en lenguaje humano y acciones del agente.
# Cubre la función pura Muc.group_occupants y el render de room_panel. Headless.

var _fail := 0
var _picked := []
var _mentions := []

func _on_pick(p_nick, p_bare) -> void:
	_picked.append([p_nick, p_bare])

func _on_mention(p_nick) -> void:
	_mentions.append(p_nick)

func _init():
	var Muc = load("res://addons/xat_xmpp/xmpp/muc.gd")
	var RoomPanel = load("res://addons/xat_xmpp/ui/room_panel.gd")
	var root = get_root()

	# --- Muc.group_occupants: dedupe por JID real (X9.1) ---
	var dedupe = Muc.group_occupants([
		{"nick": "Jclema", "jid": "jclema@h/phone", "affiliation": "owner", "role": "moderator"},
		{"nick": "jclema", "jid": "jclema@h/laptop", "affiliation": "member", "role": "participant"},
	])
	check(dedupe.size() == 1, "dos recursos del mismo bare => una persona")
	check(int(dedupe[0]["devices"]) == 2, "devices = 2")
	check(dedupe[0]["bare"] == "jclema@h", "bare del grupo")
	check(dedupe[0]["nicks"] == ["Jclema", "jclema"], "conserva ambos nicks")
	check(dedupe[0]["affiliation"] == "owner" and dedupe[0]["role"] == "moderator", "afiliación/rol más alto al fusionar")
	check(dedupe[0]["affiliation_label"] == "dueño" and dedupe[0]["role_label"] == "moderador", "rol en lenguaje humano")

	# Sala anónima (sin jid): NO se agrupa.
	var anon = Muc.group_occupants([
		{"nick": "ana", "jid": "", "affiliation": "none", "role": "participant"},
		{"nick": "ana2", "jid": "", "affiliation": "none", "role": "participant"},
	])
	check(anon.size() == 2, "sala anónima no agrupa")
	check(int(anon[0]["devices"]) == 1 and int(anon[1]["devices"]) == 1, "cada nick con 1 dispositivo")
	check(anon[0]["bare"] == "", "sin bare en sala anónima")

	# Agente por caps (p_agents) y resolución de nick anónimo.
	var cap = Muc.group_occupants([
		{"nick": "bot", "jid": "bot@h/res", "affiliation": "member", "role": "participant"},
	], {"bot@h": {}})
	check(cap.size() == 1 and cap[0]["kind"] == "agent" and bool(cap[0]["is_agent"]), "agente por caps/jid real")
	var cap_anon = Muc.group_occupants([
		{"nick": "bot", "jid": "", "affiliation": "", "role": ""},
	], {"bot@h": {}})
	check(cap_anon[0]["bare"] == "bot@h" and bool(cap_anon[0]["is_agent"]), "agente anónimo resuelto por nick")

	# Orden: agentes primero.
	var order = Muc.group_occupants([
		{"nick": "ana", "jid": "ana@h/x", "affiliation": "member", "role": "participant"},
		{"nick": "bot", "jid": "bot@h/res", "affiliation": "member", "role": "participant"},
	], {"bot@h": {}})
	check(order.size() == 2 and order[0]["kind"] == "agent" and order[1]["kind"] == "person", "agentes primero")

	# Etiquetas y dato ausente.
	check(Muc.affiliation_label("owner") == "dueño", "owner => dueño")
	check(Muc.affiliation_label("admin") == "admin", "admin => admin")
	check(Muc.affiliation_label("member") == "miembro", "member => miembro")
	check(Muc.affiliation_label("none") == "", "afiliación ausente => vacío")
	check(Muc.role_label("moderator") == "moderador", "moderator => moderador")
	check(Muc.role_label("participant") == "", "rol participante => vacío")
	check(Muc.group_occupants([]).empty(), "sin ocupantes => sin grupos")

	# --- room_panel: render (X9.1/X9.2/X9.3) ---
	var r1 = RoomPanel.new()
	root.add_child(r1)
	r1.set_room("sala@conf.h", "yo", [
		{"nick": "Jclema", "jid": "jclema@h/phone", "affiliation": "owner", "role": "moderator"},
		{"nick": "jclema", "jid": "jclema@h/laptop", "affiliation": "member", "role": "participant"},
	])
	check(r1.occupant_count() == 2, "dos ocupantes crudos")
	check(r1._rows.get_child_count() == 1, "render: una fila agrupada")
	var g_row = r1._rows.get_child(0)
	check(int(g_row.get_meta("devices")) == 2, "fila muestra 2 dispositivos")
	check(g_row.get_meta("bare") == "jclema@h", "fila con bare del grupo")
	r1._toggle_expand("jclema@h")
	check(r1._rows.get_child_count() == 3, "expandir lista 2 recursos")
	r1._toggle_expand("jclema@h")
	check(r1._rows.get_child_count() == 1, "colapsar vuelve a una fila")
	r1.queue_free()

	# Secciones Agentes/Personas + acciones del agente.
	var r2 = RoomPanel.new()
	root.add_child(r2)
	r2.connect("occupant_selected", self, "_on_pick")
	r2.connect("mention_requested", self, "_on_mention")
	r2.set_room("sala@conf.h", "yo", [
		{"nick": "bot", "jid": "bot@h/x", "affiliation": "member", "role": "participant"},
		{"nick": "ana", "jid": "ana@h/y", "affiliation": "member", "role": "participant"},
	])
	r2.set_agent("bot@h", {"activity": "processing"}, true)
	check(_has_label(r2._rows, "AGENTES"), "sección Agentes")
	check(_has_label(r2._rows, "PERSONAS"), "sección Personas")
	var bot_row = _row_by_bare(r2._rows, "bot@h")
	check(bot_row != null and bool(bot_row.get_meta("agent")), "fila de agente")
	check(_has_button_text(bot_row, "Mencionar") and _has_button_text(bot_row, "Ver mente"), "acciones Mencionar/Ver mente")
	r2._on_action("mention", "bot", "bot@h")
	r2._on_action("mind", "bot", "bot@h")
	check(_mentions == ["bot"], "Mencionar emite mention_requested")
	check(_picked.size() == 1 and _picked[0] == ["bot", "bot@h"], "Ver mente emite occupant_selected")
	r2.queue_free()

	# Sala anónima en el panel: sin agrupar.
	var r3 = RoomPanel.new()
	root.add_child(r3)
	r3.set_room("sala@conf.h", "yo", [
		{"nick": "ana", "jid": "", "affiliation": "none", "role": "participant"},
		{"nick": "bea", "jid": "", "affiliation": "none", "role": "participant"},
	])
	check(r3._rows.get_child_count() == 2, "panel anónimo no agrupa")
	r3.queue_free()

	if _fail == 0:
		print("MUC_DEDUPE_CHECK_OK")
	quit()

func _row_by_bare(p_parent: Node, p_bare: String):
	for c in p_parent.get_children():
		if c.get_meta("bare") != null and str(c.get_meta("bare")) == p_bare:
			return c
	return null

func _has_label(p_parent: Node, p_text: String) -> bool:
	for c in p_parent.get_children():
		if c is Label and c.text == p_text:
			return true
	return false

func _has_button_text(p_node: Node, p_text: String) -> bool:
	if p_node is Button and p_node.text == p_text:
		return true
	for c in p_node.get_children():
		if _has_button_text(c, p_text):
			return true
	return false

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
