extends SceneTree

# Flujo de adjuntos en la sesión sin red: descubrimiento del componente
# XEP-0363 (disco#items -> disco#info), pedido de slot, y detección de media en
# mensajes entrantes. Usa un transporte falso que sólo registra lo enviado.

var _fail := 0

class FakeTransport extends Reference:
	var sent := []
	func send(p_xml: String) -> int:
		sent.append(p_xml)
		return 0
	func last() -> String:
		return sent[sent.size() - 1] if not sent.empty() else ""

func _init():
	var Session = load("res://addons/xat_xmpp/xmpp/session.gd")
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")
	var fake = FakeTransport.new()
	var s = Session.new()
	s._transport = fake
	s._bare = "yo@hablar.fuentelibre.org"
	s.state = 2 # State.CONNECTED

	# Archivo temporal a subir.
	var path = "user://media_up_test.bin"
	var f = File.new()
	f.open(path, File.WRITE)
	f.store_buffer(PoolByteArray([1, 2, 3, 4, 5, 6, 7, 8]))
	f.close()

	# 1) Subir con host desconocido: arranca con disco#items al dominio.
	var rid = s.send_media_file("agente@hablar.fuentelibre.org", path, "image/png", 0, "")
	check(rid != "", "send_media_file devuelve request_id")
	check(fake.sent.size() == 1, "un stanza enviado (disco items)")
	check(fake.last().find('xmlns="http://jabber.org/protocol/disco#items"') >= 0, "disco items")
	check(fake.last().find('to="hablar.fuentelibre.org"') >= 0, "disco items al dominio")

	# 2) El dominio responde items: se prueba disco#info del componente upload.
	var items_id = Stanza.parse(fake.last()).get_attr("id", "")
	s._on_iq(Stanza.parse('<iq type="result" id="' + items_id + '"><query xmlns="http://jabber.org/protocol/disco#items"><item jid="upload.hablar.fuentelibre.org"/></query></iq>'))
	var info_sent = _find(fake, 'xmlns="http://jabber.org/protocol/disco#info"')
	check(info_sent != "", "disco info al candidato")
	check(info_sent.find('to="upload.hablar.fuentelibre.org"') >= 0, "disco info al upload.*")

	# 3) El componente anuncia la feature: se pide el slot.
	var info_id = Stanza.parse(info_sent).get_attr("id", "")
	s._on_iq(Stanza.parse('<iq type="result" id="' + info_id + '"><query xmlns="http://jabber.org/protocol/disco#info"><feature var="urn:xmpp:http:upload:0"/></query></iq>'))
	check(s._upload_host == "upload.hablar.fuentelibre.org", "host de upload resuelto")
	var slot_sent = _find(fake, 'xmlns="urn:xmpp:http:upload:0"')
	check(slot_sent != "", "slot request enviado")
	check(slot_sent.find('filename="media_up_test.bin"') >= 0, "slot filename")
	check(slot_sent.find('size="8"') >= 0, "slot size")
	check(s._upload_ctx.size() == 1, "contexto esperando slot")

	# Al desconectar se olvida el componente y se limpian los pendientes.
	s._reset_upload_state()
	check(not s._upload_host_known and s._upload_host == "", "reset olvida el host")
	check(s._upload_ctx.empty() and s._disco_ctx.empty() and s._upload_queue.empty(), "reset limpia pendientes")

	# 4) Detección de media entrante.
	var rec = {"body": "mirá https://up.x/foto.jpg", "oob_url": ""}
	s._apply_media(rec)
	check(rec.get("attach", {}).get("url", "") == "https://up.x/foto.jpg", "media por link en body")
	check(rec.get("attach", {}).get("kind", "") == "image", "kind imagen")
	var rec2 = {"body": "", "oob_url": "https://up.x/voz.ogg"}
	s._apply_media(rec2)
	check(rec2["body"] == "https://up.x/voz.ogg", "oob sin body rellena body")
	check(rec2.get("attach", {}).get("kind", "") == "audio", "kind audio")
	var plain = {"body": "hola sin adjunto", "oob_url": ""}
	s._apply_media(plain)
	check(not plain.has("attach"), "texto plano no es adjunto")

	# 5) Ruta de caché determinista y con nombre útil.
	var p = s.media_cache_path("https://up.x/a/foto.png?t=1")
	check(p.begins_with("user://media/"), "cache en user://media/")
	check(p.ends_with(".png"), "cache conserva extensión")
	check(p == s.media_cache_path("https://up.x/a/foto.png?t=1"), "cache estable")

	var d = Directory.new()
	d.remove(path)
	s.free()
	if _fail == 0:
		print("MEDIA_SESSION_CHECK_OK")
	quit()

func _find(p_fake, p_needle: String) -> String:
	for x in p_fake.sent:
		if x.find(p_needle) >= 0:
			return x
	return ""

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
