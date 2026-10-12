extends Reference

# Motor OMEMO 2 (XEP-0384) de xat. Arma y lee `<encrypted>`, administra las
# sesiones del Double Ratchet (persistidas en `omemo_store`) y la confianza.
# La cripto la hace el módulo nativo `XatOmemo`; el formato del cable, `omemo.gd`.

const Omemo = preload("res://addons/xat_xmpp/xmpp/omemo.gd")
const Stanza = preload("res://addons/xat_xmpp/xmpp/stanza.gd")
const NS := "urn:xmpp:omemo:2"

const _S_SESSION := "omemo.session."
const _S_PEER_DEV := "omemo.peer_devices."
const _S_PEER_BUNDLE := "omemo.peer_bundle."
const _S_TRUST := "omemo.trust."

var _store
var _device
var _omemo

func _init(p_store, p_device, p_omemo = null) -> void:
	_store = p_store
	_device = p_device
	_omemo = p_omemo if p_omemo != null else ClassDB.instance("XatOmemo")

func available() -> bool:
	return _store != null and _store.available() and _device != null and _device.available() and _omemo != null

func own_device_id() -> int:
	return _device.device_id()

# --- Caché del par (device list y bundles) ---

func set_peer_devices(p_bare: String, p_ids: Array) -> void:
	_store.set_json(_S_PEER_DEV + p_bare, p_ids)

func peer_devices(p_bare: String) -> Array:
	var v = _store.get_json(_S_PEER_DEV + p_bare, [])
	return v if v is Array else []

func set_peer_bundle(p_bare: String, p_dev: int, p_bundle: Dictionary) -> void:
	_store.set_json(_S_PEER_BUNDLE + p_bare + "." + str(p_dev), _bundle_to_json(p_bundle))

func peer_bundle(p_bare: String, p_dev: int) -> Dictionary:
	var v = _store.get_json(_S_PEER_BUNDLE + p_bare + "." + str(p_dev), {})
	return _bundle_from_json(v) if v is Dictionary else {}

func has_peer_bundle(p_bare: String, p_dev: int) -> bool:
	return _store.has(_S_PEER_BUNDLE + p_bare + "." + str(p_dev))

# id -> bundle, para todos los dispositivos conocidos del par.
func peer_bundles(p_bare: String) -> Dictionary:
	var out := {}
	for id in peer_devices(p_bare):
		var b = peer_bundle(p_bare, int(id))
		if not b.empty():
			out[int(id)] = b
	return out

func trust_key(p_bare: String, p_dev: int) -> PoolByteArray:
	return _store.get_bytes(_S_TRUST + p_bare + "." + str(p_dev))

func has_session(p_bare: String, p_dev: int) -> bool:
	return _store.has(_S_SESSION + p_bare + "." + str(p_dev))

# --- Cifrado ---

# Devuelve {ok, element} con el `<encrypted>` listo para colgar de un <message>.
func encrypt(p_own_bare: String, p_bare: String, p_body: String) -> Dictionary:
	if not available():
		return {"ok": false, "error": "no_disponible"}
	var peers = peer_bundles(p_bare)
	if peers.empty():
		return {"ok": false, "error": "sin_dispositivos"}
	var plaintext = Omemo.build_sce_envelope(p_body, p_bare)
	var enc = _omemo.payload_encrypt(plaintext.to_utf8())
	if not enc.has("key"):
		return {"ok": false, "error": "payload"}
	var key48: PoolByteArray = enc["key"]
	var payload: PoolByteArray = enc["payload"]
	var keys := []
	for dev in peers.keys():
		var r = _encrypt_for(p_bare, int(dev), peers[dev], key48)
		if not r["ok"]:
			return {"ok": false, "error": r["error"]}
		keys.append(r)
	return {"ok": true, "element": _build_encrypted(p_bare, keys, payload)}

