extends SceneTree

# XEP-0050/0004/0439: discovery, execute, submit, parseo y selection IQ.

var _fail := 0

func _init():
	var Commands = load("res://addons/xat_xmpp/xmpp/commands.gd")
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")

	var disco = Commands.build_discovery("bot@h/res", "d1")
	check(disco.to_xml() == '<iq type="get" to="bot@h/res" id="d1"><query xmlns="http://jabber.org/protocol/disco#items" node="http://jabber.org/protocol/commands"/></iq>', "discovery xml")

	var exe = Commands.build_execute("bot@h/res", "elevated", "sess1", "c1")
	check(exe.to_xml().find('<command xmlns="http://jabber.org/protocol/commands" node="elevated" action="execute" sessionid="sess1"/>') >= 0, "execute xml")

	var sub = Commands.build_submit("bot@h/res", "elevated", "sess1", [{"var": "mode", "type": "list-single", "values": ["on"]}], "c2")
	var subxml = sub.to_xml()
	check(subxml.find('action="submit"') >= 0 and subxml.find('<x xmlns="jabber:x:data" type="submit">') >= 0, "submit xml")
	check(subxml.find('<value>on</value>') >= 0, "submit valor")

	# Respuesta executing con formulario + acciones.
	var iq1 = Stanza.parse('<iq type="result"><command xmlns="http://jabber.org/protocol/commands" node="elevated" status="executing" sessionid="oc-1">' \
		+ '<x xmlns="jabber:x:data" type="form"><field var="minutes" type="text-single"><value>10</value></field></x>' \
		+ '<actions execute="next"><next/></actions>' \
		+ '</command></iq>')
	var r1 = Commands.parse_response(iq1)
	check(r1["status"] == "executing" and r1["sessionid"] == "oc-1" and r1["node"] == "elevated", "parse executing")
	check(r1["form"] != null and r1["form"]["fields"][0]["value"] == "10", "parse form")
	check(r1["actions"].has("next") and r1["default"] == "next", "parse actions")

	# Respuesta completed con nota + form de resultado.
	var iq2 = Stanza.parse('<iq type="result"><command xmlns="http://jabber.org/protocol/commands" node="status" status="completed">' \
		+ '<note type="info">Listo</note>' \
		+ '<x xmlns="jabber:x:data" type="result"><field var="x"><value>y</value></field></x>' \
		+ '</command></iq>')
	var r2 = Commands.parse_response(iq2)
	check(r2["status"] == "completed", "parse completed")
	check(r2["notes"].size() == 1 and r2["notes"][0]["text"] == "Listo", "parse note")

	# Error.
	var iq3 = Stanza.parse('<iq type="error"><command xmlns="http://jabber.org/protocol/commands" node="abort" status="canceled"/><error type="auth"/></iq>')
	var r3 = Commands.parse_response(iq3)
	check(r3["error_type"] == "auth", "parse error")

	# disco#items.
	var di = Stanza.parse('<iq type="result"><query xmlns="http://jabber.org/protocol/disco#items" node="http://jabber.org/protocol/commands">' \
		+ '<item jid="bot@h/res" node="compact" name="Session: compact"/>' \
		+ '<item jid="bot@h/res" node="model" name="Model"/>' \
		+ '</query></iq>')
	var items = Commands.parse_items(di)
	check(items.size() == 2 and items[0]["node"] == "compact" and items[0]["name"] == "Session: compact", "parse items")

	# next_action.
	check(Commands.next_action("executing", {"next": true}, "") == "next", "next_action next")
	check(Commands.next_action("executing", {}, "complete") == "complete", "next_action default")
	check(Commands.next_action("completed", {}, "") == "complete", "next_action completed")

	if _fail == 0:
		print("COMMANDS_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
