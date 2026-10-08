extends SceneTree

# Tool card, approval card y su integración en el chat (sin red).

var _fail := 0
var _got := []

func _init():
	var Panel = load("res://addons/xat_xmpp/ui/chat_panel.gd")
	var c = Panel.new()
	get_root().add_child(c)
	c.connect("quick_selected", self, "_on_quick")
	c.connect("action_selected", self, "_on_action")
	c.set_peer("a@h")
	c.add_message({"from": "a@h", "body": "¿apruebo?", "direction": "in", "timestamp": "2026-01-01T10:00:00Z", "id": "m1"})

	c.tool_started("bash", "ls")
	check(c._tool != null and c._tool.state == "running", "tool card corriendo")
	c.tool_finished(true)
	check(c._tool.state == "ok", "tool card ok")
	c.tool_started("read")
	c.tool_finished(false)
	check(c._tool.state == "err", "tool card err")

	var expiry = float(OS.get_unix_time()) * 1000.0 + 45000.0
	c.set_actions({"id": "m1", "quick_responses": [{"value": "si", "label": "Sí"}, {"value": "no", "label": "No"}], "commands": [{"node": "cmd:1", "name": "Allow"}]})
	check(c._card != null and c._actions.get_child_count() == 3, "approval card con 3 botones")
	c.apply_approval_hook({"event": "approval", "state": "pending", "stanzaId": "m1", "expiresAtMs": expiry, "command": "rm -rf x"})
	check(c._card._ring.visible and c._card._cmd.text == "rm -rf x", "hook trae anillo y comando")
	c._actions.get_child(0).emit_signal("pressed")
	check(_got == ["quick:si"] and c._card.sealed, "click emite quick_selected y sella")
	c.apply_approval_hook({"event": "approval", "state": "expired", "stanzaId": "m1"})
	check(c._card.sealed, "hook posterior no rompe card sellada")

	# Hook expirado sella una card pendiente.
	c.set_actions({"id": "m1", "quick_responses": [{"value": "si", "label": "Sí"}]})
	c.apply_approval_hook({"state": "expired", "stanzaId": "m1"})
	check(c._card.sealed and c._card._stamp.text == "Expirado", "expirado sella la card")

	c.set_thinking(true)
	check(c._state.visible and "pensando" in c._state.bbcode_text, "indicador pensando")
	c.set_thinking(false)
	check(not c._state.visible, "pensando apagado")
	check(c.header_slot is HBoxContainer, "header_slot")

	c.free()
	if _fail == 0:
		print("CARDS_CHECK_OK")
	quit()

func _on_quick(_b, v) -> void:
	_got.append("quick:" + v)

func _on_action(_b, _i) -> void:
	_got.append("action")

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
