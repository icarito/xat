extends SceneTree

# End-to-end Main startup lifecycle with fake credentials and a mock autoconnect
# hook. The shell runner sets XDG_DATA_HOME to /tmp/xat-startup-flow.

const ACCOUNT_PATH := "user://account.json"
const SAFE_USER_DATA_PREFIX := "/tmp/xat-startup-flow"
const FAKE_ACCOUNT := {
	"jid": "startup-test@example.invalid",
	"pass": "fixture-only-password",
	"host": "example.invalid",
	"port": 5222,
	"cafile": "",
}

var _fail := 0
var _original_autoconnect := ""
var _retry_step := ""
var _outcome := ""
var _Session

func _init():
	# Guard before touching account.json; fail closed if Godot ignored XDG_DATA_HOME.
	if not OS.get_user_data_dir().begins_with(SAFE_USER_DATA_PREFIX):
		print("FAIL user data is outside the test temp directory")
		OS.exit_code = 1
		quit()
		return

	_original_autoconnect = OS.get_environment("XAT_AUTOCONNECT")
	OS.set_environment("XAT_AUTOCONNECT", "")
	_Session = load("res://addons/xat_xmpp/xmpp/session.gd")
	_clear_account()

	# X1.1: pasos reales del splash (marca, anillo, fallo + Reintentar, skip MAM).
	yield(_check_splash_steps(), "completed")

	# No saved account keeps the normal login form visible.
	var empty_main = _new_main()
	check(empty_main._account.visible and empty_main._startup_splash == null, "no credentials leaves login visible")
	yield(self, "idle_frame")
	check(not empty_main.autoconnect_attempted, "no credentials does not autoconnect")
	empty_main.queue_free()
	yield(self, "idle_frame")

	# A complete fake fixture hides the account synchronously, then runs only the
	# mock hook on the deferred autoconnect turn.
	_write_fake_account()
	var auth_main = _new_main()
	check(not auth_main._account.visible and auth_main._startup_splash.visible, "stored credentials hide login before first frame")
	yield(self, "idle_frame")
	check(auth_main.autoconnect_attempted, "stored credentials schedule autoconnect hook")
	check(auth_main._startup_splash != null and auth_main._split.visible == false, "startup overlay remains until connection outcome")
	auth_main._on_auth_failed()
	check(auth_main._account.visible, "auth failure reveals login immediately")
	yield(create_timer(0.45), "timeout")
	check(auth_main._startup_splash == null and auth_main._account.visible, "auth failure removes splash after fade")
	auth_main.queue_free()
	yield(self, "idle_frame")

	# Cancellation calls Session.disconnect_account; the fixture never opens a
	# transport because its _autoconnect override only records the call.
	var cancel_main = _new_main()
	yield(self, "idle_frame")
	cancel_main._startup_splash.cancel()
	check(cancel_main._account.visible and cancel_main._startup_splash == null, "cancel reveals login and removes splash")
	check(cancel_main.session.state == _Session.State.DISCONNECTED, "cancel leaves session disconnected")
	cancel_main.queue_free()
	yield(self, "idle_frame")

	# Simulate the session's CONNECTED signal. The app view appears immediately;
	# the splash finishes its short success hold/fade and is then freed.
	var connected_main = _new_main()
	connected_main._on_state_changed(_Session.State.CONNECTED)
	check(connected_main._split.visible and not connected_main._account.visible, "connected state reveals app panels")
	yield(create_timer(1.35), "timeout")
	check(connected_main._startup_splash == null, "successful splash is removed after fade")
	connected_main.queue_free()
	yield(self, "idle_frame")

	# Explicit opt-out leaves the form available even with a complete account.
	OS.set_environment("XAT_AUTOCONNECT", "0")
	var optout_main = _new_main()
	check(optout_main._account.visible and optout_main._startup_splash == null, "XAT_AUTOCONNECT=0 keeps login visible")
	yield(self, "idle_frame")
	check(not optout_main.autoconnect_attempted, "explicit opt-out skips autoconnect")
	optout_main.queue_free()
	yield(self, "idle_frame")

	_clear_account()
	OS.set_environment("XAT_AUTOCONNECT", _original_autoconnect)
	print("DONE fail=%d" % _fail)
	OS.exit_code = 1 if _fail > 0 else 0
	quit()

func _new_main():
	var fixture_path = ProjectSettings.globalize_path("res://").plus_file("../tests/fixtures/startup_main_mock.gd")
	var MainMock = load(fixture_path)
	var main = MainMock.new()
	get_root().add_child(main)
	return main

func _write_fake_account() -> void:
	var file := File.new()
	file.open(ACCOUNT_PATH, File.WRITE)
	file.store_string(to_json(FAKE_ACCOUNT))
	file.close()

func _clear_account() -> void:
	var file := File.new()
	if file.file_exists(ACCOUNT_PATH):
		Directory.new().remove(ACCOUNT_PATH)

func check(p_condition: bool, p_label: String) -> void:
	if p_condition:
		print("ok   ", p_label)
	else:
		_fail += 1
		print("FAIL ", p_label)

