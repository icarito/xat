extends SceneTree

# Sesión: los eventos PEP (telemetría/hooks) se rutean a agent_model y señales,
# y no se tratan como mensajes de chat. Sin _ready: no toca el transporte.

var _fail := 0
var _states := []
var _hooks := []
var _msgs := 0
var _dirs := []
var _last := {}

func _init():
	var s = load("res://addons/xat_xmpp/xmpp/session.gd").new()
	s.connect("agent_state_changed", self, "_on_state")
	s.connect("agent_hook", self, "_on_hook")
	s.connect("message_received", self, "_on_msg")
	var ev = '<message from="bot@h/res" type="headline"><event xmlns="http://jabber.org/protocol/pubsub#event"><items node="%s"><item id="i">%s</item></items></event></message>'
	s._on_stanza(ev % ["urn:openclaw:telemetry:0", '<telemetry xmlns="urn:openclaw:telemetry:0" activity="processing"><context used="100" max="1000"/><tool>exec</tool></telemetry>'])
	check(_states.size() == 1 and _states[0][0] == "bot@h", "telemetría -> agent_state_changed con bare")
	check(s.agent_model.get_state("bot@h")["tool"] == "exec", "agent_model guarda tool")
	s._on_stanza(ev % ["urn:openclaw:hooks:approval:0", '<event xmlns="urn:openclaw:hooks:approval:0" version="1">{"event":"approval","state":"pending","approvalId":"a1","expiresAtMs":null}</event>'])
	check(_hooks.size() == 1 and _hooks[0]["approvalId"] == "a1", "hook approval -> agent_hook")
	check(s.agent_model.pending_approvals("bot@h", 0).size() == 1, "aprobación pendiente registrada")
	check(_msgs == 0, "PEP no se emite como mensaje")

	# MAM trae ambos sentidos: lo propio sale como "out", lo del agente como "in".
	s._bare = "me@h"
	var mam = '<message to="me@h/xat"><result xmlns="urn:xmpp:mam:2" queryid="q" id="%s"><forwarded xmlns="urn:xmpp:forward:0"><message xmlns="jabber:client" type="chat" from="%s" to="%s" id="%s"><body>x</body></message></forwarded></result></message>'
	s._on_stanza(mam % ["a1", "me@h/xat", "bot@h", "m1"])
	s._on_stanza(mam % ["a2", "bot@h/oc", "me@h", "m2"])
	check(_last.get("direction") == "in" and _dirs == ["out", "in"], "MAM: dirección según from")
	# OMEMO sin body: se muestra un aviso en vez de perderse.
	var before = _msgs
	s._on_stanza('<message type="chat" from="bot@h/oc" to="me@h/xat" id="e1"><encrypted xmlns="urn:xmpp:omemo:2"><header sid="1"/><payload>x</payload></encrypted></message>')
	check(_msgs == before + 1 and _last.get("encrypted", false) and str(_last.get("body")).find("OMEMO") >= 0, "OMEMO: aviso visible")

	# disco#info con node#ver (como pregunta Prosody) se responde con +notify.
	var Caps = load("res://addons/xat_xmpp/xmpp/caps.gd")
	var fake = FakeTransport.new()
	s._transport = fake
	s._on_stanza('<iq type="get" id="d1" from="hablar.example"><query xmlns="http://jabber.org/protocol/disco#info" node="%s#%s"/></iq>' % [Caps.XAT_NODE, Caps.XAT_VER])
	check(fake.sent.size() == 1 and fake.sent[0].find("urn:openclaw:telemetry:0+notify") >= 0 and fake.sent[0].find("#" + Caps.XAT_VER) >= 0, "disco#info node#ver respondido")
	s.free()
	if _fail == 0:
		print("SESSION_PEP_CHECK_OK")
	quit()

func _on_state(p_bare, p_state):
	_states.append([p_bare, p_state])

func _on_hook(_p_bare, p_hook):
	_hooks.append(p_hook)

func _on_msg(p_rec):
	_msgs += 1
	_dirs.append(p_rec.get("direction"))
	_last = p_rec

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1

class FakeTransport:
	var sent = []
	func send(p_xml):
		sent.append(p_xml)
		return 0
