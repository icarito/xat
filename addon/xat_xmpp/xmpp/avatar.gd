extends Reference

# XEP-0084 avatares: pedido del item de datos, parseo del resultado y caché en
# disco por id (sha1 del publicador). Puro salvo la caché (archivos).

const NS = preload("res://addons/xat_xmpp/xmpp/namespaces.gd")
const Stanza = preload("res://addons/xat_xmpp/xmpp/stanza.gd")

const CACHE_DIR := "user://avatars"

# <iq type=get to=bare><pubsub><items node=urn:xmpp:avatar:data><item id/></items></pubsub></iq>
static func build_data_request(p_iq_id: String, p_to_bare: String, p_item_id: String):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "get")
	iq.set_attr("id", p_iq_id)
	iq.set_attr("to", p_to_bare)
	var pubsub = Stanza.new("pubsub")
	pubsub.set_attr("xmlns", NS.PUBSUB)
	var items = Stanza.new("items")
	items.set_attr("node", NS.AVATAR_DATA)
	var item = Stanza.new("item")
	item.set_attr("id", p_item_id)
	items.add_child_stanza(item)
	pubsub.add_child_stanza(items)
	iq.add_child_stanza(pubsub)
	return iq

# Resultado del pedido -> {item_id, base64} (vacío si no es un resultado de avatar).
static func parse_data_result(p_iq) -> Dictionary:
	var out := {"item_id": "", "base64": ""}
	var pubsub = p_iq.get_child("pubsub", NS.PUBSUB) if p_iq != null else null
	var items = pubsub.get_child("items") if pubsub != null else null
	if items == null or items.get_attr("node", "") != NS.AVATAR_DATA:
		return out
	var item = items.get_child("item")
	var data = item.get_child("data", NS.AVATAR_DATA) if item != null else null
	if data == null:
		return out
	out["item_id"] = item.get_attr("id", "")
	out["base64"] = data.get_text().strip_edges()
	return out

static func ext_for_type(p_type: String) -> String:
	match p_type:
		"image/jpeg", "image/jpg":
			return "jpg"
		"image/webp":
			return "webp"
	return "png"

static func cache_path(p_id: String, p_type: String) -> String:
	# El id es hex (sha1); se filtra igual por si un peer manda basura.
	return "%s/%s.%s" % [CACHE_DIR, p_id.validate_node_name().replace("/", ""), ext_for_type(p_type)]

static func save(p_path: String, p_bytes: PoolByteArray) -> bool:
	Directory.new().make_dir_recursive(CACHE_DIR)
	var f = File.new()
	if f.open(p_path, File.WRITE) != OK:
		return false
	f.store_buffer(p_bytes)
	f.close()
	return true

# Carga un avatar cacheado como textura (null si falta o no decodifica).
static func load_texture(p_path: String):
	var f = File.new()
	if not f.file_exists(p_path) or f.open(p_path, File.READ) != OK:
		return null
	var bytes = f.get_buffer(f.get_len())
	f.close()
	var img = Image.new()
	var rc = ERR_FILE_UNRECOGNIZED
	if p_path.ends_with(".jpg"):
		rc = img.load_jpg_from_buffer(bytes)
	elif p_path.ends_with(".webp"):
		rc = img.load_webp_from_buffer(bytes)
	else:
		rc = img.load_png_from_buffer(bytes)
	if rc != OK:
		return null
	# JPEG decodifica a RGB8 y Adreno (GLES3 en Android) pinta negro con
	# FLAG_MIPMAPS: normalizar a RGBA8 y sin mipmaps.
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var tex = ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_FILTER)
	return tex

# --- Publicación (XEP-0084) ---

# SHA-1 hex de los bytes: XEP-0084 usa el sha1 del archivo como id del item.
static func sha1_hex(p_bytes: PoolByteArray) -> String:
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(p_bytes)
	var digest: PoolByteArray = ctx.finish()
	var s = ""
	for b in digest:
		s += "%02x" % b
	return s

