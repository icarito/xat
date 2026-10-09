extends Reference

# Carga de adjuntos para la UI: bytes -> ImageTexture / AudioStreamSample.
# Godot 3.6 sólo reproduce WAV (no hay AudioStreamOGGVorbis en el fork), así que
# el audio se decodifica con el parser WAV de `media.gd`.

const Media = preload("res://addons/xat_xmpp/xmpp/media.gd")

# Imagen desde disco (png/jpg/webp/bmp) o null. Detecta por bytes mágicos para
# no imprimir errores del loader equivocado.
static func load_texture(p_path: String):
	var f = File.new()
	if not f.file_exists(p_path) or f.open(p_path, File.READ) != OK:
		return null
	var buf = f.get_buffer(f.get_len())
	f.close()
	var img = Image.new()
	var ok = false
	if _starts(buf, [0x89, 0x50, 0x4E, 0x47]):
		ok = img.load_png_from_buffer(buf) == OK
	elif _starts(buf, [0xFF, 0xD8, 0xFF]):
		ok = img.load_jpg_from_buffer(buf) == OK
	elif _starts(buf, [0x42, 0x4D]):
		ok = img.load_bmp_from_buffer(buf) == OK
	elif _starts(buf, [0x52, 0x49, 0x46, 0x46]) and buf.size() > 16 and String(buf.subarray(8, 11)) == "WEBP":
		ok = img.load_webp_from_buffer(buf) == OK
	if not ok or img.is_empty():
		return null
	var tex = ImageTexture.new()
	tex.create_from_image(img, 0)
	return tex

# Miniatura cuadrada máxima p_max (conserva aspecto) o null.
static func load_thumbnail(p_path: String, p_max: int):
	var img = _load_image(p_path)
	if img == null:
		return null
	var w = img.get_width()
	var h = img.get_height()
	if w <= 0 or h <= 0:
		return null
	var scale = min(float(p_max) / float(w), float(p_max) / float(h))
	if scale < 1.0:
		img.resize(int(w * scale), int(h * scale), Image.INTERPOLATE_BILINEAR)
	var tex = ImageTexture.new()
	tex.create_from_image(img, 0)
	return tex

# Dimensiones (w,h) de la imagen, para reservar el espacio del thumbnail.
static func image_size(p_path: String) -> Vector2:
	var img = _load_image(p_path)
	if img == null:
		return Vector2.ZERO
	return Vector2(img.get_width(), img.get_height())

static func _load_image(p_path: String):
	var f = File.new()
	if not f.file_exists(p_path) or f.open(p_path, File.READ) != OK:
		return null
	var buf = f.get_buffer(f.get_len())
	f.close()
	var img = Image.new()
	var ok = false
	if _starts(buf, [0x89, 0x50, 0x4E, 0x47]):
		ok = img.load_png_from_buffer(buf) == OK
	elif _starts(buf, [0xFF, 0xD8, 0xFF]):
		ok = img.load_jpg_from_buffer(buf) == OK
	elif _starts(buf, [0x42, 0x4D]):
		ok = img.load_bmp_from_buffer(buf) == OK
	elif _starts(buf, [0x52, 0x49, 0x46, 0x46]) and buf.size() > 16 and String(buf.subarray(8, 11)) == "WEBP":
		ok = img.load_webp_from_buffer(buf) == OK
	return img if ok and not img.is_empty() else null

# Audio WAV -> AudioStreamSample, o null si no es WAV PCM.
static func load_wav(p_path: String):
	var f = File.new()
	if not f.file_exists(p_path) or f.open(p_path, File.READ) != OK:
		return null
	var buf = f.get_buffer(f.get_len())
	f.close()
	var info = Media.parse_wav(buf)
	if not info["ok"]:
		return null
	var s = AudioStreamSample.new()
	s.format = info["format"]
	s.mix_rate = info["mix_rate"]
	s.stereo = info["stereo"]
	s.data = info["data"]
	return s

# Audio reproducible: WAV (siempre), OGG Vorbis y MP3 (si el build trae los
# módulos stb_vorbis/minimp3). Opus/M4A/AAC no tienen decodificador en Godot 3.
# Se instancia por ClassDB para no depender de que la clase exista al compilar.
static func load_audio(p_path: String):
	var ext = Media.extension_of(p_path)
	if ext == "wav":
		return load_wav(p_path)
	var f = File.new()
	if not f.file_exists(p_path) or f.open(p_path, File.READ) != OK:
		return null
	var buf = f.get_buffer(f.get_len())
	f.close()
	if ext == "ogg" or ext == "oga":
		return _stream_from_data("AudioStreamOGGVorbis", buf)
	if ext == "mp3":
		return _stream_from_data("AudioStreamMP3", buf)
	return null

static func _stream_from_data(p_class: String, p_data: PoolByteArray):
	if not ClassDB.class_exists(p_class):
		return null
	var s = ClassDB.instance(p_class)
	if s == null:
		return null
	s.set("data", p_data)
	return s

static func is_playable(p_path: String) -> bool:
	var ext = Media.extension_of(p_path)
	if ext == "wav":
		return true
	if ext == "ogg" or ext == "oga":
		return ClassDB.class_exists("AudioStreamOGGVorbis")
	if ext == "mp3":
		return ClassDB.class_exists("AudioStreamMP3")
	return false

static func _starts(p_buf: PoolByteArray, p_magic: Array) -> bool:
	if p_buf.size() < p_magic.size():
		return false
	for i in range(p_magic.size()):
		if p_buf[i] != p_magic[i]:
			return false
	return true
