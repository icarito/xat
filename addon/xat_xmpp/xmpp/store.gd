extends Reference

# Historial XMPP en SQLite (por bare JID), sobre el binding nativo
# `SQLiteBinding`. Dedupe por `(bare_jid, mam_id)` con `INSERT OR IGNORE`,
# plegado de correcciones 0308 por `request_id`, y expiración de acciones.
#
# Política de hilos: se usa desde el hilo principal; NUNCA desde el hilo de
# libstrophe (por eso el módulo nativo expone SQLite aparte).

const _SCHEMA := [
	"CREATE TABLE IF NOT EXISTS messages (" \
	+ "id INTEGER PRIMARY KEY AUTOINCREMENT," \
	+ "bare_jid TEXT NOT NULL," \
	+ "body TEXT NOT NULL," \
	+ "direction TEXT NOT NULL," \
	+ "timestamp TEXT NOT NULL," \
	+ "mam_id TEXT," \
	+ "quick_responses TEXT," \
	+ "commands TEXT," \
	+ "request_id TEXT," \
	+ "attachment TEXT," \
	+ "was_encrypted INTEGER NOT NULL DEFAULT 0," \
	+ "UNIQUE(bare_jid, mam_id))",
	"CREATE INDEX IF NOT EXISTS idx_messages_jid_ts ON messages(bare_jid, timestamp)",
	"CREATE INDEX IF NOT EXISTS idx_messages_jid_request ON messages(bare_jid, request_id)",
	"CREATE TABLE IF NOT EXISTS rooms (" \
	+ "bare_jid TEXT PRIMARY KEY," \
	+ "nick TEXT NOT NULL," \
	+ "autojoin INTEGER NOT NULL DEFAULT 1)",
]

var _db = null
var _available := false

func _init() -> void:
	if ClassDB.class_exists("SQLiteBinding"):
		_db = ClassDB.instance("SQLiteBinding")
		_available = _db != null

func available() -> bool:
	return _available

func open(p_path: String) -> int:
	if not _available:
		return -1
	var rc = _db.open(p_path)
	if rc != 0:
		return rc
	for stmt in _SCHEMA:
		var e = _db.exec(stmt)
		if e != 0:
			return e
	_migrate()
	# Limpieza: MAM archiva chat-states, recibos y marcadores sin cuerpo. Versiones
	# anteriores los guardaron y se veían como burbujas vacías. Sólo se borran si
	# además no traen acciones (nunca hay filas legítimas sin cuerpo y sin acciones).
	_db.exec("DELETE FROM messages WHERE trim(body) = '' AND (commands IS NULL OR commands IN ('', '[]')) AND (quick_responses IS NULL OR quick_responses IN ('', '[]'))")
	# Dedupe de entregas repetidas (vivo+MAM, o espejo del agente): para cada
	# (peer, dirección, remitente, cuerpo, minuto) se conserva la fila más
	# antigua. `sender` entra en la clave para no plegar a dos ocupantes de una
	# sala que digan lo mismo en el mismo minuto (en 1:1 es NULL para todos).
	_db.exec("DELETE FROM messages WHERE trim(body) <> '' AND id NOT IN (SELECT MIN(id) FROM messages WHERE trim(body) <> '' GROUP BY bare_jid, direction, sender, trim(body), substr(timestamp, 1, 16))")
	return 0

func close() -> void:
	if _db != null:
		_db.close()

# Migración de bases creadas por versiones anteriores: agrega columnas nuevas
# que el CREATE TABLE IF NOT EXISTS no puede añadir a una tabla existente.
func _migrate() -> void:
	var cols := _column_names()
	if not cols.has("attachment"):
		_db.exec("ALTER TABLE messages ADD COLUMN attachment TEXT")
	if not cols.has("sender"):
		_db.exec("ALTER TABLE messages ADD COLUMN sender TEXT")

func _column_names() -> Array:
	var out := []
	var rows = _db.query("PRAGMA table_info(messages)", [])
	for r in rows:
		out.append(str(r.get("name", "")))
	return out

