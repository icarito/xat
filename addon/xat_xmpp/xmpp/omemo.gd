extends Reference

# Modelo OMEMO (XEP-0384) puro: parsing y serialización de las piezas que viajan
# por el cable — `<encrypted>`, listas de dispositivos, bundles, el envelope SCE
# (XEP-0420) y el protobuf de los mensajes internos. NO hace criptografía: eso
# vive en el módulo nativo `modules/xmpp` (monocypher + mbedTLS). Testeable
# headless.
#
# Interop verificado contra openclaw-xmpp: `src/omemo/index.ts` (formato de
# `<encrypted>`, SCE, detección de kex), `src/omemo/v2-crypto.ts` (números de
# campo del protobuf) y `src/omemo/sidecar.py` (POJO con twomemo).
#
# Convención: los blobs (claves, payload) se manejan como base64 en las caras
# públicas (lo que va en el XML) y como PoolByteArray en el protobuf.

const NS_V2 := "urn:xmpp:omemo:2"
const NS_LEGACY := "eu.siacs.conversations.axolotl"
const NS_SCE := "urn:xmpp:sce:1"
const NS_JABBER_CLIENT := "jabber:client"

# Nodos PEP. En v2 el bundle va un item por dispositivo dentro de `…:bundles`.
const NODE_DEVICES := "urn:xmpp:omemo:2:devices"
const NODE_BUNDLES := "urn:xmpp:omemo:2:bundles"
const NODE_DEVICES_LEGACY := "eu.siacs.conversations.axolotl.devicelist"
const NODE_BUNDLES_LEGACY := "eu.siacs.conversations.axolotl.bundles"

# --- Localización de la stanza cifrada ---

# Devuelve el `<encrypted>` (v2 o legacy) de una stanza, o null.
static func encrypted_child(p_stanza):
	if p_stanza == null:
		return null
	var el = p_stanza.get_child("encrypted", NS_V2)
	if el != null:
		return el
	return p_stanza.get_child("encrypted", NS_LEGACY)

static func is_encrypted(p_stanza) -> bool:
	return encrypted_child(p_stanza) != null

static func encrypted_namespace(p_enc) -> String:
	if p_enc == null:
		return ""
	return str(p_enc.get_attr("xmlns", NS_V2))

static func is_v2(p_enc) -> bool:
	return encrypted_namespace(p_enc) == NS_V2

# --- Mensaje cifrado ---

# Parsea el `<encrypted>`. `p_own_rid` es nuestro device id: si se pasa, se
# resuelve `our` (la entrada `<key>` destinada a nosotros) y `our_prekey`.
# Devuelve {namespace, sid, payload_b64, iv_b64, keys: [...], our, our_prekey}.
static func parse_encrypted(p_enc, p_own_rid: int = -1) -> Dictionary:
	var out := {
		"namespace": NS_V2,
		"sid": -1,
		"payload_b64": "",
		"iv_b64": "",
		"keys": [],
		"our": {},
		"our_prekey": false,
	}
	if p_enc == null:
		return out
	var ns := encrypted_namespace(p_enc)
	out["namespace"] = ns
	var legacy := ns == NS_LEGACY
	var header = p_enc.get_child("header")
	if header != null:
		out["sid"] = int(str(header.get_attr("sid", "-1")))
		var iv = header.get_child("iv")
		if iv != null:
			out["iv_b64"] = iv.get_text().strip_edges()
		# v2 agrupa por jid en `<keys jid=…><key rid=…/></keys>`; legacy cuelga
		# los `<key/>` directo del header.
		if legacy:
			for k in header.get_children("key"):
				out["keys"].append(_key_entry("", k, legacy))
		else:
			for keys in header.get_children("keys"):
				var jid := str(keys.get_attr("jid", ""))
				for k in keys.get_children("key"):
					out["keys"].append(_key_entry(jid, k, legacy))
	var payload = p_enc.get_child("payload")
	if payload != null:
		out["payload_b64"] = payload.get_text().strip_edges()
	if p_own_rid >= 0:
		for e in out["keys"]:
			if e["rid"] == p_own_rid:
				out["our"] = e
				out["our_prekey"] = e["prekey"]
				break
	return out

