extends Reference

# Adjuntos de media: helpers puros para XEP-0363 (HTTP File Upload) y el
# clasificado de archivos (imagen / audio / archivo) que consume la UI.
# Testeable headless: no toca red ni FS salvo el parser de WAV (que sólo mira
# bytes). El link del adjunto viaja por XEP-0066 (OOB); el builder/parseo del
# <message> vive en `message.gd` y acá sólo se construyen IQs de descubrimiento
# y de pedido de slot.

const Stanza = preload("res://addons/xat_xmpp/xmpp/stanza.gd")
const NS = preload("res://addons/xat_xmpp/xmpp/namespaces.gd")

const KIND_IMAGE := "image"
const KIND_AUDIO := "audio"
const KIND_FILE := "file"

# Techo de subida (los servidores de upload suelen limitar; 100 MiB es común).
const MAX_UPLOAD_SIZE := 104857600

# MIME por extensión. Subconjunto práctico (fotos, voz, documentos).
const MIME_BY_EXT := {
	"png": "image/png",
	"jpg": "image/jpeg",
	"jpeg": "image/jpeg",
	"gif": "image/gif",
	"webp": "image/webp",
	"bmp": "image/bmp",
	"heic": "image/heic",
	"heif": "image/heif",
	"ogg": "audio/ogg",
	"oga": "audio/ogg",
	"opus": "audio/opus",
	"mp3": "audio/mpeg",
	"m4a": "audio/mp4",
	"aac": "audio/aac",
	"wav": "audio/wav",
	"flac": "audio/flac",
	"pdf": "application/pdf",
	"txt": "text/plain",
	"zip": "application/zip",
}

const _IMAGE_PREFIX := "image/"
const _AUDIO_PREFIX := "audio/"

# --- Clasificación ---

static func extension_of(p_path: String) -> String:
	var name = p_path.get_file()
	var q = name.find("?")
	if q >= 0:
		name = name.substr(0, q)
	var h = name.find("#")
	if h >= 0:
		name = name.substr(0, h)
	var dot = name.find_last(".")
	if dot < 0 or dot == name.length() - 1:
		return ""
	return name.substr(dot + 1).to_lower()

static func mime_for_path(p_path: String) -> String:
	var ext = extension_of(p_path)
	return MIME_BY_EXT.get(ext, "application/octet-stream")

static func mime_for_ext(p_ext: String) -> String:
	return MIME_BY_EXT.get(p_ext.to_lower().lstrip("."), "application/octet-stream")

static func kind_for_mime(p_mime: String) -> String:
	var mime = p_mime.to_lower().split(";")[0].strip_edges()
	if mime.begins_with(_IMAGE_PREFIX):
		return KIND_IMAGE
	if mime.begins_with(_AUDIO_PREFIX):
		return KIND_AUDIO
	return KIND_FILE if mime != "" else ""

static func kind_for_path(p_path: String) -> String:
	return kind_for_mime(mime_for_path(p_path))

static func is_image_mime(p_mime: String) -> bool:
	return kind_for_mime(p_mime) == KIND_IMAGE

static func is_audio_mime(p_mime: String) -> bool:
	return kind_for_mime(p_mime) == KIND_AUDIO

# --- Nombres y links ---

# Basename seguro para el slot de subida (sin rutas ni caracteres problemáticos).
static func sanitize_filename(p_name: String, p_fallback: String = "archivo") -> String:
	var base = p_name.get_file().strip_edges()
	var out := ""
	for i in range(base.length()):
		var ch = base[i]
		if ch == "/" or ch == "\\" or ch == "\n" or ch == "\r" or ch == "\t" or ch == "\"":
			out += "_"
		else:
			out += ch
	out = out.lstrip(".").strip_edges()
	if out == "":
		return p_fallback
	return out

# Un nombre utilizable a partir de una URL (para descargar/cachear).
static func filename_from_url(p_url: String, p_fallback: String = "archivo") -> String:
	var path = p_url
	var q = path.find("?")
	if q >= 0:
		path = path.substr(0, q)
	var frag = path.find("#")
	if frag >= 0:
		path = path.substr(0, frag)
	var name = path.get_file()
	var dot = name.find_last(".")
	var ext = ""
	if dot >= 0 and dot < name.length() - 1:
		ext = name.substr(dot + 1).to_lower()
	if MIME_BY_EXT.has(ext):
		if name == "":
			return p_fallback + "." + ext
		return sanitize_filename(name, p_fallback + "." + ext)
	return p_fallback

