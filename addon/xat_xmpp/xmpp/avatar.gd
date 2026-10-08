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
