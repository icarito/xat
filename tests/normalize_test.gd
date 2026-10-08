extends SceneTree

# Normalización de objetivos/stanzas y corte de cuerpos largos.

var _fail := 0

func _init():
	var N = load("res://addons/xat_xmpp/xmpp/normalize.gd")

	check(N.bare_jid("a@b/res") == "a@b", "bare_jid")
	check(N.bare_jid("a@b") == "a@b", "bare_jid sin recurso")

	check(N.is_group_jid("sala@conference.h/res", "conference.h"), "is_group_jid")
	check(not N.is_group_jid("a@h/res", "conference.h"), "no es grupo")

	check(N.looks_like_xmpp_target_id("a@b"), "target simple")
	check(N.looks_like_xmpp_target_id("a@b/res"), "target con recurso")
	check(not N.looks_like_xmpp_target_id("a b@c"), "target con espacio")
	check(not N.looks_like_xmpp_target_id("sinarroba"), "target sin @")
	check(not N.looks_like_xmpp_target_id("@b"), "target sin local")

	check(N.normalize_messaging_target("xmpp:a@b") == "a@b", "quita xmpp:")
	check(N.normalize_messaging_target("channel:a@b") == "a@b", "quita channel:")
	check(N.normalize_messaging_target("a@b") == "a@b", "sin prefijo")

	# split_for_limit.
	check(N.split_for_limit("hola", 4000).size() == 1, "corto no parte")
	var big = ""
	for i in range(10):
		big += "linea-" + str(i) + "\n"
	var parts = N.split_for_limit(big, 30)
	check(parts.size() > 1, "largo se parte")
	var too_long = false
	for p in parts:
		if p.length() > 30:
			too_long = true
	check(not too_long, "ninguna parte excede el límite")
	var hard = N.split_for_limit("x".repeat(95), 30)
	check(hard.size() == 4 and hard[3].length() == 5, "corte duro 95/30")

	# markdown_to_plain.
	check(N.markdown_to_plain("hola **mundo** *x*") == "hola mundo x", "plain simple")
	check(N.markdown_to_plain("```\ncode\n```") == "code", "plain fence")
	check(N.markdown_to_plain("[t](https://u)") == "t (https://u)", "plain link")

	# OOB.
	var body = "mirá <x xmlns='jabber:x:oob'><url>https://ejemplo/f.png</url></x>"
	check(N.extract_oob_url(body) == "https://ejemplo/f.png", "oob url")
	check(N.strip_inline_oob_markup(body) == "https://ejemplo/f.png", "strip oob")

	if _fail == 0:
		print("NORMALIZE_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