# Inserta (o actualiza metadatos de) un registro. Devuelve false si ya existía
# una fila con el mismo (bare_jid, mam_id) (dedupe de MAM).
func record_message(p_rec: Dictionary) -> bool:
	if not _available:
		return false
	var q = _db.prepare("INSERT OR IGNORE INTO messages(bare_jid,body,direction,timestamp,mam_id,quick_responses,commands,request_id,attachment,sender) VALUES(?,?,?,?,?,?,?,?,?,?)")
	if q == null:
		return false
	q.bind_text(1, str(p_rec.get("bare_jid", "")))
	q.bind_text(2, str(p_rec.get("body", "")))
	q.bind_text(3, str(p_rec.get("direction", "in")))
	q.bind_text(4, str(p_rec.get("ts", p_rec.get("timestamp", ""))))
	var mam_id = str(p_rec.get("mam_id", ""))
	if mam_id == "":
		q.bind_null(5)
	else:
		q.bind_text(5, mam_id)
	q.bind_text(6, _json(p_rec.get("quick", [])))
	q.bind_text(7, _json(p_rec.get("commands", [])))
	var request_id = str(p_rec.get("request_id", ""))
	if request_id == "":
		q.bind_null(8)
	else:
		q.bind_text(8, request_id)
	var attach = p_rec.get("attach", null)
	if attach == null or (attach is Dictionary and (attach as Dictionary).empty()):
		q.bind_null(9)
	else:
		q.bind_text(9, _json(attach))
	var sender = str(p_rec.get("sender", ""))
	if sender == "":
		q.bind_null(10)
	else:
		q.bind_text(10, sender)
	q.step()
	q.finalize()
	var inserted = _db.changes() > 0
	if not inserted and (request_id != "" or mam_id != ""):
		# Fila preexistente: completar request_id y acciones si faltaban.
		_update_metadata(p_rec, request_id)
	return inserted

func _update_metadata(p_rec: Dictionary, p_request_id: String) -> void:
	var sets := []
	var values := []
	if p_request_id != "":
		sets.append("request_id = COALESCE(request_id, ?)")
		values.append(p_request_id)
	if p_rec.has("quick") and not (p_rec["quick"] as Array).empty():
		sets.append("quick_responses = COALESCE(quick_responses, ?)")
		values.append(_json(p_rec["quick"]))
	if p_rec.has("commands") and not (p_rec["commands"] as Array).empty():
		sets.append("commands = COALESCE(commands, ?)")
		values.append(_json(p_rec["commands"]))
	if p_rec.has("attach") and p_rec["attach"] is Dictionary and not (p_rec["attach"] as Dictionary).empty():
		sets.append("attachment = COALESCE(attachment, ?)")
		values.append(_json(p_rec["attach"]))
	if p_rec.has("sender") and str(p_rec["sender"]) != "":
		sets.append("sender = COALESCE(sender, ?)")
		values.append(str(p_rec["sender"]))
	if sets.empty():
		return
	var q = _db.prepare("UPDATE messages SET " + ", ".join(sets) + " WHERE bare_jid = ? AND mam_id IS ?")
	if q == null:
		return
	for i in range(values.size()):
		q.bind_text(i + 1, str(values[i]))
	q.bind_text(values.size() + 1, str(p_rec.get("bare_jid", "")))
	var mam_id = str(p_rec.get("mam_id", ""))
	if mam_id == "":
		q.bind_null(values.size() + 2)
	else:
		q.bind_text(values.size() + 2, mam_id)
	q.step()
	q.finalize()

# Plegado 0308: reescribe el cuerpo de la fila ancla y limpia acciones.
func update_by_request_id(p_bare_jid: String, p_request_id: String, p_body: String) -> bool:
	if not _available or p_request_id == "":
		return false
	var q = _db.prepare("UPDATE messages SET body = ?, quick_responses = NULL, commands = NULL WHERE bare_jid = ? AND request_id = ?")
	if q == null:
		return false
	q.bind_text(1, p_body)
	q.bind_text(2, p_bare_jid)
	q.bind_text(3, p_request_id)
	q.step()
	q.finalize()
	return _db.changes() > 0