# Procesa una imagen de disco a un avatar cuadrado de lado <= p_side y devuelve
# {bytes, mime, width, height, id}; {} si no se pudo leer.
static func process(p_path: String, p_side: int = 96) -> Dictionary:
	var img := Image.new()
	if img.load(p_path) != OK:
		return {}
	# Recorte cuadrado centrado (los avatares son cuadrados).
	var w = img.get_width()
	var h = img.get_height()
	if w <= 0 or h <= 0:
		return {}
	var side = int(min(w, h))
	if side != w or side != h:
		var off = Vector2(int((w - side) / 2), int((h - side) / 2))
		img = img.get_rect(Rect2(off, Vector2(side, side)))
	if img.get_width() > p_side:
		img.resize(p_side, p_side, Image.INTERPOLATE_BILINEAR)
	var bytes = img.save_png_to_buffer()
	var mime := "image/png"
	# PEP recomienda <=8 KiB; si el PNG es grande, JPEG pesa mucho menos.
	if bytes.size() > 24 * 1024:
		var jpg = img.save_jpg_to_buffer(0.85)
		if jpg.size() < bytes.size():
			bytes = jpg
			mime = "image/jpeg"
	return {"bytes": bytes, "mime": mime, "width": img.get_width(), "height": img.get_height(), "id": sha1_hex(bytes)}

# <iq type=set><pubsub><publish node=urn:xmpp:avatar:data><item id><data>B64
static func build_publish_data(p_iq_id: String, p_item_id: String, p_base64: String):
	var pubsub = Stanza.new("pubsub")
	pubsub.set_attr("xmlns", NS.PUBSUB)
	var publish = Stanza.new("publish")
	publish.set_attr("node", NS.AVATAR_DATA)
	var item = Stanza.new("item")
	item.set_attr("id", p_item_id)
	var data = Stanza.new("data")
	data.set_attr("xmlns", NS.AVATAR_DATA)
	data.append_text(p_base64)
	item.add_child_stanza(data)
	publish.add_child_stanza(item)
	pubsub.add_child_stanza(publish)
	pubsub.add_child_stanza(_publish_options())
	return _iq(p_iq_id, pubsub)

# Metadata: <metadata><info bytes id type width height/></metadata>.
static func build_publish_metadata(p_iq_id: String, p_item_id: String, p_bytes: int, p_mime: String, p_width: int, p_height: int):
	var pubsub = Stanza.new("pubsub")
	pubsub.set_attr("xmlns", NS.PUBSUB)
	var publish = Stanza.new("publish")
	publish.set_attr("node", NS.AVATAR_METADATA)
	var item = Stanza.new("item")
	item.set_attr("id", p_item_id)
	var meta = Stanza.new("metadata")
	meta.set_attr("xmlns", NS.AVATAR_METADATA)
	var info = Stanza.new("info")
	info.set_attr("bytes", str(p_bytes))
	info.set_attr("id", p_item_id)
	info.set_attr("type", p_mime)
	info.set_attr("width", str(p_width))
	info.set_attr("height", str(p_height))
	meta.add_child_stanza(info)
	item.add_child_stanza(meta)
	publish.add_child_stanza(item)
	pubsub.add_child_stanza(publish)
	pubsub.add_child_stanza(_publish_options())
	return _iq(p_iq_id, pubsub)

static func _iq(p_id: String, p_pubsub):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "set")
	iq.set_attr("id", p_id)
	iq.add_child_stanza(p_pubsub)
	return iq

# Config del nodo PEP en el primer publish: accesible por presencia (lo que
# necesitan los contactos para ver el avatar), un solo item, persistente.
static func _publish_options():
	var po = Stanza.new("publish-options")
	var x = Stanza.new("x")
	x.set_attr("xmlns", NS.DATA_FORMS)
	x.set_attr("type", "submit")
	x.add_child_stanza(_field("FORM_TYPE", NS.PUBSUB_PUBLISH_OPTIONS))
	x.add_child_stanza(_field("pubsub#access_model", "presence"))
	x.add_child_stanza(_field("pubsub#max_items", "1"))
	x.add_child_stanza(_field("pubsub#persist_items", "1"))
	po.add_child_stanza(x)
	return po

static func _field(p_var: String, p_value: String):
	var field = Stanza.new("field")
	field.set_attr("var", p_var)
	var value = Stanza.new("value")
	value.append_text(p_value)
	field.add_child_stanza(value)
	return field
