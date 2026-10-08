extends SceneTree

# Verifica que el módulo nativo cargó: clases registradas y binding SQLite
# funcionando (open/exec/prepare/bind/step/query). No abre red.

var _fail := 0

func _init():
	check(ClassDB.class_exists("XmppConnection"), "clase XmppConnection")
	check(ClassDB.class_exists("SQLiteBinding"), "clase SQLiteBinding")
	check(ClassDB.class_exists("SQLiteQuery"), "clase SQLiteQuery")

	var conn = ClassDB.instance("XmppConnection")
	check(conn != null and conn is Node, "XmppConnection es Node")
	if conn != null:
		check(conn.has_method("open") and conn.has_method("send") and conn.has_method("is_open"), "API de XmppConnection")
		check(conn.has_signal("stanza_received") and conn.has_signal("connected") and conn.has_signal("disconnected"), "señales de XmppConnection")
		check(not conn.is_open(), "no conectado al crear")
		conn.free()

	var db = ClassDB.instance("SQLiteBinding")
	check(db != null, "instancia SQLiteBinding")
	if db != null:
		check(db.open(":memory:") == 0, "open :memory:")
		check(db.exec("CREATE TABLE m(id TEXT PRIMARY KEY, body TEXT, n INTEGER)") == 0, "create table")
		var ins = db.prepare("INSERT INTO m(id,body,n) VALUES(?,?,?)")
		check(ins != null, "prepare insert")
		ins.bind_text(1, "a1")
		ins.bind_text(2, "hola & chau")
		ins.bind_int(3, 7)
		check(ins.step() == 101, "step done (SQLITE_DONE=101)")
		ins.finalize()

		var rows = db.query("SELECT id, body, n FROM m WHERE n = ?", [7])
		check(rows.size() == 1, "query devuelve 1 fila")
		if rows.size() == 1:
			check(rows[0]["id"] == "a1", "columna id")
			check(rows[0]["body"] == "hola & chau", "columna body con &")
			check(rows[0]["n"] == 7, "columna n int")
		check(db.last_insert_rowid() >= 0, "last_insert_rowid")
		db.close()
		check(not db.is_open(), "cerrado")

	if _fail == 0:
		print("NATIVE_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
