extends SceneTree

# XEP-0313 MAM: construcción de query + parseo de fin/result.

var _fail := 0

func _init():
	var Mam = load("res://addons/xat_xmpp/xmpp/mam.gd")
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")

	var iq = Mam.build_query("yo@h", "q1", "iq1", "agente@h", 50, "arch-9")
	var xml = iq.to_xml()
	check(xml.find('<query xmlns="urn:xmpp:mam:2" queryid="q1">') >= 0, "query xmlns + queryid")
	check(xml.find('<field var="FORM_TYPE" type="hidden"><value>urn:xmpp:mam:2</value></field>') >= 0, "FORM_TYPE")
	check(xml.find('<field var="with"><value>agente@h</value></field>') >= 0, "campo with")
	check(xml.find('<set xmlns="http://jabber.org/protocol/rsm"><max>50</max><after>arch-9</after></set>') >= 0, "RSM max+after")
	check(iq.get_attr("type") == "set" and iq.get_attr("to") == "yo@h" and iq.get_attr("id") == "iq1", "iq attrs")

	# Sin with/after: no aparecen esos campos.
	var iq2 = Mam.build_query("yo@h", "q2", "iq2", "", 30)
	var xml2 = iq2.to_xml()
	check(xml2.find('var="with"') < 0, "sin campo with")
	check(xml2.find('<after>') < 0, "sin after")
	check(xml2.find("<max>30</max>") >= 0, "max 30")

	# Ultima pagina: <before/> vacio, sin after ni with.
	var iq3 = Mam.build_query("yo@h", "q3", "iq3", "agente@h", 50, "", "", "", "", true)
	var xml3 = iq3.to_xml()
	check(xml3.find("<before/>") >= 0, "last page: before vacio")
	check(xml3.find("<after>") < 0, "last page: sin after")
	check(xml3.find("<max>50</max>") >= 0, "last page: max")
	check(xml3.find('var="with"') >= 0, "last page: campo with")

	# parse fin.
	var fin = Stanza.parse('<iq type="result" id="iq1"><fin xmlns="urn:xmpp:mam:2" complete="true">' \
		+ '<set xmlns="http://jabber.org/protocol/rsm"><first>a1</first><last>z9</last><count>123</count></set>' \
		+ '</fin></iq>')
	var info = Mam.parse_fin(fin)
	check(info["complete"], "fin complete")
	check(info["rsm_last"] == "z9" and info["rsm_first"] == "a1", "rsm last/first")
	check(info["count"] == 123, "rsm count")

	# parse result -> registro de mensaje.
	var rec = Mam.parse_result('<message to="yo@h"><result xmlns="urn:xmpp:mam:2" queryid="q1" id="arch-7">' \
		+ '<forwarded xmlns="urn:xmpp:forward:0">' \
		+ '<delay xmlns="urn:xmpp:delay" stamp="2026-05-05T05:05:05Z"/>' \
		+ '<message from="agente@h" to="yo@h" type="chat" id="o7"><body>hola mam</body></message>' \
		+ '</forwarded></result></message>')
	check(rec["is_mam"] and rec["mam_id"] == "arch-7", "result mam_id")
	check(rec["body"] == "hola mam" and rec["timestamp"] == "2026-05-05T05:05:05Z", "result contenido")

	if _fail == 0:
		print("MAM_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
