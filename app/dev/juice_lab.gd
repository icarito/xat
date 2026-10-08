extends Control

# Laboratorio de juice: un botón por sonido, burst+pop y toggles de ajustes.

const Palette = preload("res://addons/xat_xmpp/ui/palette.gd")
const Juice = preload("res://addons/xat_xmpp/ui/juice.gd")

func _ready():
	var j = Juice.new()
	add_child(j)
	var bg = ColorRect.new()
	bg.color = Palette.BG0
	bg.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(bg)
	var box = VBoxContainer.new()
	box.set_anchors_and_margins_preset(Control.PRESET_WIDE, Control.PRESET_MODE_MINSIZE, 20)
	add_child(box)
	for n in ["send", "receive", "tool_start", "tool_done", "approve", "alert"]:
		var b = Button.new()
		b.text = n
		b.connect("pressed", j, "play", [n])
		box.add_child(b)
	var fx = Button.new()
	fx.text = "burst + pop"
	fx.connect("pressed", self, "_fx", [j, fx])
	box.add_child(fx)
	for k in ["sound_enabled", "motion_enabled"]:
		var cb = CheckBox.new()
		cb.text = k
		cb.pressed = j.settings[k]
		cb.connect("toggled", j, "set_setting", [k])
		box.add_child(cb)
	if OS.get_environment("JUICE_BURST") == "1":
		yield(get_tree(), "idle_frame")
		j.burst(get_viewport_rect().size / 2, Palette.AGENT_EDGE, 24)

func _fx(j, b):
	var c = b.get_global_rect().position + b.rect_size / 2
	j.burst(c, Palette.TOOL)
	j.pop(b)
