extends SceneTree

# Roster en vivo: un roster push del servidor debe aplicar el modelo y emitir
# roster_changed (la vista se rearma con eso). Presencia, idem.

var _fail := 0
var _roster_events := 0
var _presence_events := 0

func _init():
	var Session = load("res://addons/xat_xmpp/xmpp/session.gd")
	var s = Session.new()
	s._transport = FakeTransport.new()
	var before = s.roster_model.bare_jids().size()
	s.connect("roster_changed", self, "_on_roster")
	s.connect("presence_changed", self, "_on_presence")

	# Alta por push (otro recurso/otro cliente).
	s._on_stanza('<iq type="set" id="p1" to="me@h/r"><query xmlns="jabber:iq:roster"><item jid="nuevo@h" name="Nuevo" subscription="both"/></query></iq>')
	check(_roster_events >= 1, "push de roster emite roster_changed")
	check(s.roster_model.bare_jids().has("nuevo@h"), "el contacto nuevo entra al modelo")
	check(s.roster_model.bare_jids().size() == before + 1, "el modelo crece en runtime")

	# Baja por push.
	s._on_stanza('<iq type="set" id="p2" to="me@h/r"><query xmlns="jabber:iq:roster"><item jid="nuevo@h" subscription="remove"/></query></iq>')
	check(not s.roster_model.bare_jids().has("nuevo@h"), "el push de baja lo saca")

	# Presencia.
	s._on_stanza('<presence from="agente@h/x"><show>chat</show></presence>')
	check(_presence_events >= 1, "presencia emite presence_changed")
	check(s.presence_model.is_online("agente@h"), "la presencia actualiza el modelo")

	s.free()
	if _fail == 0:
		print("ROSTER_LIVE_CHECK_OK")
	quit()

func _on_roster() -> void:
	_roster_events += 1

func _on_presence(_p_bare: String) -> void:
	_presence_events += 1

func check(p_ok: bool, p_label: String) -> void:
	if p_ok:
		print("ok %s" % p_label)
	else:
		_fail += 1
		print("FAIL %s" % p_label)
		OS.exit_code = 1

class FakeTransport:
	var sent := []
	func send(p_xml: String) -> int:
		sent.append(p_xml)
		return 0
