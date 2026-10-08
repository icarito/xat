extends Control

signal canceled
signal completed(outcome)

const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const Orb = preload("res://addons/xat_xmpp/ui/agent_orb.gd")
const CONNECT_TIMEOUT := 15.0
const FADE_SECONDS := 0.32

var timeout_seconds := CONNECT_TIMEOUT
var state := "idle"
var _orb
var _status: Label
var _cancel: Button
var _timer: Timer
var _tween: Tween
var _finished := false

func _init():
	name = "StartupSplash"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	var bg := ColorRect.new()
	bg.color = P.BG0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGN_CENTER
	content.add_constant_override("separation", 12)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(content)
	_orb = Orb.new()
	_orb.rect_min_size = Vector2(280, 302)
	_orb.set_state({"activity": "processing"})
	content.add_child(_orb)
	_status = Label.new()
	_status.text = "Conectando…"
	_status.align = Label.ALIGN_CENTER
	_status.add_color_override("font_color", P.TEXT)
	content.add_child(_status)
	_cancel = Button.new()
	_cancel.text = "Cancelar"
	_cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cancel.connect("pressed", self, "_on_cancel")
	content.add_child(_cancel)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.connect("timeout", self, "_on_timeout")
	add_child(_timer)
	_tween = Tween.new()
	add_child(_tween)

func start() -> void:
	if _finished:
		return
	state = "connecting"
	_status.text = "Conectando…"
	_timer.start(timeout_seconds)
	modulate.a = 0.0
	_tween.interpolate_property(self, "modulate:a", 0.0, 1.0, 0.38, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	_tween.interpolate_property(_orb, "rect_scale", Vector2(0.82, 0.82), Vector2.ONE, 0.48, Tween.TRANS_BACK, Tween.EASE_OUT)
	_tween.start()

func show_success() -> void:
	if _finished:
		return
	state = "success"
	_timer.stop()
	_orb.set_connected(true)
	_orb.set_state({"activity": "available"})
	_cancel.visible = false
	_status.text = "Conectado"
	# CONNECTED may arrive before the entrance tween finishes.
	_tween.stop_all()
	modulate.a = 1.0
	_finish_after(0.85, "connected")

func cancel() -> void:
	if _finished:
		return
	_finished = true
	state = "canceled"
	_timer.stop()
	emit_signal("canceled")

func finish(p_outcome: String, p_status := "") -> void:
	if _finished:
		return
	_finished = true
	state = p_outcome
	_timer.stop()
	if p_status != "":
		_status.text = p_status
	_tween.stop_all()
	_tween.interpolate_property(self, "modulate:a", modulate.a, 0.0, FADE_SECONDS, Tween.TRANS_CUBIC, Tween.EASE_IN)
	_tween.start()
	yield(get_tree().create_timer(FADE_SECONDS), "timeout")
	emit_signal("completed", p_outcome)

func _finish_after(p_delay: float, p_outcome: String) -> void:
	_finished = true
	_tween.stop_all()
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = p_delay
	timer.connect("timeout", self, "_on_finish_delay", [p_outcome, timer])
	add_child(timer)
	timer.start()

func _on_finish_delay(p_outcome: String, p_timer: Timer) -> void:
	p_timer.queue_free()
	_tween.interpolate_property(self, "modulate:a", modulate.a, 0.0, FADE_SECONDS, Tween.TRANS_CUBIC, Tween.EASE_IN)
	_tween.start()
	yield(get_tree().create_timer(FADE_SECONDS), "timeout")
	state = p_outcome
	emit_signal("completed", p_outcome)

func _on_cancel() -> void:
	cancel()

func _on_timeout() -> void:
	finish("timeout")