func _encrypt_for(p_bare: String, p_dev: int, p_bundle: Dictionary, p_key48: PoolByteArray) -> Dictionary:
	var sess = _load_session(p_bare, p_dev)
	if sess == null:
		var prekeys = p_bundle.get("prekeys", [])
		if prekeys.empty():
			return {"ok": false, "error": "sin_prekey"}
		var prekey = prekeys[0]
		var bundle_in = {"ik": p_bundle["ik"], "spk": p_bundle["spk"], "spk_sig": p_bundle["spk_sig"], "prekey": prekey["pub"]}
		var act = _omemo.x3dh_active(_device.identity_seed(), bundle_in, PoolByteArray())
		if act.empty():
			return {"ok": false, "error": "x3dh"}
		var dr = _omemo.dr_start_active(act["ss"], p_bundle["spk"], act["ad"], p_key48)
		if dr.empty():
			return {"ok": false, "error": "dr"}
		_save_session(p_bare, p_dev, act["ad"], dr["state"], false)
		_mark_trust(p_bare, p_dev, p_bundle["ik"])
		var kx = Omemo.encode_key_exchange(prekey["id"], p_bundle["spk_id"], act["ik"], act["ek"], dr["ciphertext"])
		return {"ok": true, "rid": p_dev, "kex": true, "bytes": kx}
	var dr2 = _omemo.dr_encrypt(sess["state"], sess["ad"], p_key48)
	if dr2.empty():
		return {"ok": false, "error": "dr"}
	_save_session(p_bare, p_dev, sess["ad"], dr2["state"], true)
	return {"ok": true, "rid": p_dev, "kex": false, "bytes": dr2["ciphertext"]}

func _build_encrypted(p_bare: String, p_keys: Array, p_payload: PoolByteArray):
	var enc = Stanza.new("encrypted")
	enc.set_attr("xmlns", NS)
	var header = Stanza.new("header")
	header.set_attr("sid", str(_device.device_id()))
	var keys = Stanza.new("keys")
	keys.set_attr("jid", p_bare)
	for k in p_keys:
		var key = Stanza.new("key")
		key.set_attr("rid", str(k["rid"]))
		if k["kex"]:
			key.set_attr("kex", "true")
		key.append_text(Marshalls.raw_to_base64(k["bytes"]))
		keys.add_child_stanza(key)
	header.add_child_stanza(keys)
	enc.add_child_stanza(header)
	var payload = Stanza.new("payload")
	payload.append_text(Marshalls.raw_to_base64(p_payload))
	enc.add_child_stanza(payload)
	return enc

# --- Descifrado ---
# Devuelve {ok, body, sender_device, trust} o {ok:false, error}.
func decrypt(p_from_bare: String, p_enc) -> Dictionary:
	if not available():
		return {"ok": false, "error": "no_disponible"}
	var parsed = Omemo.parse_encrypted(p_enc, _device.device_id())
	if parsed["our"].empty():
		return {"ok": false, "error": "no_es_para_nosotros"}
	var our = parsed["our"]
	var sender_dev = int(parsed["sid"])
	var payload = Marshalls.base64_to_raw(str(parsed["payload_b64"]))
	var key_bytes = Marshalls.base64_to_raw(str(our["key_b64"]))
	var key48: PoolByteArray
	if our["prekey"]:
		var r = _decrypt_kex(p_from_bare, sender_dev, key_bytes)
		if not r["ok"]:
			return r
		key48 = r["key48"]
	else:
		var sess = _load_session(p_from_bare, sender_dev)
		if sess == null:
			return {"ok": false, "error": "sin_sesion"}
		var dr = _omemo.dr_decrypt(sess["state"], sess["ad"], key_bytes)
		if dr.empty():
			return {"ok": false, "error": "dr"}
		key48 = dr["plaintext"]
		_save_session(p_from_bare, sender_dev, sess["ad"], dr["state"], true)

	var pt = _omemo.payload_decrypt(payload, key48)
	if pt.empty():
		return {"ok": false, "error": "payload"}
	var body = Omemo.unwrap_sce(pt.get_string_from_utf8())
	return {"ok": true, "body": body, "sender_device": sender_dev, "trust": trust_key(p_from_bare, sender_dev)}

# Descifrado para OMEMO dentro de una sala (MUC): el mensaje llega desde el JID
# de la sala y puede no incluir el JID real del ocupante, pero es un cifrado 1:1
# de su dispositivo. Resolvemos la sesión por el device id (header `sid`).
func decrypt_muc(p_enc) -> Dictionary:
	var parsed = Omemo.parse_encrypted(p_enc, _device.device_id())
	if parsed["our"].empty():
		return {"ok": false, "error": "no_es_para_nosotros"}
	var sid = int(parsed["sid"])
	var tried := []
	# 1) Device conocido: buscar el bare cuya lista de dispositivos lo incluye.
	for key in _store.keys_with_prefix(_S_PEER_DEV):
		var bare = key.substr(_S_PEER_DEV.length())
		for dev in peer_devices(bare):
			if int(dev) == sid:
				var r = decrypt(bare, p_enc)
				if r.get("ok"):
					return r
				tried.append("%s:%s" % [bare, str(r.get("error", "?"))])
	# 2) Sesión existente con ese device id.
	var suffix = "." + str(sid)
	for key in _store.keys_with_prefix(_S_SESSION):
		if not key.ends_with(suffix):
			continue
		var bare2 = key.substr(_S_SESSION.length(), key.length() - _S_SESSION.length() - suffix.length())
		var r2 = decrypt(bare2, p_enc)
		if r2.get("ok"):
			return r2
		tried.append("%s:%s" % [bare2, str(r2.get("error", "?"))])
	return {"ok": false, "error": "sin_sesion_muc (%s)" % ", ".join(tried)}

