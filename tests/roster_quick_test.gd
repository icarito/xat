extends SceneTree

# X2.3: chips de preguntas rápidas en la tarjeta del AGENTE del roster.
# Verifica el render (hasta MAX_QUESTIONS, conservando /status), que sólo los
# agentes las tienen, y que tocar un chip emite `quick_question_requested`.

var _fail := 0
var _emitted := []

func _on_quick(p_bare: String, p_text: String) -> void:
	_emitted.append([p_bare, p_text])

func _init():
	var Roster = load("res://addons/xat_xmpp/ui/roster_panel.gd")
	var Quick = load("res://addons/xat_xmpp/ui/quick_questions.gd")

	var r = Roster.new()
	get_root().add_child(r)
	check(r.has_signal("quick_question_requested"), "roster expone quick_question_requested")
	r.connect("quick_question_requested", self, "_on_quick")

	# Un agente (caps conocidas) y una persona normal.
	r.set_peers(["bot@h", "ana@h"])
	r.set_agent_state("bot@h", {"activity": "available"})
	yield(self, "idle_frame")

	var chips = r._agent_chips()
	check(chips.size() == Quick.MAX_QUESTIONS, "hasta MAX_QUESTIONS chips (%d)" % chips.size())
	check(Quick.STATUS_VALUE in chips, "conserva el chip /status")

	# La tarjeta del agente contiene los chips como botones táctiles >= 44 px.
	var agent_row = r._box.get_node_or_null(r._row_name("bot@h"))
	var chip_btn = _find_button(agent_row, str(chips[0]))
	check(chip_btn != null, "chip renderizado en la tarjeta del agente")
	if chip_btn != null:
		check(chip_btn.rect_min_size.y >= 44, "chip con toque >= 44 px")
		chip_btn.emit_signal("pressed")
		check(_emitted.size() == 1 and _emitted[0][0] == "bot@h" and _emitted[0][1] == str(chips[0]),
			"tocar un chip emite quick_question_requested(bare, texto)")

	# Una persona sin caps no lleva chips.
	var person_row = r._box.get_node_or_null(r._row_name("ana@h"))
	check(_count_buttons_matching(person_row, chips) == 0, "la fila de una persona no tiene chips")

	r.free()
	if _fail == 0:
		print("ROSTER_QUICK_CHECK_OK")
	quit()

func _find_button(p_node, p_text: String):
	if p_node is Button and p_node.text == p_text:
		return p_node
	for c in p_node.get_children():
		var hit = _find_button(c, p_text)
		if hit != null:
			return hit
	return null

func _count_buttons_matching(p_node, p_texts: Array) -> int:
	if p_node == null:
		return 0
	var n = 0
	if p_node is Button and p_node.text in p_texts:
		n += 1
	for c in p_node.get_children():
		n += _count_buttons_matching(c, p_texts)
	return n

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