static func _key_entry(p_jid: String, p_key, p_legacy: bool) -> Dictionary:
	var prekey := false
	if p_legacy:
		prekey = _flag(p_key, "prekey")
	else:
		prekey = _flag(p_key, "kex")
	return {
		"jid": p_jid,
		"rid": int(str(p_key.get_attr("rid", "-1"))),
		"prekey": prekey,
		"key_b64": p_key.get_text().strip_edges(),
	}

static func _flag(p_el, p_attr: String) -> bool:
	var v := str(p_el.get_attr(p_attr, ""))
	return v == "true" or v == "1"

# --- Dispositivos (PEP) ---

# `<devices xmlns="urn:xmpp:omemo:2"><device id="1" label="x"/>…</devices>`
# (legacy: `<list><device id=…/>`). Devuelve [{id, label}].
static func parse_device_list(p_el) -> Array:
	var out := []
	if p_el == null:
		return out
	var container = p_el
	if p_el.name != "devices" and p_el.name != "list":
		container = p_el.get_child("devices")
		if container == null:
			container = p_el.get_child("list")
	if container == null:
		return out
	for d in container.get_children("device"):
		out.append({
			"id": int(str(d.get_attr("id", "-1"))),
			"label": str(d.get_attr("label", "")),
		})
	return out

static func serialize_device_list(p_devices: Array, p_v2: bool = true) -> String:
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")
	var root = Stanza.new("devices" if p_v2 else "list")
	root.set_attr("xmlns", NS_V2 if p_v2 else NS_LEGACY)
	for d in p_devices:
		var e = Stanza.new("device")
		e.set_attr("id", str(d.get("id", "")))
		if str(d.get("label", "")) != "":
			e.set_attr("label", str(d["label"]))
		root.add_child_stanza(e)
	return root.to_xml()

# --- Bundle (PEP) ---

# v2: <bundle xmlns="urn:xmpp:omemo:2"><spk id>…</spk><spks>…</spks><ik>…</ik>
#     <prekeys><pk id>…</pk>…</prekeys></bundle>
# legacy: <bundle xmlns="eu.siacs.conversations.axolotl">
#     <signedPreKeyPublic signedPreKeyId>…</signedPreKeyPublic>
#     <signedPreKeySignature>…</signedPreKeySignature><identityKey>…</identityKey>
#     <prekeys><preKeyPublic preKeyId>…</preKeyPublic>…</prekeys></bundle>
# Devuelve {identity_b64, spk: {id, b64}, spk_sig_b64, prekeys: [{id, b64}]}.
static func parse_bundle(p_el) -> Dictionary:
	var out := {"identity_b64": "", "spk": {"id": -1, "b64": ""}, "spk_sig_b64": "", "prekeys": []}
	if p_el == null:
		return out
	var legacy := str(p_el.get_attr("xmlns", NS_V2)) == NS_LEGACY
	if legacy:
		var ik = p_el.get_child("identityKey")
		if ik != null:
			out["identity_b64"] = ik.get_text().strip_edges()
		var spk = p_el.get_child("signedPreKeyPublic")
		if spk != null:
			out["spk"] = {"id": int(str(spk.get_attr("signedPreKeyId", "-1"))), "b64": spk.get_text().strip_edges()}
		var sig = p_el.get_child("signedPreKeySignature")
		if sig != null:
			out["spk_sig_b64"] = sig.get_text().strip_edges()
		var pre = p_el.get_child("prekeys")
		if pre != null:
			for pk in pre.get_children("preKeyPublic"):
				out["prekeys"].append({"id": int(str(pk.get_attr("preKeyId", "-1"))), "b64": pk.get_text().strip_edges()})
	else:
		var ik2 = p_el.get_child("ik")
		if ik2 != null:
			out["identity_b64"] = ik2.get_text().strip_edges()
		var spk2 = p_el.get_child("spk")
		if spk2 != null:
			out["spk"] = {"id": int(str(spk2.get_attr("id", "-1"))), "b64": spk2.get_text().strip_edges()}
		var sig2 = p_el.get_child("spks")
		if sig2 != null:
			out["spk_sig_b64"] = sig2.get_text().strip_edges()
		var pre2 = p_el.get_child("prekeys")
		if pre2 != null:
			for pk2 in pre2.get_children("pk"):
				out["prekeys"].append({"id": int(str(pk2.get_attr("id", "-1"))), "b64": pk2.get_text().strip_edges()})
	return out

