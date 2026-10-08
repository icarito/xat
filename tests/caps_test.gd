extends SceneTree

# XEP-0115 caps: parseo, string de verificación y base64(sha1).

var _fail := 0

func _init():
	var Caps = load("res://addons/xat_xmpp/xmpp/caps.gd")
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")

	var pres = Stanza.parse('<presence from="bot@h/res"><c xmlns="http://jabber.org/protocol/caps" hash="sha-1" node="https://github.com/openclaw/openclaw" ver="AbCd"/></presence>')
	var caps = Caps.parse_caps(pres)
	check(caps["present"] and caps["node"] == Caps.OPENCLAW_NODE, "parse caps node")
	check(caps["hash"] == "sha-1" and caps["ver"] == "AbCd", "parse hash/ver")
	check(Caps.is_agent(caps), "is_agent por node")

	var no_caps = Caps.parse_caps(Stanza.parse('<presence from="x@h"/>'))
	check(not no_caps["present"] and not Caps.is_agent(no_caps), "sin caps")

	# String de verificación (features ordenadas, `//` vacío).
	var features = [
		"http://jabber.org/protocol/commands",
		"http://jabber.org/protocol/disco#info",
		"http://jabber.org/protocol/disco#items",
		"urn:openclaw:telemetry:0+notify",
	]
	var expected = "automation/command-list//OpenClaw<" \
		+ "http://jabber.org/protocol/commands<" \
		+ "http://jabber.org/protocol/disco#info<" \
		+ "http://jabber.org/protocol/disco#items<" \
		+ "urn:openclaw:telemetry:0+notify<"
	check(Caps.verification_string("automation", "command-list", "OpenClaw", features) == expected, "verification string")

	# compute_ver = base64(sha1(string)), no hex.
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(expected.to_utf8())
	var want = Marshalls.raw_to_base64(ctx.finish())
	var got = Caps.compute_ver("automation", "command-list", "OpenClaw", features)
	check(got == want, "compute_ver = base64(sha1)")
	check(got.length() == 28 and got.ends_with("="), "ver es base64 de 20 bytes")
	check(Caps.compute_ver("automation", "command-list", "OpenClaw", features) == got, "compute_ver determinista")

	check(Caps.features_mark_agent(features), "features marcan agente")
	check(not Caps.features_mark_agent(["http://jabber.org/protocol/commands"]), "faltan features")

	# Caps propias (auto-anuncio + respuesta disco#info).
	var c = Caps.build_caps_child()
	check(c.get_attr("node") == Caps.XAT_NODE and c.get_attr("hash") == "sha-1" and c.get_attr("ver") == Caps.XAT_VER, "caps child")
	var dirq = Caps.build_disco_info_result("d1", "a@h", Caps.XAT_NODE)
	var dx = dirq.to_xml()
	check(dx.find('type="result"') >= 0 and dx.find('id="d1"') >= 0, "disco result iq")
	check(dx.find('node="' + Caps.XAT_NODE + '"') >= 0, "disco echo node")
	check(dx.find('<identity category="client" type="pc" name="xat"/>') >= 0, "disco identity")
	check(dx.find('<feature var="http://jabber.org/protocol/commands"/>') >= 0, "disco feature commands")

	if _fail == 0:
		print("CAPS_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
