extends SceneTree

# Splash lifecycle only: no account file, session, credentials, or network.

var _fail := 0
var _outcome := ""
var _canceled := false

func _init():
	var Splash = load("res://addons/xat_xmpp/ui/startup_splash.gd")
	var cancel_splash = Splash.new()
	get_root().add_child(cancel_splash)
	cancel_splash.connect("canceled", self, "_on_canceled")
	cancel_splash.connect("completed", self, "_on_completed")
	cancel_splash.start()
	check(cancel_splash.state == "connecting" and cancel_splash._orb._state.get("activity") == "processing", "splash shows connecting activity")
	cancel_splash._cancel.emit_signal("pressed")
	check(_canceled and cancel_splash.state == "canceled", "cancel button emits canceled")
	cancel_splash.queue_free()

	var success_splash = Splash.new()
	get_root().add_child(success_splash)
	success_splash.connect("completed", self, "_on_completed")
	success_splash.start()
	success_splash.show_success()
	check(success_splash.state == "success" and not success_splash._cancel.visible, "success removes cancel action")
	yield(create_timer(1.25), "timeout")
	check(_outcome == "connected" and success_splash.is_queued_for_deletion() == false, "success completes after its fade")
	success_splash.queue_free()

	var timeout_splash = Splash.new()
	timeout_splash.timeout_seconds = 0.02
	get_root().add_child(timeout_splash)
	timeout_splash.connect("completed", self, "_on_completed")
	timeout_splash.start()
	yield(create_timer(0.5), "timeout")
	check(_outcome == "timeout", "bounded startup emits timeout outcome")
	timeout_splash.queue_free()

	print("DONE fail=%d" % _fail)
	OS.exit_code = 1 if _fail > 0 else 0
	quit()

func _on_canceled() -> void:
	_canceled = true

func _on_completed(p_outcome: String) -> void:
	_outcome = p_outcome

func check(p_cond: bool, p_msg: String) -> void:
	if p_cond:
		print("ok   ", p_msg)
	else:
		print("FAIL ", p_msg)
		_fail += 1
