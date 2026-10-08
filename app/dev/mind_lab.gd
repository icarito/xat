extends Control

# Laboratorio del panel mente a la derecha. MIND_STEP=0 completo, 1 sin telemetría.

const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const Mind = preload("res://addons/xat_xmpp/ui/mind_panel.gd")

func _ready():
	var bg := ColorRect.new()
	bg.color = P.BG0
	bg.set_anchors_and_margins_preset(PRESET_WIDE)
	add_child(bg)
	var m = Mind.new()
	m.anchor_left = 1.0
	m.anchor_right = 1.0
	m.anchor_bottom = 1.0
	m.margin_left = -260
	add_child(m)
	m.set_agent("kangurito@xmpp.example")
	if OS.get_environment("MIND_STEP") == "1":
		m.set_state({})
		return
	m.set_state({
		"activity": "processing", "tool": "exec", "model": "deepseek/deepseek-v4-pro",
		"session_status": "running", "context": {"used": 81220, "max": 131000},
		"tokens": {"input": 300, "output": 200}, "session_cost": {"usd": 0.004}, "day_cost": {"usd": 0.01},
		"approvals": {"a1": {"state": "pending"}},
	})
	m.show_note("Modelo: deepseek-v4-pro")
