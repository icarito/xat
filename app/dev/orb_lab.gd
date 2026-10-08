extends Control

# Laboratorio del orbe: línea de tiempo guionada. ORB_STEP=<n> congela el paso n.

const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const Orb = preload("res://addons/xat_xmpp/ui/agent_orb.gd")

# [activity, ctx %, tool, conectado]
const STEPS := [
	["available", 10, "", true], ["processing", 40, "", true],
	["processing", 62, "exec", true], ["pending", 70, "", true],
	["processing", 90, "web_search", true], ["paused", 90, "", true],
	["available", 90, "", false],
]

var _big
var _small := []
var _step := 0

func _ready():
	var bg := ColorRect.new()
	bg.color = P.BG0
	bg.set_anchors_and_margins_preset(PRESET_WIDE)
	add_child(bg)
	_big = Orb.new()
	_big.rect_min_size = Vector2(280, 302)
	_big.rect_position = Vector2(350, 40)
	_big.rect_size = Vector2(280, 302)
	add_child(_big)
	for i in int(OS.get_environment("ORB_N")) if OS.get_environment("ORB_N") != "" else 3:
		var o = Orb.new()
		o.set_compact(true)
		o.rect_position = Vector2(400 + i * 80, 400)
		o.rect_size = Vector2(48, 48)
		add_child(o)
		_small.append(o)
	var fixed = OS.get_environment("ORB_STEP")
	if fixed != "":
		_show(int(fixed))
		return
	_show(0)
	var t := Timer.new()
	t.wait_time = 1.5
	t.autostart = true
	t.connect("timeout", self, "_next")
	add_child(t)

func _next():
	_step += 1
	_show(_step)

func _show(n: int):
	_apply(_big, n)
	for i in _small.size():
		_apply(_small[i], n if OS.get_environment("ORB_SAME") != "" else n + 2 * i)

func _apply(o, n: int):
	var s = STEPS[n % STEPS.size()]
	o.set_connected(s[3])
	o.set_state({"activity": s[0], "tool": s[2], "context": {"used": s[1] * 10, "max": 1000}})
