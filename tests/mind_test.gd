extends SceneTree

# Panel mente: smoke headless (estados, formato, chips).

var _fail := 0
var _got := []

func _init():
	var Mind = load("res://addons/xat_xmpp/ui/mind_panel.gd")
	var m = Mind.new()
	get_root().add_child(m)
	yield(self, "idle_frame")
	check(Mind.fmt_n(12000.0) == "12.0k" and Mind.fmt_n(131000.0) == "131k" and Mind.fmt_n(950.0) == "950" and Mind.fmt_n(1200000.0) == "1.2M", "fmt_n k/M")
	m.set_agent("bot@h")
	m.set_state({})
	check(not m._badge.visible and m._grid.get_child_count() == 1, "vacío: sólo 'sin telemetría'")
	m.set_state({"activity": "processing", "tool": "exec", "model": "a/b-c", "context": {"used": 12000, "max": 131000},
		"tokens": {"input": 300, "output": 200}, "session_cost": {"usd": 0.004}, "day_cost": {"usd": 0.01},
		"approvals": {"x": {"state": "pending"}, "y": {"state": "approved"}}})
	check(m._model.text == "b-c" and m._badge.visible, "modelo corto y badge de aprobaciones")
	check(m._grid.get_child_count() == 8, "4 filas con datos")
	m.set_connected(false)
	m.show_note("hola")
	m.connect("command_requested", self, "_on_cmd")
	var btns := []
	_find(m, btns)
	for b in btns:
		if b.text == "abort":
			b.emit_signal("pressed")
	check(_got == ["abort"], "chip emite command_requested")
	print("DONE fail=%d" % _fail)
	OS.exit_code = 1 if _fail > 0 else 0
	quit()

func _on_cmd(p_node):
	_got.append(p_node)

func _find(n: Node, out: Array) -> void:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_find(c, out)

func check(p_cond: bool, p_msg: String) -> void:
	if p_cond:
		print("ok   ", p_msg)
	else:
		print("FAIL ", p_msg)
		_fail += 1
