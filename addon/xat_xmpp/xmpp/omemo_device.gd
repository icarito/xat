extends Reference

# Material de llaves OMEMO del dispositivo (XEP-0384 §5): una identidad Ed25519
# estable, un signed prekey X25519 firmado por la identidad, y un pool de
# prekeys X25519. Genera, persiste y rota. La cripto la hace el módulo nativo
# (`XatOmemo`); acá sólo se orquesta y se persiste.

const _K_IDENTITY := "omemo.identity_seed"
const _K_DEVICE := "omemo.device_id"
const _K_SPK := "omemo.spk"
const _K_SPK_OLD := "omemo.spk_old"
const _K_NEXT_PK := "omemo.next_prekey_id"
const _K_PK := "omemo.prekey."

const TARGET_PREKEYS := 100
const REFILL_BELOW := 99

var _store
var _omemo
var _identity_seed := PoolByteArray()
var _device_id := -1
var _spk := {}
var _spk_old := {}
var _prekeys := {}
var _next_pk_id := 1

func _init(p_store, p_omemo = null) -> void:
	_store = p_store
	_omemo = p_omemo if p_omemo != null else (ClassDB.instance("XatOmemo") if ClassDB.class_exists("XatOmemo") else null)

func available() -> bool:
	return _store != null and _store.available() and _omemo != null

# Carga el material existente o lo crea. Idempotente.
func ensure_created() -> bool:
	if not available():
		return false
	_identity_seed = _store.get_bytes(_K_IDENTITY)
	if _identity_seed.size() != 32:
		_identity_seed = _omemo.random_bytes(32)
		_store.set_bytes(_K_IDENTITY, _identity_seed)
	if _store.has(_K_DEVICE):
		_device_id = int(_store.get_text(_K_DEVICE))
	if _device_id < 0:
		_device_id = _random_id()
		_store.set_text(_K_DEVICE, str(_device_id))
	_next_pk_id = int(_store.get_text(_K_NEXT_PK)) if _store.has(_K_NEXT_PK) else 1
	if _next_pk_id < 1:
		_next_pk_id = 1
	_load_prekeys()
	_spk = _store.get_json(_K_SPK, {})
	if _spk.empty():
		rotate_signed_prekey()
	else:
		_spk_old = _store.get_json(_K_SPK_OLD, {})
	if _prekeys.size() < REFILL_BELOW:
		generate_prekeys(TARGET_PREKEYS - _prekeys.size())
	return true

func identity_seed() -> PoolByteArray:
	return _identity_seed

func identity_key() -> PoolByteArray:
	return _omemo.ed25519_public_key(_identity_seed)

func device_id() -> int:
	return _device_id

func signed_pre_key_id() -> int:
	return int(_spk.get("id", -1))

func signed_pre_key() -> PoolByteArray:
	if _spk.empty():
		return PoolByteArray()
	return _omemo.x25519_public_key(Marshalls.base64_to_raw(str(_spk["priv"])))

func signed_pre_key_sig() -> PoolByteArray:
	return PoolByteArray() if _spk.empty() else Marshalls.base64_to_raw(str(_spk["sig"]))

func old_signed_pre_key_id() -> int:
	return -1 if _spk_old.empty() else int(_spk_old.get("id", -1))

func signed_pre_key_priv() -> PoolByteArray:
	return PoolByteArray() if _spk.empty() else Marshalls.base64_to_raw(str(_spk["priv"]))

func old_signed_pre_key_priv() -> PoolByteArray:
	return PoolByteArray() if _spk_old.empty() else Marshalls.base64_to_raw(str(_spk_old["priv"]))

# Rota el signed prekey: genera uno nuevo firmado por la identidad y conserva el
# anterior (por si llega un mensaje que lo use).
func rotate_signed_prekey() -> void:
	if not available():
		return
	if not _spk.empty():
		_spk_old = _spk
		_store.set_json(_K_SPK_OLD, _spk_old)
	var kp = _omemo.x25519_keypair()
	var pub: PoolByteArray = kp["public"]
	var sig = _omemo.ed25519_sign(_identity_seed, pub)
	_spk = {
		"id": _random_id(),
		"priv": Marshalls.raw_to_base64(kp["secret"]),
		"sig": Marshalls.raw_to_base64(sig),
		"ts": Time.get_datetime_string_from_system(true),
	}
	_store.set_json(_K_SPK, _spk)

# Genera `p_n` prekeys nuevas con ids crecientes estables.
func generate_prekeys(p_n: int) -> int:
	if not available():
		return 0
	var made := 0
	for _i in range(p_n):
		var kp = _omemo.x25519_keypair()
		var id := _next_pk_id
		_next_pk_id += 1
		_prekeys[id] = kp["secret"]
		_store.set_bytes(_K_PK + str(id), kp["secret"])
		made += 1
	_store.set_text(_K_NEXT_PK, str(_next_pk_id))
	return made

func prekey_count() -> int:
	return _prekeys.size()

func prekey_ids() -> Array:
	return _prekeys.keys()

func prekey_priv(p_id: int) -> PoolByteArray:
	return _prekeys.get(p_id, PoolByteArray())

func prekey_pub(p_id: int) -> PoolByteArray:
	var priv = _prekeys.get(p_id, PoolByteArray())
	return PoolByteArray() if priv.empty() else _omemo.x25519_public_key(priv)

# Busca el id de prekey cuya pública coincide (para resolver un KeyExchange).
func prekey_id_for_pub(p_pub: PoolByteArray) -> int:
	for id in _prekeys.keys():
		if _omemo.x25519_public_key(_prekeys[id]) == p_pub:
			return id
	return -1

# Consume (borra) una prekey tras usarla en un X3DH pasivo.
func consume_prekey(p_id: int) -> void:
	if _prekeys.has(p_id):
		_prekeys.erase(p_id)
		_store.erase(_K_PK + str(p_id))

# Bundle para publicar por PEP: {ik, spk, spk_id, spk_sig, prekeys:[{id, pub}]}.
func bundle() -> Dictionary:
	var prekeys := []
	for id in _prekeys.keys():
		prekeys.append({"id": id, "pub": _omemo.x25519_public_key(_prekeys[id])})
	return {
		"ik": identity_key(),
		"spk": signed_pre_key(),
		"spk_id": signed_pre_key_id(),
		"spk_sig": signed_pre_key_sig(),
		"prekeys": prekeys,
	}

# Lista de dispositivos propios (para el nodo de devices); por ahora uno.
func device_list() -> Array:
	return [{"id": _device_id, "label": ""}]

func _load_prekeys() -> void:
	_prekeys = {}
	for key in _store.keys_with_prefix(_K_PK):
		var id := int(key.substr(_K_PK.length()))
		var priv = _store.get_bytes(key)
		if priv.size() == 32:
			_prekeys[id] = priv

func _random_id() -> int:
	var b = _omemo.random_bytes(4)
	var v := 0
	for i in range(4):
		v = (v << 8) | int(b[i])
	return (v & 0x7fffffff) | 1
