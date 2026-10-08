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
