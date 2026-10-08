extends SceneTree

# PEP: avatar (XEP-0084) y telemetría de OpenClaw (payload XML).

var _fail := 0

func _init():
	var Pep = load("res://addons/xat_xmpp/xmpp/pep.gd")
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")

	# Avatar metadata.
	var meta_msg = Stanza.parse('<message from="bot@h" type="headline"><event xmlns="http://jabber.org/protocol/pubsub#event">' \
		+ '<items node="urn:xmpp:avatar:metadata"><item id="abc123">' \
		+ '<metadata xmlns="urn:xmpp:avatar:metadata"><info id="abc123" bytes="4096" type="image/png"/></metadata>' \
		+ '</item></items></event></message>')
	var ev = Pep.parse_event(meta_msg)
	check(ev["node"] == "urn:xmpp:avatar:metadata" and ev["item_id"] == "abc123", "evento avatar metadata")
	var meta = Pep.parse_avatar_metadata(ev)
	check(meta["id"] == "abc123" and meta["bytes"] == 4096 and meta["type"] == "image/png", "avatar metadata")

	# Avatar data.
	var data_msg = Stanza.parse('<message from="bot@h" type="headline"><event xmlns="http://jabber.org/protocol/pubsub#event">' \
		+ '<items node="urn:xmpp:avatar:data"><item id="abc123">' \
		+ '<data xmlns="urn:xmpp:avatar:data">aGVsbG8=</data></item></items></event></message>')
	var data = Pep.parse_avatar_data(Pep.parse_event(data_msg))
	check(data["id"] == "abc123" and data["base64"] == "aGVsbG8=", "avatar data")

	# Retract.
	var retract = Pep.parse_event(Stanza.parse('<message from="bot@h"><event xmlns="http://jabber.org/protocol/pubsub#event">' \
		+ '<items node="urn:xmpp:avatar:metadata"><retract id="old"/></items></event></message>'))
	check(retract["retract"] and retract["item_id"] == "old", "retract")

	# Telemetría.
	var tel_msg = Stanza.parse('<message from="bot@h/res" type="headline"><event xmlns="http://jabber.org/protocol/pubsub#event">' \
		+ '<items node="urn:openclaw:telemetry:0"><item id="current">' \
		+ '<telemetry xmlns="urn:openclaw:telemetry:0" activity="available" availability="available">' \
		+ '<context used="12000" max="131072" scope="active" maxSource="config"/>' \
		+ '<tokens total="500" input="300" output="200" requests="5" scope="session"/>' \
		+ '<cost usd="0.0012" scope="last-request"/>' \
		+ '<session-cost usd="0.0040" scope="session"/>' \
		+ '<day-cost usd="0.0100" scope="day-local"/>' \
		+ '<model>deepseek/deepseek-v4-pro</model><tool>exec</tool><session status="running"/>' \
		+ '</telemetry></item></items></event></message>')
	var tel = Pep.parse_telemetry(Pep.parse_event(tel_msg))
	check(tel["activity"] == "available" and tel["availability"] == "available", "telemetry actividad")
	check(tel["context"]["used"] == 12000 and tel["context"]["max"] == 131072 and tel["context"]["scope"] == "active", "telemetry context")
	check(tel["tokens"]["total"] == 500 and tel["tokens"]["requests"] == 5, "telemetry tokens")
	check(abs(tel["cost"]["usd"] - 0.0012) < 0.00001, "telemetry cost")
	check(tel["model"] == "deepseek/deepseek-v4-pro" and tel["tool"] == "exec", "telemetry model/tool")
	check(tel["session_status"] == "running", "telemetry session status")

	# Hooks OpenClaw: JSON en el texto de un <event xmlns="urn:openclaw:hooks:...">.
	var hook_ev = '<event xmlns="http://jabber.org/protocol/pubsub#event"><items node="%s"><item id="x">' \
		+ '<event xmlns="%s" version="1">%s</event></item></items></event>'

	# approval.
	var appr = Pep.parse_hook(Pep.parse_event(Stanza.parse('<message from="bot@h/res">'
		+ (hook_ev % ["urn:openclaw:hooks:approval:0", "urn:openclaw:hooks:approval:0",
			'{"contractVersion":1,"event":"approval","state":"pending","approvalId":"a1","expiresAtMs":2000,"jid":"bot@h"}'])
		+ '</message>')))
	check(appr["event"] == "approval" and appr["state"] == "pending" and appr["approvalId"] == "a1" and appr["expiresAtMs"] == 2000, "hook approval")

	# activity.
	var act = Pep.parse_hook(Pep.parse_event(Stanza.parse('<message from="bot@h/res">'
		+ (hook_ev % ["urn:openclaw:hooks:activity:0", "urn:openclaw:hooks:activity:0",
			'{"contractVersion":1,"event":"activity","state":"processing"}'])
		+ '</message>')))
	check(act["event"] == "activity" and act["state"] == "processing", "hook activity")

	# progress.
	var prog = Pep.parse_hook(Pep.parse_event(Stanza.parse('<message from="bot@h/res">'
		+ (hook_ev % ["urn:openclaw:hooks:progress:0", "urn:openclaw:hooks:progress:0",
			'{"contractVersion":1,"event":"progress","state":"start","detail":"exec ls"}'])
		+ '</message>')))
	check(prog["event"] == "progress" and prog["state"] == "start" and prog["detail"] == "exec ls", "hook progress")

	# JSON inválido -> {}.
	var bad_json = Pep.parse_hook(Pep.parse_event(Stanza.parse('<message>'
		+ (hook_ev % ["urn:openclaw:hooks:activity:0", "urn:openclaw:hooks:activity:0", "{not json}"])
		+ '</message>')))
	check(bad_json.empty(), "hook json inválido")

	# Nodo que no es hook (telemetría) -> {}.
	check(Pep.parse_hook(Pep.parse_event(tel_msg)).empty(), "hook node no-hook")

	# xmlns del payload distinto del nodo -> {}.
	var mismatch = Pep.parse_hook(Pep.parse_event(Stanza.parse('<message>'
		+ (hook_ev % ["urn:openclaw:hooks:activity:0", "urn:openclaw:hooks:progress:0", '{"event":"activity"}'])
		+ '</message>')))
	check(mismatch.empty(), "hook xmlns mismatch")

	if _fail == 0:
		print("PEP_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
