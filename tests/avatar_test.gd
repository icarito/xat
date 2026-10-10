extends SceneTree

# XEP-0084 (avatar propio): sha1, procesado de imagen, builders de publish y
# la API de la sesión (con transporte falso).

var _fail := 0

class FakeTransport:
	extends Node
	var sent := []
	func send(xml: String) -> int:
		sent.append(xml)
		return 0
	func available() -> bool:
		return true

func _init():
	var Avatar = load("res://addons/xat_xmpp/xmpp/avatar.gd")
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")
	var Session = load("res://addons/xat_xmpp/xmpp/session.gd")

	# SHA-1 de bytes vacíos (valor conocido).
	check(Avatar.sha1_hex(PoolByteArray()) == "da39a3ee5e6b4b0d3255bfef95601890afd80709", "sha1 de vacío")

	# Procesado: 200x100 -> recorte cuadrado + resize a 96.
	var img = Image.new()
	img.create(200, 100, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.6, 0.3, 1.0))
	var src = "user://avatar_test_src.png"
	img.save_png(src)
	var a = Avatar.process(src, 96)
	check(not a.empty(), "process devuelve datos")
	check(int(a.get("width", 0)) == 96 and int(a.get("height", 0)) == 96, "process recorta cuadrado a 96")
	check(Avatar.sha1_hex(a["bytes"]) == str(a["id"]), "id = sha1(bytes)")
	check(str(a.get("mime", "")).begins_with("image/"), "mime de imagen")

	# Builders.
	var d = Avatar.build_publish_data("av1", "abc123", "QkJC").to_xml()
	check(d.find('node="urn:xmpp:avatar:data"') >= 0 and d.find('<item id="abc123"') >= 0 and d.find("QkJC") >= 0, "publish data")
	check(d.find("pubsub#access_model") >= 0 and d.find("<value>presence</value>") >= 0, "publish-options presence")
	var m = Avatar.build_publish_metadata("avm1", "abc123", 1234, "image/png", 96, 96).to_xml()
	check(m.find('node="urn:xmpp:avatar:metadata"') >= 0 and m.find('bytes="1234"') >= 0 and m.find('type="image/png"') >= 0, "publish metadata")

	# Sesión: publish_avatar manda data + metadata y cachea local.
	var s = Session.new()
	s.name = "S"
	get_root().add_child(s)
	var fake = FakeTransport.new()
	s._transport = fake
	s.state = Session.State.CONNECTED
	s._bare = "yo@h"
	fake.sent.clear()
	check(s.publish_avatar(src) == 0, "publish_avatar rc")
	check(fake.sent.size() == 2, "publish_avatar envía 2 stanzas")
	check(fake.sent[0].find("avatar:data") >= 0 and fake.sent[1].find("avatar:metadata") >= 0, "primero data, luego metadata")
	check(s.avatars.has("yo@h"), "avatar propio cacheado")
	check(s.publish_avatar("/no/existe.png") == -2, "imagen inválida -> -2")
	s.free()
	Directory.new().remove(src)

	if _fail == 0:
		print("AVATAR_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
