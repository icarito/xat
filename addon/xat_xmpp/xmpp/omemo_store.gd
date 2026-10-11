extends Reference

# Persistencia del estado OMEMO en la misma base SQLite que el historial.
# Los bytes se guardan en base64 y los diccionarios como JSON. Es una tabla
# clave/valor: OMEMO tiene pocas entidades (identidad, spk, prekeys, sesiones,
# listas de dispositivos, confianza) y así evitamos migraciones por cada una.
#
# Se usa desde el hilo principal; nunca desde el hilo de libstrophe (ver
# sqlite_binding.h).

const _SCHEMA := "CREATE TABLE IF NOT EXISTS omemo_kv (k TEXT PRIMARY KEY, v TEXT NOT NULL)"

var _db = null

func _init(p_db = null) -> void:
	_db = p_db

func available() -> bool:
	return _db != null

func ensure_schema() -> bool:
	if _db == null:
		return false
	return _db.exec(_SCHEMA) == 0

func set_text(p_key: String, p_value: String) -> bool:
	if _db == null:
		return false
	var q = _db.prepare("INSERT OR REPLACE INTO omemo_kv(k, v) VALUES(?, ?)")
	if q == null:
		return false
	q.bind_text(1, p_key)
	q.bind_text(2, p_value)
	q.step()
	q.finalize()
	return true

func get_text(p_key: String) -> String:
	if _db == null:
		return ""
	var rows = _db.query("SELECT v FROM omemo_kv WHERE k = ?", [p_key])
	if rows.empty():
		return ""
	return str(rows[0].get("v", ""))

func has(p_key: String) -> bool:
	return get_text(p_key) != ""

func erase(p_key: String) -> void:
	if _db == null:
		return
	var q = _db.prepare("DELETE FROM omemo_kv WHERE k = ?")
	if q == null:
		return
	q.bind_text(1, p_key)
	q.step()
	q.finalize()

func set_bytes(p_key: String, p_bytes: PoolByteArray) -> bool:
	return set_text(p_key, Marshalls.raw_to_base64(p_bytes))

func get_bytes(p_key: String) -> PoolByteArray:
	var t := get_text(p_key)
	return PoolByteArray() if t == "" else Marshalls.base64_to_raw(t)

func set_json(p_key: String, p_value) -> bool:
	return set_text(p_key, to_json(p_value))

func get_json(p_key: String, p_default = null):
	var t := get_text(p_key)
	if t == "":
		return p_default
	var parsed = parse_json(t)
	return p_default if parsed == null else parsed

func keys_with_prefix(p_prefix: String) -> Array:
	if _db == null:
		return []
	var rows = _db.query("SELECT k FROM omemo_kv WHERE k LIKE ?", [p_prefix + "%"])
	var out := []
	for r in rows:
		out.append(str(r.get("k", "")))
	return out
