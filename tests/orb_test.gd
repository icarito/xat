extends SceneTree

# Orbe: smoke headless (instancia, estados, conectado, compacto).

var _fail := 0

func _init():
	var Orb = load("res://addons/xat_xmpp/ui/agent_orb.gd")
	var f = Orb.new()
	f.set_state({"activity": "processing", "tool": "exec", "context": {"used": 500, "max": 1000}})
	f.set_connected(false)
	get_root().add_child(f)
	yield(self, "idle_frame")
	check(abs(f.frac - 0.5) < 0.001 and f.crack > 0.99, "set_state fuera del árbol se aplica al entrar")
	var o = Orb.new()
	get_root().add_child(o)
	yield(self, "idle_frame")
	o.set_state({})
	check(o.frac == 0.0, "sin telemetría: anillo vacío")
	o.set_state({"activity": "processing", "tool": "exec", "context": {"used": 620, "max": 1000}})
	o.set_state({"activity": "pending", "tool": "", "context": {"used": 900, "max": 1000}})
	o.set_state({"activity": "paused", "context": {}})
	o.set_connected(false)
	o.set_compact(true)
	o.set_compact(false)
	o.set_connected(true)
	o.set_state({"activity": "available", "tool": "web_search", "context": {"used": 100, "max": 1000}})
	yield(create_timer(0.7), "timeout")
	check(abs(o.frac - 0.1) < 0.01, "anillo converge a used/max")
	check(o.sat_k > 0.99, "satélite visible con tool")
	o.set_state({"activity": "available", "tool": ""})
	yield(create_timer(0.7), "timeout")
	check(o.sat_k < 0.01, "satélite se apaga sin tool")
	print("DONE fail=%d" % _fail)
	OS.exit_code = 1 if _fail > 0 else 0
	quit()

func check(p_cond: bool, p_msg: String) -> void:
	if p_cond:
		print("ok   ", p_msg)
	else:
		print("FAIL ", p_msg)
		_fail += 1
