extends SceneTree

# Parseo/construcción de <message>: 0085, 0184, 0280, 0203, 0308, 0359, 0313,
# y items inline de OpenClaw.

var _fail := 0

func _init():
	var Message = load("res://addons/xat_xmpp/xmpp/message.gd")
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")

	# Mensaje simple con delay + request de recibo + origin-id.
	var m = Message.parse('<message from="agente@h/x" to="yo@h" type="chat" id="m1">' \
		+ '<body>hola</body>' \
		+ '<request xmlns="urn:xmpp:receipts"/>' \
		+ '<origin-id xmlns="urn:xmpp:sid:0" id="o1"/>' \
		+ '<delay xmlns="urn:xmpp:delay" stamp="2026-01-02T03:04:05Z"/>' \
		+ '</message>')
	check(m["body"] == "hola", "body")
	check(m["from"] == "agente@h/x" and m["to"] == "yo@h", "from/to")
	check(m["id"] == "m1", "id")
	check(m["receipt_request"], "request de recibo")
	check(m["origin_id"] == "o1", "origin-id")
	check(m["timestamp"] == "2026-01-02T03:04:05Z" and m["delayed"], "delay 0203")

	# Chat state composing.
	var cs = Message.parse('<message to="a@h" from="b@h" type="chat"><composing xmlns="http://jabber.org/protocol/chatstates"/></message>')
	check(cs["chat_state"] == "composing", "chat state")

	# Carbons (sent): se desenvuelve el mensaje interno.
	var carb = Message.parse('<message from="yo@h" type="chat"><sent xmlns="urn:xmpp:carbons:2">' \
		+ '<forwarded xmlns="urn:xmpp:forward:0"><message to="agente@h" from="yo@h/res" type="chat" id="c1"><body>eco</body></message></forwarded>' \
		+ '</sent></message>')
	check(carb["carbon"] == "sent", "carbon sent")
	check(carb["body"] == "eco" and carb["id"] == "c1", "carbon desenvuelto")

	# MAM result.
	var mam = Message.parse('<message to="yo@h"><result xmlns="urn:xmpp:mam:2" queryid="q1" id="arch-1">' \
		+ '<forwarded xmlns="urn:xmpp:forward:0">' \
		+ '<delay xmlns="urn:xmpp:delay" stamp="2026-03-03T03:03:03Z"/>' \
		+ '<message from="agente@h" to="yo@h" type="chat" id="orig1"><body>archivado</body></message>' \
		+ '</forwarded></result></message>')
	check(mam["is_mam"] and mam["mam_id"] == "arch-1" and mam["mam_queryid"] == "q1", "mam ids")
	check(mam["body"] == "archivado" and mam["timestamp"] == "2026-03-03T03:03:03Z", "mam contenido")

	# Corrección 0308.
	var corr = Message.parse('<message from="a@h" type="chat" id="e1"><body>v2</body>' \
		+ '<replace xmlns="urn:xmpp:message-correct:0" id="orig1"/></message>')
	check(corr["replace_id"] == "orig1", "replace id")

	# Recibo recibido.
	var rec = Message.parse('<message to="a@h" from="b@h" type="chat"><received xmlns="urn:xmpp:receipts" id="m1"/></message>')
	check(rec["received_id"] == "m1", "received id")

	# Items inline: comandos + quick responses.
	var inline = Message.parse('<message from="agente@h" type="chat"><body>¿Aprobás?</body>' \
		+ '<query xmlns="http://jabber.org/protocol/disco#items" node="http://jabber.org/protocol/commands">' \
		+ '<item jid="agente@h" node="cmd:abc:0" name="Permitir" style="success" expires-at-ms="1699999999000"/>' \
		+ '</query>' \
		+ '<response xmlns="urn:xmpp:tmp:quick-response" value="si" label="Sí"/>' \
		+ '<response xmlns="urn:xmpp:quick-response:0" value="no" label="No" style="danger"/>' \
		+ '</message>')
	check(inline["commands"].size() == 1, "un comando inline")
	check(inline["commands"][0]["node"] == "cmd:abc:0" and inline["commands"][0]["expires_at_ms"] == 1699999999000, "comando campos")
	check(inline["quick_responses"].size() == 2, "dos quick responses")
	check(inline["quick_responses"][1]["style"] == "danger", "quick style")

	# Builder: chat con active + request; re-parse.
	var built = Message.build_chat("agente@h", "hola & chau", "s1", "o9", true)
	check(built.to_xml().find('<active xmlns="http://jabber.org/protocol/chatstates"/>') >= 0, "builder active")
	var reparsed = Message.parse(built)
	check(reparsed["body"] == "hola & chau" and reparsed["receipt_request"] and reparsed["chat_state"] == "active", "builder re-parse")
	check(reparsed["origin_id"] == "o9", "builder origin-id")

	# Builder de recibo.
	var receipt = Message.build_receipt("agente@h", "m1")
	check(Message.parse(receipt)["received_id"] == "m1", "builder recibo")

	# Builder de corrección.
	var fix = Message.build_correction("agente@h", "v3", "orig1", "e2")
	var fixrec = Message.parse(fix)
	check(fixrec["body"] == "v3" and fixrec["replace_id"] == "orig1", "builder corrección")

	# Adjunto OOB (0066): url + desc en el <x>; el body trae el link.
	var oob = Message.parse('<message from="a@h" type="chat"><body>pie\nhttps://up.x/f.jpg</body>' \
		+ '<x xmlns="jabber:x:oob"><url>https://up.x/f.jpg</url><desc>pie</desc></x></message>')
	check(oob["oob_url"] == "https://up.x/f.jpg" and oob["oob_desc"] == "pie", "oob parse")
	check(oob["body"] == "pie\nhttps://up.x/f.jpg", "oob body intacto")

	# Builder de media: link en el body y en OOB; con pie, el body lleva pie+link.
	var media = Message.parse(Message.build_media("agente@h", "https://up.x/v.ogg", "", "s2", "o2", true))
	check(media["oob_url"] == "https://up.x/v.ogg" and media["body"] == "https://up.x/v.ogg", "builder media url")
	check(media["receipt_request"] and media["origin_id"] == "o2", "builder media extras")
	var media2 = Message.parse(Message.build_media("agente@h", "https://up.x/v.ogg", "hola", "s3"))
	check(media2["oob_url"] == "https://up.x/v.ogg" and media2["body"] == "hola\nhttps://up.x/v.ogg" and media2["oob_desc"] == "hola", "builder media pie")

	if _fail == 0:
		print("MESSAGE_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