# Primer URL http(s) de un texto (el body de un adjunto suele ser el link).
static func url_of(p_text: String) -> String:
	var text = p_text.strip_edges()
	for scheme in ["https://", "http://"]:
		var i = text.find(scheme)
		if i < 0:
			continue
		var rest = text.substr(i)
		var end = rest.length()
		for j in range(rest.length()):
			var ch = rest[j]
			if ch == " " or ch == "\n" or ch == "\r" or ch == "\t" or ch == "<" or ch == ">":
				end = j
				break
		var url = rest.substr(0, end)
		# Sacar puntuación de cierre pegada al link.
		while url.length() > 0 and (url.ends_with(".") or url.ends_with(",") or url.ends_with(")") or url.ends_with(";")):
			url = url.substr(0, url.length() - 1)
		return url
	return ""

# ¿El cuerpo es SÓLO el link (para no duplicarlo como texto bajo la media)?
static func is_url_only(p_body: String, p_url: String) -> bool:
	if p_url == "":
		return false
	var stripped = p_body.strip_edges()
	return stripped == p_url or stripped == ""

# Texto visible que queda al quitar el link del cuerpo (puede ser un pie de foto).
static func caption_of(p_body: String, p_url: String) -> String:
	var text = p_body.strip_edges()
	if p_url == "":
		return text
	var kept := []
	for line in text.split("\n"):
		if line.strip_edges() == p_url:
			continue
		kept.append(line)
	var out = PoolStringArray(kept).join("\n")
	# El link puede venir embebido en una línea (p. ej. "[image/png] f.png: URL").
	out = out.replace(p_url, "").strip_edges()
	# Quitar separadores que quedan colgando al final.
	while out.length() > 0:
		var last = out[out.length() - 1]
		if last == ":" or last == "-" or last == "·" or last == "|" or last == " " or last == "\n" or last == "\t":
			out = out.substr(0, out.length() - 1).strip_edges()
		else:
			break
	return out

# --- Sistema de archivos ---

# Tamaño en bytes de un archivo local; -1 si no existe o no se puede abrir.
# File.get_len() en Godot 3 no recibe argumentos: hay que abrir primero.
static func file_size(p_path: String) -> int:
	var f = File.new()
	if not f.file_exists(p_path):
		return -1
	if f.open(p_path, File.READ) != OK:
		return -1
	var n = f.get_len()
	f.close()
	return n

# --- Formato ---

static func format_size(p_bytes: int) -> String:
	var b = float(p_bytes)
	if b < 1024.0:
		return "%d B" % int(b)
	if b < 1024.0 * 1024.0:
		return "%.0f KB" % (b / 1024.0)
	if b < 1024.0 * 1024.0 * 1024.0:
		return "%.1f MB" % (b / (1024.0 * 1024.0))
	return "%.1f GB" % (b / (1024.0 * 1024.0 * 1024.0))

# Segundos -> "m:ss" (o "h:mm:ss").
static func format_duration(p_seconds: float) -> String:
	var total = int(max(0.0, p_seconds))
	var s = total % 60
	var m = (total / 60) % 60
	var h = total / 3600
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s]
	return "%d:%02d" % [m, s]

static func format_duration_ms(p_ms: int) -> String:
	return format_duration(float(p_ms) / 1000.0)

# Motivo de fallo legible (subida o descarga) a partir del código interno.
static func describe_error(p_code: String) -> String:
	if p_code == "sin-servicio":
		return "El servidor no ofrece subida de archivos"
	if p_code == "slot-error":
		return "El servidor rechazó la subida"
	if p_code == "file-too-large":
		return "El archivo supera el límite del servidor"
	if p_code == "http-413":
		return "El archivo supera el límite del servidor"
	if p_code == "archivo":
		return "No se pudo leer el archivo"
	if p_code == "no-soportado":
		return "No disponible en esta plataforma"
	if p_code.begins_with("http-"):
		return "Falló la transferencia (HTTP %s)" % p_code.substr(5)
	if p_code.begins_with("red-") or p_code.begins_with("no-se-pudo-iniciar"):
		return "Falló la transferencia (sin conexión)"
	return "No se pudo transferir el adjunto"