func latest_mam_id(p_bare_jid: String) -> String:
	var rows = _db.query("SELECT mam_id FROM messages WHERE bare_jid = ? AND mam_id IS NOT NULL ORDER BY timestamp DESC, id DESC LIMIT 1", [p_bare_jid])
	if rows.empty() or rows[0]["mam_id"] == null:
		return ""
	return str(rows[0]["mam_id"])

func latest_timestamp(p_bare_jid: String) -> String:
	var rows = _db.query("SELECT timestamp FROM messages WHERE bare_jid = ? AND trim(body) <> '' ORDER BY timestamp DESC, id DESC LIMIT 1", [p_bare_jid])
	if rows.empty() or rows[0]["timestamp"] == null:
		return ""
	return str(rows[0]["timestamp"])

# Devuelve las `p_limit` filas más nuevas, re-ordenadas ascendente para render.
func get_recent(p_bare_jid: String, p_limit: int = 50) -> Array:
	var rows = _db.query("SELECT * FROM (SELECT * FROM messages WHERE bare_jid = ? AND trim(body) <> '' ORDER BY timestamp DESC, id DESC LIMIT ?) ORDER BY timestamp ASC, id ASC", [p_bare_jid, p_limit])
	return _decode_rows(rows)

func find_by_request_id(p_bare_jid: String, p_request_id: String):
	if p_request_id == "":
		return null
	var rows = _db.query("SELECT * FROM messages WHERE bare_jid = ? AND request_id = ? LIMIT 1", [p_bare_jid, p_request_id])
	if rows.empty():
		return null
	return _decode_row(rows[0])

# Adjunto (dict) de una fila, o {} si no tiene.
func get_attachment(p_bare_jid: String, p_request_id: String) -> Dictionary:
	var row = find_by_request_id(p_bare_jid, p_request_id)
	if row == null:
		return {}
	var a = row.get("attach", {})
	return a if a is Dictionary else {}

# Reemplaza el dict de adjunto (estado de subida/descarga, ruta local, etc.).
func set_attachment(p_bare_jid: String, p_request_id: String, p_attach: Dictionary) -> bool:
	if not _available or p_request_id == "":
		return false
	var q = _db.prepare("UPDATE messages SET attachment = ? WHERE bare_jid = ? AND request_id = ?")
	if q == null:
		return false
	q.bind_text(1, _json(p_attach))
	q.bind_text(2, p_bare_jid)
	q.bind_text(3, p_request_id)
	q.step()
	q.finalize()
	return _db.changes() > 0

# Adjunta un mam_id a una fila viva (sin mam_id) que matchee request_id o,
# si no, por cuerpo+dirección dentro de una ventana de 120 s.
func attach_mam(p_bare_jid: String, p_mam_id: String, p_body: String, p_direction: String, p_ts: String) -> bool:
	var q = _db.prepare("UPDATE messages SET mam_id = ? WHERE id = (SELECT id FROM messages WHERE bare_jid = ? AND mam_id IS NULL AND body = ? AND direction = ? AND ABS(strftime('%s', timestamp) - strftime('%s', ?)) <= 120 ORDER BY ABS(strftime('%s', timestamp) - strftime('%s', ?)) ASC LIMIT 1)")
	if q == null:
		return false
	q.bind_text(1, p_mam_id)
	q.bind_text(2, p_bare_jid)
	q.bind_text(3, p_body)
	q.bind_text(4, p_direction)
	q.bind_text(5, p_ts)
	q.bind_text(6, p_ts)
	q.step()
	q.finalize()
	return _db.changes() > 0

