extends SceneTree

# Historial SQLite (requiere el módulo nativo): dedupe por (bare_jid,mam_id),
# plegado 0308 por request_id, watermark y orden de get_recent.

var _fail := 0

func _init():
	if not ClassDB.class_exists("SQLiteBinding"):
		print("FAIL módulo nativo ausente")
		OS.exit_code = 1
		quit()
		return

	var Store = load("res://addons/xat_xmpp/xmpp/store.gd")
	var s = Store.new()
	check(s.available(), "store disponible")
	check(s.open(":memory:") == 0, "open :memory:")

	# Inserto una fila viva 'in' sin mam_id.
	var inserted = s.record_message({"bare_jid": "a@h", "body": "hola", "direction": "in", "ts": "2026-01-01T00:00:00Z", "request_id": "orig1"})
	check(inserted, "insert inicial")
	# Mismo (bare_jid,mam_id) => dedupe.
	check(s.record_message({"bare_jid": "a@h", "body": "m1-body", "direction": "in", "ts": "2026-01-01T00:00:01Z", "mam_id": "m1"}), "insert mam m1")
	check(not s.record_message({"bare_jid": "a@h", "body": "dup2", "direction": "in", "ts": "2026-01-01T00:00:02Z", "mam_id": "m1"}), "m1 duplicado se ignora")

	# Plegado 0308 por request_id.
	check(s.update_by_request_id("a@h", "orig1", "hola editado"), "update_by_request_id")
	var row = s.find_by_request_id("a@h", "orig1")
	check(row != null and row["body"] == "hola editado", "cuerpo actualizado")

	# Agrego un saliente y otro mam_id; watermark y orden.
	s.record_message({"bare_jid": "a@h", "body": "respuesta", "direction": "out", "ts": "2026-01-01T00:00:03Z"})
	s.record_message({"bare_jid": "a@h", "body": "tarde", "direction": "in", "ts": "2026-01-01T00:00:09Z", "mam_id": "m2"})
	check(s.latest_mam_id("a@h") == "m2", "latest_mam_id")
	check(s.latest_timestamp("a@h") == "2026-01-01T00:00:09Z", "latest_timestamp")

	var recent = s.get_recent("a@h", 10)
	check(recent.size() == 4, "get_recent 4 filas")
	check(recent[0]["ts"] <= recent[3]["ts"], "get_recent ascendente")
	check(recent[3]["body"] == "tarde", "última fila al final")

	# Búsqueda por cuerpo (adjuntar mam a fila viva).
	s.record_message({"bare_jid": "b@h", "body": "suelta", "direction": "in", "ts": "2026-02-02T00:00:00Z"})
	check(s.attach_mam("b@h", "m9", "suelta", "in", "2026-02-02T00:00:00Z"), "attach_mam por cuerpo")
	check(s.latest_mam_id("b@h") == "m9", "mam adjuntado")

	# Adjunta por request_id (id de stanza): evita duplicar vivo+MAM.
	s.record_message({"bare_jid": "d@h", "body": "vivo", "direction": "out", "ts": "2026-04-04T00:00:00Z", "request_id": "stanza-1"})
	check(s.attach_mam_by_request("d@h", "stanza-1", "mm1"), "attach_mam_by_request")
	check(s.has_mam("d@h", "mm1"), "has_mam true")
	check(s.get_recent("d@h", 10).size() == 1, "no duplica: sigue 1 fila")
	check(not s.attach_mam_by_request("d@h", "stanza-1", "mm2"), "attach_mam_by_request no re-adjunta")
	check(not s.has_mam("d@h", "mm2"), "has_mam false")

	# Cuerpo vacío (chat-state/recibo archivado en MAM): no se lee como mensaje.
	s.record_message({"bare_jid": "a@h", "body": "", "direction": "out", "ts": "2026-01-01T00:00:20Z", "mam_id": "m3"})
	check(s.get_recent("a@h", 10).size() == 4, "get_recent omite cuerpo vacío")
	check(s.latest_timestamp("a@h") == "2026-01-01T00:00:09Z", "latest_timestamp omite cuerpo vacío")

	# has_request_id: dedupe de entregas repetidas del agente.
	s.record_message({"bare_jid": "e@h", "body": "repetido", "direction": "in", "ts": "2026-05-05T00:00:00Z", "request_id": "rid-1"})
	check(s.has_request_id("e@h", "rid-1"), "has_request_id true")
	check(not s.has_request_id("e@h", "rid-2"), "has_request_id false")

	# Adjuntos: metadata JSON por fila + reemplazo de estado de subida.
	s.record_message({"bare_jid": "h@h", "body": "https://up.x/f.jpg", "direction": "out", "ts": "2026-07-07T00:00:00Z", "request_id": "att-1", "attach": {"url": "https://up.x/f.jpg", "mime": "image/jpeg", "kind": "image", "state": "uploading"}})
	var hr = s.find_by_request_id("h@h", "att-1")
	check(hr != null and hr["attach"]["kind"] == "image" and hr["attach"]["state"] == "uploading", "attachment round-trip")
	check(s.get_attachment("h@h", "att-1")["mime"] == "image/jpeg", "get_attachment")
	check(s.set_attachment("h@h", "att-1", {"url": "https://up.x/f.jpg", "kind": "image", "state": "sent", "local": "/tmp/f.jpg"}), "set_attachment")
	check(s.get_attachment("h@h", "att-1")["state"] == "sent", "set_attachment persiste")
	check(s.get_recent("h@h", 10).back()["attach"]["state"] == "sent", "get_recent decodifica attach")
	check(s.get_attachment("h@h", "no-existe").empty(), "get_attachment ausente")

	# open() limpia filas sin cuerpo heredadas.
	var tmp = "user://store_test_tmp.db"
	var s2 = Store.new()
	check(s2.open(tmp) == 0, "open archivo temporal")
	s2.record_message({"bare_jid": "c@h", "body": "", "direction": "in", "ts": "2026-03-03T00:00:00Z", "mam_id": "z1"})
	s2.record_message({"bare_jid": "c@h", "body": "real", "direction": "in", "ts": "2026-03-03T00:00:01Z", "mam_id": "z2"})
	# Duplicado por mismo cuerpo+minuto: open() debe colapsarlo.
	s2.record_message({"bare_jid": "g@h", "body": "hola", "direction": "in", "ts": "2026-06-06T00:00:01Z", "mam_id": "a1"})
	s2.record_message({"bare_jid": "g@h", "body": "hola", "direction": "in", "ts": "2026-06-06T00:00:20Z", "mam_id": "a2"})
	s2.close()
	var s3 = Store.new()
	check(s3.open(tmp) == 0, "reopen archivo temporal")
	check(s3.get_recent("c@h", 10).size() == 1, "open limpia filas sin cuerpo")
	check(s3.get_recent("g@h", 10).size() == 1, "open colapsa duplicados del mismo minuto")
	s3.close()
	var d = Directory.new()
	d.remove(tmp)

	s.close()
	if _fail == 0:
		print("STORE_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