static func serialize_bundle(p_bundle: Dictionary, p_v2: bool = true) -> String:
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")
	var root = Stanza.new("bundle")
	root.set_attr("xmlns", NS_V2 if p_v2 else NS_LEGACY)
	if p_v2:
		var spk = Stanza.new("spk")
		spk.set_attr("id", str(p_bundle.get("spk", {}).get("id", "")))
		spk.append_text(str(p_bundle.get("spk", {}).get("b64", "")))
		root.add_child_stanza(spk)
		_leaf(root, "spks", str(p_bundle.get("spk_sig_b64", "")))
		_leaf(root, "ik", str(p_bundle.get("identity_b64", "")))
		var pre = Stanza.new("prekeys")
		for pk in p_bundle.get("prekeys", []):
			var e = Stanza.new("pk")
			e.set_attr("id", str(pk.get("id", "")))
			e.append_text(str(pk.get("b64", "")))
			pre.add_child_stanza(e)
		root.add_child_stanza(pre)
	else:
		var spk = Stanza.new("signedPreKeyPublic")
		spk.set_attr("signedPreKeyId", str(p_bundle.get("spk", {}).get("id", "")))
		spk.append_text(str(p_bundle.get("spk", {}).get("b64", "")))
		root.add_child_stanza(spk)
		_leaf(root, "signedPreKeySignature", str(p_bundle.get("spk_sig_b64", "")))
		_leaf(root, "identityKey", str(p_bundle.get("identity_b64", "")))
		var pre = Stanza.new("prekeys")
		for pk in p_bundle.get("prekeys", []):
			var e = Stanza.new("preKeyPublic")
			e.set_attr("preKeyId", str(pk.get("id", "")))
			e.append_text(str(pk.get("b64", "")))
			pre.add_child_stanza(e)
		root.add_child_stanza(pre)
	return root.to_xml()

# --- Payloads PEP (XEP-0163): device list y bundle ---

# `<devices xmlns="urn:xmpp:omemo:2"><device id label/></devices>`.
static func build_devices_element(p_devices: Array):
	return _parse(serialize_device_list(p_devices, true))

# `<bundle xmlns="urn:xmpp:omemo:2">...` desde el bundle del dispositivo
# ({ik, spk, spk_id, spk_sig, prekeys:[{id, pub}]}).
static func build_bundle_element(p_dev_bundle: Dictionary, p_v2: bool = true):
	var prekeys := []
	for p in p_dev_bundle.get("prekeys", []):
		prekeys.append({"id": p.get("id", -1), "b64": Marshalls.raw_to_base64(p.get("pub", PoolByteArray()))})
	var b := {
		"identity_b64": Marshalls.raw_to_base64(p_dev_bundle.get("ik", PoolByteArray())),
		"spk": {"id": p_dev_bundle.get("spk_id", -1), "b64": Marshalls.raw_to_base64(p_dev_bundle.get("spk", PoolByteArray()))},
		"spk_sig_b64": Marshalls.raw_to_base64(p_dev_bundle.get("spk_sig", PoolByteArray())),
		"prekeys": prekeys,
	}
	return _parse(serialize_bundle(b, p_v2))