# X1.1: el splash muestra los pasos reales; un paso no confirmado nunca es verde
# y el anillo sólo avanza con pasos confirmados (honestidad P1).
func _check_splash_steps():
	var Splash = load("res://addons/xat_xmpp/ui/startup_splash.gd")
	var s = Splash.new()
	get_root().add_child(s)
	s.start()
	check(s.step_status("tls") == "active", "start marks TLS active")
	check(s.steps_done() == 0, "no step is done before confirmation")
	check(s._orb._state.get("context", {}).get("used", -1) == 0, "ring starts empty")
	s.set_step("tls", "done")
	check(s.step_status("tls") == "done" and s._step_rows["tls"]["indicator"].text == "✓", "confirmed step gets a check mark")
	check(s._orb._state.get("context", {}).get("used", -1) == 1, "ring advances with each confirmed step")
	s.set_step("sasl", "done")
	s.set_step("roster", "done")
	s.set_step("fleet", "done")
	check(s.steps_done() == 4 and s._orb._state.get("context", {}).get("used", -1) == 4, "ring follows confirmed steps")
	s.fail_step("mam", "sin respuesta del servidor")
	check(s.step_status("mam") == "failed" and s.steps_done() == 4, "failed step is not counted as done")
	check(s._step_rows["mam"]["retry"].visible and s._step_rows["mam"]["reason"].visible, "failed step shows reason and Reintentar")
	check(s._step_rows["mam"]["reason"].text == "sin respuesta del servidor", "failure reason is shown verbatim")
	check(s._step_rows["mam"]["indicator"].text == "×", "failed step indicator is a red x")
	s.connect("retry_requested", self, "_on_retry_requested")
	s._step_rows["mam"]["retry"].emit_signal("pressed")
	check(s.step_status("mam") == "active" and _retry_step == "mam", "Reintentar re-arms the step and requests a retry")
	s.queue_free()
	yield(self, "idle_frame")

	# show_success() con wait_for_history: espera MAM y ofrece "Entrar sin esperar".
	var s2 = Splash.new()
	s2.wait_for_history = true
	get_root().add_child(s2)
	s2.start()
	s2.show_success()
	check(s2.state == "success" and s2._skip_history.visible, "success with pending history offers Entrar sin esperar")
	check(s2.step_status("tls") == "done" and s2.step_status("sasl") == "done", "CONNECTED confirms TLS and SASL")
	check(s2.step_status("mam") != "done", "history stays unconfirmed until MAM arrives")
	_outcome = ""
	s2.connect("completed", self, "_on_completed")
	s2._skip_history.emit_signal("pressed")
	yield(create_timer(0.45), "timeout")
	check(_outcome == "connected", "Entrar sin esperar completes as connected")
	check(s2.step_status("mam") != "done", "skipping history does not fake MAM as done")
	s2.queue_free()
	yield(self, "idle_frame")

	# bind_session: las señales reales de la sesión mueven los pasos.
	var s3 = Splash.new()
	var fake = FakeSession.new()
	get_root().add_child(s3)
	get_root().add_child(fake)
	s3.start()
	s3.bind_session(fake, "fleet@example.invalid", "urn:openclaw:fleet:0")
	fake.set_connected(true)
	fake.emit_signal("state_changed", 2)
	check(s3.step_status("tls") == "done" and s3.step_status("sasl") == "done", "session CONNECTED confirms TLS+SASL")
	check(s3.step_status("roster") == "active", "roster becomes active after connect")
	fake.emit_signal("roster_changed")
	check(s3.step_status("roster") == "done", "roster_changed completes the roster step")
	fake.emit_signal("pubsub_items_received", "fleet@example.invalid", "urn:openclaw:fleet:0", [])
	check(s3.step_status("fleet") == "done", "fleet snapshot completes the fleet step")
	fake.emit_signal("history_fetched", "a@b", [], true)
	check(s3.step_status("mam") == "done", "history_fetched completes MAM")
	check(s3.steps_done() == 5, "all real steps finish in order")
	fake.emit_signal("auth_failed")
	check(s3.step_status("sasl") != "failed", "auth_failed after success does not regress a done step")
	s3.queue_free()
	fake.queue_free()
	yield(self, "idle_frame")

	# auth_failed vía la sesión marca SASL en rojo, nunca verde.
	var s4 = Splash.new()
	var f2 = FakeSession.new()
	get_root().add_child(s4)
	get_root().add_child(f2)
	s4.start()
	s4.bind_session(f2)
	f2.emit_signal("auth_failed")
	check(s4.step_status("sasl") == "failed" and s4.steps_done() == 0, "auth_failed marks SASL failed, not done")
	s4.queue_free()
	f2.queue_free()
	yield(self, "idle_frame")

	# finish("auth_failed") de main.gd también refleja el paso fallido.
	var s5 = Splash.new()
	get_root().add_child(s5)
	s5.start()
	s5.finish("auth_failed")
	check(s5.step_status("sasl") == "failed", "finish(auth_failed) surfaces the failed SASL step")
	s5.queue_free()
	yield(self, "idle_frame")

func _on_retry_requested(p_step: String) -> void:
	_retry_step = p_step

func _on_completed(p_outcome: String) -> void:
	_outcome = p_outcome

# Doble mínimo de Session: sólo las señales y el predicado que consume el splash.
class FakeSession:
	extends Node

	signal state_changed(state)
	signal roster_changed()
	signal history_fetched(bare_jid, rows, complete)
	signal auth_failed()
	signal pubsub_items_received(from_jid, node, items)

	var _connected := false

	func set_connected(p_connected: bool) -> void:
		_connected = p_connected

	func is_connected_to_server() -> bool:
		return _connected