# ¿Ya hay una fila con este mam_id? (dedupe de catch-up MAM)
func has_mam(p_bare_jid: String, p_mam_id: String) -> bool:
	if p_mam_id == "":
		return false
	var rows = _db.query("SELECT 1 FROM messages WHERE bare_jid = ? AND mam_id = ? LIMIT 1", [p_bare_jid, p_mam_id])
	return not rows.empty()

# Adjunta un mam_id a la fila viva (sin mam_id) con ese request_id (id de stanza).
# Es la vía fiable para no duplicar un mensaje que ya llegó en vivo y luego por MAM.
func attach_mam_by_request(p_bare_jid: String, p_request_id: String, p_mam_id: String) -> bool:
	if p_request_id == "" or p_mam_id == "":
		return false
	var q = _db.prepare("UPDATE messages SET mam_id = ? WHERE id = (SELECT id FROM messages WHERE bare_jid = ? AND request_id = ? AND mam_id IS NULL LIMIT 1)")
	if q == null:
		return false
	q.bind_text(1, p_mam_id)
	q.bind_text(2, p_bare_jid)
	q.bind_text(3, p_request_id)
	q.step()
	q.finalize()
	return _db.changes() > 0

# ¿Ya hay una fila con ese request_id? (dedupe de entregas repetidas del agente)
func has_request_id(p_bare_jid: String, p_request_id: String) -> bool:
	if p_request_id == "":
		return false
	var rows = _db.query("SELECT 1 FROM messages WHERE bare_jid = ? AND request_id = ? LIMIT 1", [p_bare_jid, p_request_id])
	return not rows.empty()

func _decode_rows(rows: Array) -> Array:
	var out := []
	for r in rows:
		out.append(_decode_row(r))
	return out

func _decode_row(r: Dictionary) -> Dictionary:
	return {
		"id": r.get("id", 0),
		"bare_jid": r.get("bare_jid", ""),
		"body": r.get("body", ""),
		"direction": r.get("direction", "in"),
		"ts": r.get("timestamp", ""),
		"mam_id": r.get("mam_id", ""),
		"quick": _unjson(r.get("quick_responses", "")),
		"commands": _unjson(r.get("commands", "")),
		"request_id": r.get("request_id", ""),
		"attach": _unjson_obj(r.get("attachment", "")),
		"sender": r.get("sender", ""),
	}

# --- Salas (XEP-0045) ---

func list_rooms() -> Array:
	var rows = _db.query("SELECT bare_jid, nick, autojoin FROM rooms ORDER BY bare_jid", [])
	var out := []
	for r in rows:
		out.append({
			"bare_jid": str(r.get("bare_jid", "")),
			"nick": str(r.get("nick", "")),
			"autojoin": int(r.get("autojoin", 1)) != 0,
		})
	return out

func save_room(p_bare_jid: String, p_nick: String, p_autojoin: bool = true) -> bool:
	if not _available or p_bare_jid == "":
		return false
	var q = _db.prepare("INSERT OR REPLACE INTO rooms(bare_jid, nick, autojoin) VALUES(?,?,?)")
	if q == null:
		return false
	q.bind_text(1, p_bare_jid)
	q.bind_text(2, p_nick)
	q.bind_int(3, 1 if p_autojoin else 0)
	q.step()
	q.finalize()
	return _db.changes() > 0

func remove_room(p_bare_jid: String) -> bool:
	if not _available:
		return false
	var q = _db.prepare("DELETE FROM rooms WHERE bare_jid = ?")
	if q == null:
		return false
	q.bind_text(1, p_bare_jid)
	q.step()
	q.finalize()
	return _db.changes() > 0

func _json(p_value) -> String:
	return to_json(p_value)

func _unjson(p_text) -> Array:
	if p_text == null or str(p_text) == "":
		return []
	var parsed = parse_json(str(p_text))
	return parsed if parsed is Array else []

func _unjson_obj(p_text) -> Dictionary:
	if p_text == null or str(p_text) == "":
		return {}
	var parsed = parse_json(str(p_text))
	return parsed if parsed is Dictionary else {}
