extends SceneTree

# XEP-0084: metadata -> pedido del item de datos -> caché -> avatar_changed.

var _fail := 0
var _changed := []

func _init():
	var Avatar = load("res://addons/xat_xmpp/xmpp/avatar.gd")
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")

	var req = Avatar.build_data_request("av1", "bob@h", "abc123").to_xml()
	check(req.find('node="urn:xmpp:avatar:data"') >= 0 and req.find('id="abc123"') >= 0 and req.find('to="bob@h"') >= 0, "pedido de datos")
	check(Avatar.ext_for_type("image/jpeg") == "jpg" and Avatar.ext_for_type("") == "png", "extensión por tipo")
	check(Avatar.cache_path("ab/../c", "image/png").find("..") < 0, "cache_path sin traversal")

	# PNG real 2x2 en base64.
	var img = Image.new()
	img.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0))
	var b64 = Marshalls.raw_to_base64(img.save_png_to_buffer())
	var id = "test%d" % OS.get_unix_time()

	var s = load("res://addons/xat_xmpp/xmpp/session.gd").new()
	var fake = FakeTransport.new()
	s._transport = fake
	s.connect("avatar_changed", self, "_on_changed")
	s._on_stanza('<message from="bob@h" type="headline"><event xmlns="http://jabber.org/protocol/pubsub#event"><items node="urn:xmpp:avatar:metadata"><item id="%s"><metadata xmlns="urn:xmpp:avatar:metadata"><info id="%s" bytes="70" type="image/png"/></metadata></item></items></event></message>' % [id, id])
	check(fake.sent.size() == 1 and fake.sent[0].find(id) >= 0, "metadata nueva pide datos")
	var iq_id = s._avatar_req.keys()[0] if not s._avatar_req.empty() else ""
	s._on_stanza('<iq type="result" id="%s" from="bob@h"><pubsub xmlns="http://jabber.org/protocol/pubsub"><items node="urn:xmpp:avatar:data"><item id="%s"><data xmlns="urn:xmpp:avatar:data">%s</data></item></items></pubsub></iq>' % [iq_id, id, b64])
	check(_changed.size() == 1 and _changed[0] == "bob@h" and s.avatars["bob@h"] is ImageTexture, "datos -> textura + señal")
	# Segunda vez: sale de la caché sin pedir de nuevo.
	s._on_stanza('<message from="ana@h" type="headline"><event xmlns="http://jabber.org/protocol/pubsub#event"><items node="urn:xmpp:avatar:metadata"><item id="%s"><metadata xmlns="urn:xmpp:avatar:metadata"><info id="%s" type="image/png"/></metadata></item></items></event></message>' % [id, id])
	check(fake.sent.size() == 1 and _changed.size() == 2, "caché evita el pedido")
	Directory.new().remove(Avatar.cache_path(id, "image/png"))
	s.free()
	if _fail == 0:
		print("AVATAR_CHECK_OK")
	quit()

func _on_changed(p_bare, _tex):
	_changed.append(p_bare)

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