# Acorta un nombre largo conservando la extensión (para chips de adjunto).
static func short_name(p_name: String, p_max: int = 28) -> String:
	if p_name.length() <= p_max:
		return p_name
	var dot = p_name.find_last(".")
	var ext = ""
	if dot >= 0 and dot > p_name.length() - 6:
		ext = p_name.substr(dot)
	var keep = p_max - ext.length() - 1
	if keep < 4:
		keep = 4
	return p_name.substr(0, keep) + "…" + ext

# --- XEP-0363: descubrimiento del componente de subida ---

static func build_disco_items(p_iq_id: String, p_to: String):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "get")
	iq.set_attr("id", p_iq_id)
	iq.set_attr("to", p_to)
	var q = Stanza.new("query")
	q.set_attr("xmlns", NS.DISCO_ITEMS)
	iq.add_child_stanza(q)
	return iq

# JIDs de los items ofrecidos por el dominio (candidatos a componente de upload).
static func parse_disco_items(p_stanza) -> Array:
	var out := []
	var q = p_stanza.get_child("query", NS.DISCO_ITEMS)
	if q == null:
		return out
	for item in q.get_children("item"):
		var jid = item.get_attr("jid", "")
		if jid != "":
			out.append(jid)
	return out

static func build_disco_info(p_iq_id: String, p_to: String):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "get")
	iq.set_attr("id", p_iq_id)
	iq.set_attr("to", p_to)
	var q = Stanza.new("query")
	q.set_attr("xmlns", NS.DISCO_INFO)
	iq.add_child_stanza(q)
	return iq

static func disco_has_upload(p_stanza) -> bool:
	var q = p_stanza.get_child("query", NS.DISCO_INFO)
	if q == null:
		return false
	# Algunos servidores anuncian urn:xmpp:http:upload (v0.6) además de la :0.
	for f in q.get_children("feature"):
		var v = f.get_attr("var", "")
		if v == NS.HTTP_UPLOAD or v == "urn:xmpp:http:upload":
			return true
	return false

# Límite de subida anunciado por el componente (XEP-0363 max-file-size). 0 si
# no lo publica.
static func disco_max_file_size(p_stanza) -> int:
	var q = p_stanza.get_child("query", NS.DISCO_INFO)
	if q == null:
		return 0
	for x in q.get_children("x"):
		var form_type = ""
		var max_size = ""
		for field in x.get_children("field"):
			var var_name = field.get_attr("var", "")
			var value = field.get_child("value")
			var v = value.get_text() if value != null else ""
			if var_name == "FORM_TYPE":
				form_type = v
			elif var_name == "max-file-size":
				max_size = v
		if (form_type == NS.HTTP_UPLOAD or form_type == "urn:xmpp:http:upload") and max_size != "":
			return int(max_size)
	return 0


# --- XEP-0363: pedido de slot ---

static func build_slot_request(p_iq_id: String, p_to: String, p_filename: String, p_size: int, p_content_type: String):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "get")
	iq.set_attr("id", p_iq_id)
	iq.set_attr("to", p_to)
	var req = Stanza.new("request")
	req.set_attr("xmlns", NS.HTTP_UPLOAD)
	req.set_attr("filename", p_filename)
	req.set_attr("size", str(p_size))
	req.set_attr("content-type", p_content_type)
	iq.add_child_stanza(req)
	return iq

# Resultado del slot: {ok, put_url, get_url, headers:[{name,value}], error}.
static func parse_slot_result(p_stanza) -> Dictionary:
	var out := {"ok": false, "put_url": "", "get_url": "", "headers": [], "error": ""}
	if p_stanza.get_attr("type", "") == "error":
		out["error"] = "error"
		return out
	var slot = p_stanza.get_child("slot", NS.HTTP_UPLOAD)
	if slot == null:
		slot = p_stanza.get_child("slot", "urn:xmpp:http:upload")
	if slot == null:
		out["error"] = "no-slot"
		return out
	var put = slot.get_child("put")
	var get = slot.get_child("get")
	# Las URLs vienen en el atributo `url=`, no como texto.
	out["put_url"] = put.get_attr("url", "") if put != null else ""
	out["get_url"] = get.get_attr("url", "") if get != null else ""
	if put != null:
		for h in put.get_children("header"):
			var name = h.get_attr("name", "")
			var value = h.get_text()
			if name != "" and value != "":
				out["headers"].append({"name": name, "value": value})
	out["ok"] = out["put_url"] != "" and out["get_url"] != ""
	if not out["ok"]:
		out["error"] = "slot-incompleto"
	return out

