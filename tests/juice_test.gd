extends SceneTree

# Juice: parser WAV manual, ajustes (round-trip), no-ops con sonido/movimiento
# apagados y burst/pop/shake sin error.

var _fail := 0

func _init():
	var Juice = load("res://addons/xat_xmpp/ui/juice.gd")
	for n in ["send", "receive", "tool_start", "tool_done", "approve", "alert"]:
		var s = Juice.load_wav("res://sfx/%s.wav" % n)
		check(s != null and s.mix_rate == 44100 and s.data.size() > 0 and not s.stereo, "wav %s" % n)

	var j = Juice.new()
	j.settings_path = "user://juice_test_settings.json"
	get_root().add_child(j)
	var c = Control.new()
	c.rect_size = Vector2(40, 20)
	get_root().add_child(c)

	j.set_setting("sound_enabled", false)
	j.play("receive")
	check(j._last.empty(), "play sin sonido es no-op")
	j.set_setting("sound_enabled", true)
	j.play("receive")
	check(j._last.has("receive"), "play con sonido")
	var t0 = j._last["receive"]
	j.play("receive")
	check(j._last["receive"] == t0, "throttle 80ms")

	j.set_setting("volume_db", -20.0)
	j.set_setting("motion_enabled", false)
	var j2 = Juice.new()
	j2.settings_path = j.settings_path
	j2.load_settings()
	check(j2.settings["volume_db"] == -20.0 and j2.settings["motion_enabled"] == false and j2.settings["sound_enabled"], "ajustes round-trip")

	j.burst(Vector2(50, 50), Color.red)
	j.pop(c)
	j.shake(c)
	check(c.rect_scale == Vector2.ONE and j._layer.get_child_count() == 0, "movimiento apagado: no-op")
	j.set_setting("motion_enabled", true)
	j.burst(Vector2(50, 50), Color.red)
	j.pop(c)
	j.shake(c)
	j.haptic()
	j.haptic("no-existe")
	j.set_setting("haptics_enabled", false)
	j.haptic("alert")
	j.set_setting("haptics_enabled", true)
	var well_formed = true
	for k in j.HAPTICS:
		for pulse in j.HAPTICS[k]:
			well_formed = well_formed and pulse.size() == 3 and pulse[0] >= 0.0 and pulse[0] <= 1.0 and pulse[1] >= 0.0 and pulse[1] <= 1.0 and pulse[2] > 0
	check(well_formed and j.HAPTICS.has("alert") and j.HAPTICS.has("success"), "patrones hápticos bien formados")
	check(j._layer.get_child_count() == 1, "burst crea partículas")
	yield(create_timer(0.5), "timeout")
	check(abs(c.rect_scale.x - 1.0) < 0.05, "pop vuelve a 1")

	Directory.new().remove(j.settings_path)
	if _fail == 0:
		print("JUICE_CHECK_OK")
	quit()

func check(cond: bool, label: String):
	if cond:
		print("ok ", label)
	else:
		print("FAIL ", label)
		_fail += 1
		OS.exit_code = 1
