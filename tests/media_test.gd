extends SceneTree

# Media: clasificación por MIME/extensión, nombres/links, formato, y la
# plomería XML de XEP-0363 (disco + slot) y del parser de WAV. Todo puro.

var _fail := 0

func _init():
	var Media = load("res://addons/xat_xmpp/xmpp/media.gd")
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")

	# Clasificación.
	check(Media.extension_of("/a/b/Foto.JPG") == "jpg", "extension_of")
	check(Media.extension_of("https://up.x/a/b.jpg?t=1#x") == "jpg", "extension_of con query")
	check(Media.mime_for_path("x/foto.png") == "image/png", "mime png")
	check(Media.mime_for_path("x/voz.wav") == "audio/wav", "mime wav")
	check(Media.mime_for_path("x/rar.unknownext") == "application/octet-stream", "mime default")
	check(Media.kind_for_mime("image/jpeg; charset=x") == Media.KIND_IMAGE, "kind image con parámetros")
	check(Media.kind_for_mime("audio/ogg") == Media.KIND_AUDIO, "kind audio")
	check(Media.kind_for_mime("application/pdf") == Media.KIND_FILE, "kind file")
	check(Media.kind_for_mime("") == "", "kind vacío")
	check(Media.kind_for_path("a/foto.webp") == Media.KIND_IMAGE, "kind_for_path")
	check(Media.is_audio_mime("audio/opus") and not Media.is_audio_mime("image/png"), "is_audio_mime")

	# Nombres.
	check(Media.sanitize_filename("../../etc/passwd") == "passwd", "sanitize quita ruta")
	check(Media.sanitize_filename('foto "rara".png') == "foto _rara_.png", "sanitize comillas")
	check(Media.sanitize_filename("  .oculto.png ") == "oculto.png", "sanitize punto inicial")
	check(Media.sanitize_filename("") == "archivo", "sanitize fallback")
	check(Media.filename_from_url("https://up.x/abc/file%20one.png?tok=1") == "file%20one.png", "filename_from_url")
	check(Media.filename_from_url("https://up.x/opaco") == "archivo", "filename_from_url sin ext")

	# Links en el cuerpo.
	var body = "Mirá esto\nhttps://up.x/a/b.jpg\ngracias"
	check(Media.url_of(body) == "https://up.x/a/b.jpg", "url_of")
	check(Media.url_of("https://up.x/a.jpg).") == "https://up.x/a.jpg", "url_of puntuación")
	check(Media.url_of("sin links") == "", "url_of vacío")
	check(Media.is_url_only("https://up.x/a.jpg", "https://up.x/a.jpg"), "is_url_only igual")
	check(Media.is_url_only("", "https://up.x/a.jpg"), "is_url_only vacío")
	check(not Media.is_url_only("pie\nhttps://up.x/a.jpg", "https://up.x/a.jpg"), "is_url_only con pie")
	check(Media.caption_of("pie de foto\nhttps://up.x/a.jpg", "https://up.x/a.jpg") == "pie de foto", "caption_of")
	check(Media.caption_of("[image/png] f.png: https://up.x/a.png", "https://up.x/a.png") == "[image/png] f.png", "caption_of link embebido")

	# Formato.
	check(Media.format_size(512) == "512 B", "size B")
	check(Media.format_size(2048) == "2 KB", "size KB")
	check(Media.format_size(5 * 1024 * 1024) == "5.0 MB", "size MB")
	check(Media.format_duration(65.0) == "1:05", "duration m:ss")
	check(Media.format_duration(3725.0) == "1:02:05", "duration h:mm:ss")
	check(Media.format_duration_ms(65000) == "1:05", "duration ms")

	# FS: tamaño de archivo (File.get_len() no recibe ruta en Godot 3).
	var tmp = "user://media_size_test.bin"
	var wf = File.new()
	if wf.open(tmp, File.WRITE) == OK:
		wf.store_buffer(PoolByteArray([1, 2, 3, 4, 5]))
		wf.close()
	check(Media.file_size(tmp) == 5, "file_size bytes")
	check(Media.file_size("user://no_existe_xyz.bin") == -1, "file_size inexistente")
	var td = Directory.new()
	td.remove(tmp)

	# Errores legibles y nombres cortos.
	check(Media.describe_error("sin-servicio").find("subida") >= 0, "describe sin-servicio")
	check(Media.describe_error("http-413").find("413") >= 0, "describe http")
	check(Media.describe_error("red-7").find("conexión") >= 0, "describe red")
	check(Media.describe_error("cualquiera") == "No se pudo transferir el adjunto", "describe genérico")
	check(Media.short_name("corto.png") == "corto.png", "short_name corto")
	var largo = Media.short_name("una_foto_con_nombre_larguisimo_1234567890.png", 24)
	check(largo.length() <= 24 and largo.ends_with(".png") and largo.find("…") >= 0, "short_name recorta")

	# XEP-0363: disco#items.
	var items = Media.build_disco_items("i1", "hablar.fuentelibre.org")
	check(items.to_xml().find("http://jabber.org/protocol/disco#items") >= 0, "disco items xmlns")
	var items_parsed = Media.parse_disco_items(Stanza.parse('<iq type="result" id="i1"><query xmlns="http://jabber.org/protocol/disco#items"><item jid="upload.hablar.fuentelibre.org"/><item jid="conference.hablar.fuentelibre.org"/></query></iq>'))
	check(items_parsed.size() == 2 and items_parsed[0] == "upload.hablar.fuentelibre.org", "parse disco items")

	# XEP-0363: disco#info feature.
	check(Media.disco_has_upload(Stanza.parse('<iq type="result"><query xmlns="http://jabber.org/protocol/disco#info"><feature var="urn:xmpp:http:upload:0"/></query></iq>')), "disco has upload")
	check(not Media.disco_has_upload(Stanza.parse('<iq type="result"><query xmlns="http://jabber.org/protocol/disco#info"><feature var="urn:xmpp:ping"/></query></iq>')), "disco sin upload")

	# XEP-0363: pedido de slot.
	var req = Media.build_slot_request("s1", "upload.x", "foto.jpg", 1234, "image/jpeg")
	var req_xml = req.to_xml()
	check(req_xml.find('filename="foto.jpg"') >= 0 and req_xml.find('size="1234"') >= 0 and req_xml.find('content-type="image/jpeg"') >= 0, "slot request attrs")

	# Resultado del slot: put/get en atributos url y headers.
	var slot = Media.parse_slot_result(Stanza.parse('<iq type="result" id="s1"><slot xmlns="urn:xmpp:http:upload:0">' \
		+ '<put url="https://up.x/put/1"><header name="Authorization">Bearer abc</header></put>' \
		+ '<get url="https://up.x/get/1"/></slot></iq>'))
	check(slot["ok"], "slot ok")
	check(slot["put_url"] == "https://up.x/put/1" and slot["get_url"] == "https://up.x/get/1", "slot urls")
	check(slot["headers"].size() == 1 and slot["headers"][0]["name"] == "Authorization", "slot header")
	var hdrs = Media.headers_array(slot["headers"])
	check(hdrs.size() == 1 and hdrs[0] == "Authorization: Bearer abc", "headers_array")
	var bad = Media.parse_slot_result(Stanza.parse('<iq type="error" id="s2"><slot xmlns="urn:xmpp:http:upload:0"/></iq>'))
	check(not bad["ok"] and bad["error"] == "error", "slot error")

	# WAV: armar un PCM 16-bit mono 8000 Hz con 4 muestras y parsearlo.
	var wav = _make_wav(8000, 1, 16, PoolByteArray([1, 0, 2, 0, 3, 0, 4, 0]))
	var info = Media.parse_wav(wav)
	check(info["ok"], "wav ok")
	check(info["mix_rate"] == 8000 and not info["stereo"] and info["format"] == 1, "wav fmt")
	check(info["data"].size() == 8, "wav data size")
	check(not Media.parse_wav(PoolByteArray([1, 2, 3]) )["ok"], "wav basura")

	if _fail == 0:
		print("MEDIA_CHECK_OK")
	quit()

func _make_wav(p_rate: int, p_channels: int, p_bits: int, p_data: PoolByteArray) -> PoolByteArray:
	# PoolByteArray es tipo valor: los appends van inline (no en helpers).
	var b := PoolByteArray()
	b.append_array("RIFF".to_utf8())
	b.append_array(_le(36 + p_data.size(), 4))
	b.append_array("WAVE".to_utf8())
	b.append_array("fmt ".to_utf8())
	b.append_array(_le(16, 4))
	b.append_array(_le(1, 2)) # PCM
	b.append_array(_le(p_channels, 2))
	b.append_array(_le(p_rate, 4))
	b.append_array(_le(p_rate * p_channels * p_bits / 8, 4))
	b.append_array(_le(p_channels * p_bits / 8, 2))
	b.append_array(_le(p_bits, 2))
	b.append_array("data".to_utf8())
	b.append_array(_le(p_data.size(), 4))
	b.append_array(p_data)
	return b

static func _le(p_value: int, p_bytes: int) -> PoolByteArray:
	var out := PoolByteArray()
	for i in range(p_bytes):
		out.append((p_value >> (8 * i)) & 0xFF)
	return out

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