# Cabeceras del slot como PoolStringArray "Name: value" (HTTPRequest).
static func headers_array(p_headers: Array) -> PoolStringArray:
	var out := PoolStringArray()
	for h in p_headers:
		out.append(str(h.get("name", "")) + ": " + str(h.get("value", "")))
	return out

# --- WAV (para reproducir lo grabado y los audios recibidos) ---

# Parsea un WAV PCM y devuelve {ok, mix_rate, stereo, format, data} donde
# `format` es la constante de AudioStreamSample (FORMAT_8_BITS=0,
# FORMAT_16_BITS=1). Sólo soporta PCM entero (que es lo que graba Godot y lo
# habitual en voz). Los formatos comprimidos se rechazan con ok=false.
static func parse_wav(p_bytes: PoolByteArray) -> Dictionary:
	var out := {"ok": false, "mix_rate": 44100, "stereo": false, "format": 1, "data": PoolByteArray()}
	if p_bytes.size() < 44:
		return out
	if p_bytes[0] == 0x52 and p_bytes[1] == 0x49 and p_bytes[2] == 0x46 and p_bytes[3] == 0x46:
		pass
	else:
		return out
	if p_bytes[8] != 0x57 or p_bytes[9] != 0x41 or p_bytes[10] != 0x56 or p_bytes[11] != 0x45:
		return out
	var pos := 12
	var fmt_found := false
	var bits := 16
	var channels := 1
	while pos + 8 <= p_bytes.size():
		var cid = _ascii4(p_bytes, pos)
		var csize = _u32(p_bytes, pos + 4)
		var body = pos + 8
		if cid == "fmt " and body + 16 <= p_bytes.size():
			var audio_format = _u16(p_bytes, body)
			channels = _u16(p_bytes, body + 2)
			out["mix_rate"] = _u32(p_bytes, body + 4)
			bits = _u16(p_bytes, body + 14)
			if audio_format != 1 and audio_format != 0xFFFE:
				return out # no-PCM
			fmt_found = true
		elif cid == "data":
			if not fmt_found:
				return out
			var take = min(int(csize), p_bytes.size() - body)
			out["data"] = p_bytes.subarray(body, body + take - 1)
			out["stereo"] = channels > 1
			if bits == 8:
				out["format"] = 0
			elif bits == 16:
				out["format"] = 1
			else:
				return out
			out["ok"] = out["data"].size() > 0
			return out
		pos = body + int(csize)
		if int(csize) == 0:
			break
	return out

static func _ascii4(p_bytes: PoolByteArray, p_pos: int) -> String:
	var s := ""
	for i in range(4):
		s += char(p_bytes[p_pos + i])
	return s

static func _u16(p_bytes: PoolByteArray, p_pos: int) -> int:
	return p_bytes[p_pos] | (p_bytes[p_pos + 1] << 8)

static func _u32(p_bytes: PoolByteArray, p_pos: int) -> int:
	return p_bytes[p_pos] | (p_bytes[p_pos + 1] << 8) | (p_bytes[p_pos + 2] << 16) | (p_bytes[p_pos + 3] << 24)

# --- Audio de voz: downmix + remuestreo + WAV IMA-ADPCM (ver adpcm.gd) ---

# Baja a mono y remuestrea por interpolación lineal a p_rate. Entrada y salida
# PCM16 LE. Pensado para voz (44.1 kHz estéreo -> 16 kHz mono), donde el coste
# de calidad es despreciable frente al ahorro de tamaño.
static func downmix_resample(p_pcm: PoolByteArray, p_channels: int, p_in_rate: int, p_out_rate: int) -> PoolByteArray:
	var n = p_pcm.size() / 2
	if n == 0 or p_channels <= 0 or p_out_rate <= 0:
		return PoolByteArray()
	var frames = n / p_channels
	if frames == 0:
		return PoolByteArray()
	# 1) Downmix a mono float.
	var mono := PoolRealArray()
	mono.resize(frames)
	for f in range(frames):
		var acc := 0.0
		for ch in range(p_channels):
			acc += _sample_at(p_pcm, f * p_channels + ch)
		mono[f] = acc / float(p_channels)
	# 2) Remuestreo lineal a out_rate.
	var out_frames = int(round(frames * float(p_out_rate) / float(p_in_rate)))
	if out_frames <= 0:
		return PoolByteArray()
	var out := PoolByteArray()
	out.resize(out_frames * 2)
	var ratio = float(p_in_rate) / float(p_out_rate)
	for i in range(out_frames):
		var src = i * ratio
		var i0 = int(floor(src))
		var i1 = min(i0 + 1, frames - 1)
		var t = src - i0
		if i0 > frames - 1:
			i0 = frames - 1
		var s = int(round(mono[i0] * (1.0 - t) + mono[i1] * t))
		s = int(clamp(s, -32768, 32767))
		var u = s if s >= 0 else s + 65536
		out[i * 2] = u & 0xFF
		out[i * 2 + 1] = (u >> 8) & 0xFF
	return out