func _decrypt_kex(p_from_bare: String, p_sender_dev: int, p_key_bytes: PoolByteArray) -> Dictionary:
	var kx = Omemo.parse_key_exchange(p_key_bytes)
	if kx["ek"].empty() or kx["message"].empty():
		return {"ok": false, "error": "kex"}
	var prekey_priv = _device.prekey_priv(kx["pk_id"])
	if prekey_priv.empty():
		return {"ok": false, "error": "prekey"}
	var spk_priv = _spk_priv_for_id(kx["spk_id"])
	if spk_priv.empty():
		return {"ok": false, "error": "spk"}
	var pas = _omemo.x3dh_passive(_device.identity_seed(), spk_priv, prekey_priv, {"ik": kx["ik"], "ek": kx["ek"]})
	if pas.empty():
		return {"ok": false, "error": "x3dh"}
	var dr = _omemo.dr_start_passive(pas["ss"], spk_priv, pas["ad"], kx["message"])
	if dr.empty() or not dr.has("plaintext"):
		return {"ok": false, "error": "dr"}
	_save_session(p_from_bare, p_sender_dev, pas["ad"], dr["state"], true)
	_mark_trust(p_from_bare, p_sender_dev, kx["ik"])
	_device.consume_prekey(kx["pk_id"])
	return {"ok": true, "key48": dr["plaintext"]}

# --- Persistencia de sesiones y confianza ---

func _save_session(p_bare: String, p_dev: int, p_ad: PoolByteArray, p_state: PoolByteArray, p_confirmed: bool) -> void:
	_store.set_json(_S_SESSION + p_bare + "." + str(p_dev), {
		"ad": Marshalls.raw_to_base64(p_ad),
		"state": Marshalls.raw_to_base64(p_state),
		"confirmed": p_confirmed,
	})

func _load_session(p_bare: String, p_dev: int):
	var v = _store.get_json(_S_SESSION + p_bare + "." + str(p_dev), null)
	if not (v is Dictionary) or not v.has("ad") or not v.has("state"):
		return null
	return {
		"ad": Marshalls.base64_to_raw(str(v["ad"])),
		"state": Marshalls.base64_to_raw(str(v["state"])),
		"confirmed": bool(v.get("confirmed", false)),
	}

func _mark_trust(p_bare: String, p_dev: int, p_ik: PoolByteArray) -> void:
	_store.set_bytes(_S_TRUST + p_bare + "." + str(p_dev), p_ik)

func _spk_priv_for_id(p_id: int) -> PoolByteArray:
	if p_id == _device.signed_pre_key_id():
		return _device.signed_pre_key_priv()
	if p_id == _device.old_signed_pre_key_id():
		return _device.old_signed_pre_key_priv()
	return PoolByteArray()

func _bundle_to_json(p_b: Dictionary) -> Dictionary:
	var prekeys := []
	for p in p_b.get("prekeys", []):
		prekeys.append({"id": p.get("id", -1), "pub": Marshalls.raw_to_base64(p.get("pub", PoolByteArray()))})
	return {
		"ik": Marshalls.raw_to_base64(p_b.get("ik", PoolByteArray())),
		"spk": Marshalls.raw_to_base64(p_b.get("spk", PoolByteArray())),
		"spk_id": int(p_b.get("spk_id", -1)),
		"spk_sig": Marshalls.raw_to_base64(p_b.get("spk_sig", PoolByteArray())),
		"prekeys": prekeys,
	}

func _bundle_from_json(p_j: Dictionary) -> Dictionary:
	if p_j.empty() or not p_j.has("ik"):
		return {}
	var prekeys := []
	for p in p_j.get("prekeys", []):
		prekeys.append({"id": int(p.get("id", -1)), "pub": Marshalls.base64_to_raw(str(p.get("pub", "")))})
	return {
		"ik": Marshalls.base64_to_raw(str(p_j.get("ik", ""))),
		"spk": Marshalls.base64_to_raw(str(p_j.get("spk", ""))),
		"spk_id": int(p_j.get("spk_id", -1)),
		"spk_sig": Marshalls.base64_to_raw(str(p_j.get("spk_sig", ""))),
		"prekeys": prekeys,
	}
