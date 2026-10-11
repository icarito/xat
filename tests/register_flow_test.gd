extends SceneTree

# Flow de registro XEP-0077 end-to-end (sin red): panel -> sesión -> transporte.
# El nativo (pre-auth real) se prueba a mano contra un servidor; acá se valida
# el cableado y los campos.

var _fail := 0
var _captured := {}

func _init():
	if not ClassDB.class_exists("XmppConnection"):
		print("FAIL: falta XmppConnection")
		OS.exit_code = 1
		quit()
		return
	var AccountPanel = load("res://addons/xat_xmpp/ui/account_panel.gd")
	var Session = load("res://addons/xat_xmpp/xmpp/session.gd")

	# Panel: campos y emisión.
	var panel = AccountPanel.new()
	panel._jid.text = "ana@example.org"
	panel._pass.text = "secreta"
	panel._email.text = "ana@mail.org"
	var fields = panel.registration_fields()
	check(fields["username"] == "ana" and fields["password"] == "secreta" and fields["email"] == "ana@mail.org", "panel: campos de XEP-0077")
	panel.connect("register_requested", self, "_on_register")
	panel._on_register()
	check(_captured.get("jid") == "ana@example.org" and _captured.get("pass") == "secreta", "panel: emite register_requested con cfg")
	# Sin datos no emite.
	_captured = {}
	panel._jid.text = ""
	panel._on_register()
	check(_captured.empty(), "panel: sin jid/contraseña no emite")

	# Sesión -> transporte (falso).
	var s = Session.new()
	var fake = FakeTransport.new()
	s._transport = fake
	var rc = s.register_account("ana@example.org", "secreta", "example.org", 5222, "")
	check(rc == 0 and fake.calls.size() == 1, "sesión: register_account llega al transporte")
	check(fake.calls[0]["jid"] == "ana@example.org" and fake.calls[0]["host"] == "example.org", "sesión: parámetros correctos")
	s.connect("register_result", self, "_on_result")
	s._on_register_result(true, "")
	check(seen.get("ok") == true, "sesión: reemite register_result")

	panel.free()
	s.free()
	if _fail == 0:
		print("REGISTER_FLOW_CHECK_OK")
	quit()

func _on_register(p_cfg: Dictionary) -> void:
	_captured = p_cfg

func _on_result(p_ok: bool, _p_message: String) -> void:
	seen["ok"] = p_ok

var seen := {}

func check(p_ok: bool, p_label: String) -> void:
	if p_ok:
		print("ok %s" % p_label)
	else:
		_fail += 1
		print("FAIL %s" % p_label)
		OS.exit_code = 1

class FakeTransport:
	signal register_result(ok, message)
	var calls := []
	func register_account(jid: String, password: String, host: String = "", port: int = 5222, cafile: String = "") -> int:
		calls.append({"jid": jid, "pass": password, "host": host, "port": port, "cafile": cafile})
		return 0