static func _sample_at(p_pcm: PoolByteArray, p_index: int) -> float:
	var v = p_pcm[p_index * 2] | (p_pcm[p_index * 2 + 1] << 8)
	if v >= 32768:
		v -= 65536
	return float(v)

# Arma un WAV IMA-ADPCM (format 0x11) a partir del bloque codificado.
# p_enc es la salida de Adpcm.encode.
static func build_wav_adpcm(p_enc: Dictionary) -> PoolByteArray:
	var channels = int(p_enc["channels"])
	var rate = int(p_enc["sample_rate"])
	var block_align = int(p_enc["block_align"])
	var spb = int(p_enc["samples_per_block"])
	var data: PoolByteArray = p_enc["data"]
	var out := PoolByteArray()
	out.append_array("RIFF".to_utf8())
	out.append_array(_le(36 + data.size(), 4))
	out.append_array("WAVE".to_utf8())
	out.append_array("fmt ".to_utf8())
	out.append_array(_le(20, 4)) # tamaño del bloque fmt con extension
	out.append_array(_le(0x11, 2)) # WAVE_FORMAT_IMA_ADPCM
	out.append_array(_le(channels, 2))
	out.append_array(_le(rate, 4))
	# byte rate = (rate / spb) * block_align
	out.append_array(_le(int(rate / spb) * block_align, 4))
	out.append_array(_le(block_align, 2))
	out.append_array(_le(4, 2)) # bits por muestra (4) -- convención ADPCM
	out.append_array(_le(2, 2)) # cbSize (extension)
	out.append_array(_le(spb, 2)) # samples per block
	out.append_array("data".to_utf8())
	out.append_array(_le(data.size(), 4))
	out.append_array(data)
	return out

# Devuelve true si el WAV (en bytes) usa IMA-ADPCM.
static func is_wav_adpcm(p_bytes: PoolByteArray) -> bool:
	if p_bytes.size() < 24:
		return false
	return _ascii4(p_bytes, 0) == "RIFF" and _ascii4(p_bytes, 8) == "WAVE" and _u16(p_bytes, 20) == 0x11

# Lee un WAV IMA-ADPCM -> {ok, channels, sample_rate, samples_per_block, data}.
static func parse_wav_adpcm(p_bytes: PoolByteArray) -> Dictionary:
	var out := {"ok": false, "channels": 1, "sample_rate": 8000, "samples_per_block": 505, "data": PoolByteArray()}
	if p_bytes.size() < 44 or _ascii4(p_bytes, 0) != "RIFF" or _ascii4(p_bytes, 8) != "WAVE":
		return out
	var pos := 12
	var got_fmt := false
	while pos + 8 <= p_bytes.size():
		var cid = _ascii4(p_bytes, pos)
		var csize = _u32(p_bytes, pos + 4)
		var body = pos + 8
		if cid == "fmt " and body + 20 <= p_bytes.size():
			if _u16(p_bytes, body) != 0x11:
				return out
			out["channels"] = _u16(p_bytes, body + 2)
			out["sample_rate"] = _u32(p_bytes, body + 4)
			out["samples_per_block"] = _u16(p_bytes, body + 18)
			got_fmt = true
		elif cid == "data":
			if not got_fmt:
				return out
			var take = min(int(csize), p_bytes.size() - body)
			out["data"] = p_bytes.subarray(body, body + take - 1)
			out["ok"] = out["data"].size() > 0
			return out
		pos = body + int(csize)
		if int(csize) == 0:
			break
	return out

static func _le(p_value: int, p_bytes: int) -> PoolByteArray:
	var out := PoolByteArray()
	for i in range(p_bytes):
		out.append((p_value >> (8 * i)) & 0xFF)
	return out