static func _leaf(p_parent, p_name: String, p_text: String) -> void:
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")
	var e = Stanza.new(p_name)
	e.append_text(p_text)
	p_parent.add_child_stanza(e)

# --- Envelope SCE (XEP-0420) ---

# Construye el envelope que se autentica y cifra. `p_rpad` permite fijar el
# relleno (para tests); vacío => aleatorio 0..200 letras.
static func build_sce_envelope(p_body: String, p_to: String = "", p_rpad: String = "") -> String:
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")
	var rpad := p_rpad
	if rpad == "":
		var n := int(randf() * 200.0)
		for _i in range(n):
			rpad += char(65 + int(randf() * 26.0))
	var env = Stanza.new("envelope")
	env.set_attr("xmlns", NS_SCE)
	var content = Stanza.new("content")
	content.set_attr("xmlns", NS_SCE)
	var body = Stanza.new("body")
	body.set_attr("xmlns", NS_JABBER_CLIENT)
	body.append_text(p_body)
	content.add_child_stanza(body)
	env.add_child_stanza(content)
	_leaf(env, "rpad", rpad)
	if p_to != "":
		var to = Stanza.new("to")
		to.set_attr("jid", _bare(p_to))
		env.add_child_stanza(to)
	return env.to_xml()

# Extrae el body del envelope descifrado. Si no es SCE (texto plano legacy),
# lo devuelve tal cual.
static func unwrap_sce(p_payload: String) -> String:
	if p_payload.find(NS_SCE) < 0:
		return p_payload
	var env = _parse(p_payload)
	if env == null:
		return p_payload
	var content = env.get_child("content")
	if content == null:
		return p_payload
	var body = content.get_child("body")
	if body == null:
		return p_payload
	return body.get_text()

static func _bare(p_jid: String) -> String:
	var s := p_jid.strip_edges()
	var i := s.find("/")
	return s if i < 0 else s.substr(0, i)

static func _parse(p_xml: String):
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")
	return Stanza.parse(p_xml)

# --- Protobuf de los mensajes internos (XEP-0384 §4) ---
#
# OMEMOMessage{n=1, pn=2, dh_pub=3, ciphertext=4}
# OMEMOAuthenticatedMessage{mac=1, message=2}
# Los números de campo coinciden con `v2-crypto.ts` de openclaw-xmpp.

# OMEMOKeyExchange{pk_id=1, spk_id=2, ik=3, ek=4, message=5}.
static func encode_key_exchange(p_pk_id: int, p_spk_id: int, p_ik: PoolByteArray, p_ek: PoolByteArray, p_message: PoolByteArray) -> PoolByteArray:
	var out := PoolByteArray()
	out.append_array(_pb_varint_field(1, p_pk_id))
	out.append_array(_pb_varint_field(2, p_spk_id))
	out.append_array(_pb_bytes_field(3, p_ik))
	out.append_array(_pb_bytes_field(4, p_ek))
	out.append_array(_pb_bytes_field(5, p_message))
	return out

static func parse_key_exchange(p_bytes: PoolByteArray) -> Dictionary:
	var f := _pb_fields(p_bytes)
	var out := {"pk_id": -1, "spk_id": -1, "ik": PoolByteArray(), "ek": PoolByteArray(), "message": PoolByteArray()}
	if not f.has(1) or not f.has(2) or not f.has(3) or not f.has(4) or not f.has(5):
		return out
	out["pk_id"] = int(f[1][0])
	out["spk_id"] = int(f[2][0])
	out["ik"] = f[3][0]
	out["ek"] = f[4][0]
	out["message"] = f[5][0]
	return out

# Separa un OMEMOAuthenticatedMessage en mac y el OMEMOMessage crudo.
static func split_authenticated(p_bytes: PoolByteArray) -> Dictionary:
	var f := _pb_fields(p_bytes)
	if not f.has(1) or not f.has(2):
		return {}
	return {"mac": f[1][0], "message": f[2][0]}

static func encode_authenticated_message(p_ciphertext: PoolByteArray, p_mac: PoolByteArray, p_n: int = 0, p_pn: int = 0, p_dh_pub = null) -> PoolByteArray:
	var dh = p_dh_pub if p_dh_pub != null else PoolByteArray()
	var inner := PoolByteArray()
	inner.append_array(_pb_varint_field(1, p_n))
	inner.append_array(_pb_varint_field(2, p_pn))
	inner.append_array(_pb_bytes_field(3, dh))
	inner.append_array(_pb_bytes_field(4, p_ciphertext))
	var out := PoolByteArray()
	out.append_array(_pb_bytes_field(1, p_mac))
	out.append_array(_pb_bytes_field(2, inner))
	return out

static func decode_authenticated_message(p_bytes: PoolByteArray) -> Dictionary:
	var outer := _pb_fields(p_bytes)
	var m_outer = outer.get(1, [])
	var msg = outer.get(2, [])
	if m_outer.empty() or msg.empty():
		return {}
	var inner := _pb_fields(msg[0])
	var ct = inner.get(4, [])
	if ct.empty():
		return {}
	var n := 0
	var pn := 0
	var dh := PoolByteArray()
	if not inner.get(1, []).empty():
		n = int(inner[1][0])
	if not inner.get(2, []).empty():
		pn = int(inner[2][0])
	if not inner.get(3, []).empty():
		dh = inner[3][0]
	return {
		"mac": m_outer[0],
		"ciphertext": ct[0],
		"n": n,
		"pn": pn,
		"dh_pub": dh,
	}

# Lee protobuf wire format. Devuelve field -> Array (int para wire 0, bytes
# para wire 2). Lanza si aparece un wire type no soportado.
static func _pb_fields(p_buf: PoolByteArray) -> Dictionary:
	var out := {}
	var i := 0
	var n := p_buf.size()
	while i < n:
		var tag := _pb_read_varint(p_buf, i)
		i = tag[1]
		var field = tag[0] >> 3
		var wire = tag[0] & 7
		if wire == 0:
			var v := _pb_read_varint(p_buf, i)
			i = v[1]
			_pb_push(out, field, v[0])
		elif wire == 2:
			var ln := _pb_read_varint(p_buf, i)
			i = ln[1]
			var end := i + int(ln[0])
			if end > n:
				break
			var slice := p_buf.subarray(i, end - 1)
			i = end
			_pb_push(out, field, slice)
		else:
			break
	return out

static func _pb_push(p_fields: Dictionary, p_field: int, p_value) -> void:
	var list = p_fields.get(p_field, [])
	list.append(p_value)
	p_fields[p_field] = list

static func _pb_read_varint(p_buf: PoolByteArray, p_offset: int) -> Array:
	var value := 0
	var shift := 0
	var i := p_offset
	while i < p_buf.size() and shift < 35:
		var b := int(p_buf[i])
		i += 1
		value |= (b & 0x7f) << shift
		if (b & 0x80) == 0:
			return [value, i]
		shift += 7
	return [value, i]

static func _pb_varint(p_n: int) -> PoolByteArray:
	var out := PoolByteArray()
	var x := p_n
	while true:
		var b := x & 0x7f
		x = x >> 7
		if x != 0:
			out.append(b | 0x80)
		else:
			out.append(b)
			break
	return out

static func _pb_bytes_field(p_field: int, p_bytes: PoolByteArray) -> PoolByteArray:
	var out := PoolByteArray()
	out.append((p_field << 3) | 2)
	out.append_array(_pb_varint(p_bytes.size()))
	out.append_array(p_bytes)
	return out

static func _pb_varint_field(p_field: int, p_value: int) -> PoolByteArray:
	var out := PoolByteArray()
	out.append(p_field << 3)
	out.append_array(_pb_varint(p_value))
	return out
