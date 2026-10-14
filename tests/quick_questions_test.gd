extends SceneTree

# Tests del helper puro quick_questions.gd (REQ-X2.3 / X4.4) y de los helpers
# puros de cifrado de bubble.gd (REQ-X4.3). Sin red ni nodos.

var _fail := 0

func _init():
	var QQ = load("res://addons/xat_xmpp/ui/quick_questions.gd")
	var Bubble = load("res://addons/xat_xmpp/ui/bubble.gd")

	# --- defaults ---
	var d = QQ.defaults()
	check(d.size() == QQ.DEFAULT_QUESTIONS.size(), "defaults: tamaño")
	check(d.size() > 0 and d[0] == QQ.DEFAULT_QUESTIONS[0], "defaults: contenido")
	d.append("mutado")
	check(QQ.DEFAULT_QUESTIONS.size() == QQ.MAX_QUESTIONS, "defaults: copia (no muta la constante)")

	# --- from_settings ---
	check(QQ.from_settings({}) == QQ.defaults(), "sin clave: defaults")
	check(QQ.from_settings(null) == QQ.defaults(), "settings nulo: defaults")
	check(QQ.from_settings({"quick_questions": ["uno", "dos"]}) == ["uno", "dos"], "lista custom")

	# --- sanitize ---
	check(QQ.sanitize(["uno", "   ", "uno", "dos"]) == ["uno", "dos"], "sanitiza: vacíos y repetidos")
	check(QQ.sanitize(["  hola  "]) == ["hola"], "sanitiza: recorta espacios")
	check(QQ.sanitize("no es array").empty(), "sanitiza: entrada inválida -> vacío")
	var many := []
	for i in range(10):
		many.append("q%d" % i)
	check(QQ.from_settings({"quick_questions": many}).size() == QQ.MAX_QUESTIONS, "tope MAX_QUESTIONS")

	# --- chips (/status al final, una sola vez) ---
	var c = QQ.chips({"quick_questions": ["uno", QQ.STATUS_VALUE]})
	check(c == ["uno", QQ.STATUS_VALUE], "chips: no duplica /status")
	var c2 = QQ.chips({})
	check(c2.size() == QQ.MAX_QUESTIONS + 1 and c2[c2.size() - 1] == QQ.STATUS_VALUE, "chips: /status al final")

	# --- archivo: inexistente -> defaults; round-trip de escritura/lectura ---
	check(QQ.load_questions("user://__nope_qq__.json") == QQ.defaults(), "sin archivo: defaults")
	var path = "user://__qq_test__.json"
	var f = File.new()
	check(f.open(path, File.WRITE) == OK, "escribe settings")
	f.store_string(JSON.print({"quick_questions": ["a", "b"]}))
	f.close()
	check(QQ.load_questions(path) == ["a", "b"], "lee del json")
	var d2 = Directory.new()
	d2.remove(path)

	# --- chip de cifrado (helper puro en bubble.gd) ---
	check(Bubble.encryption_chip_text(false) == "Chat sin OMEMO · texto plano", "chip sin OMEMO")
	check(Bubble.encryption_chip_text(true) == "", "chip con OMEMO: vacío (honesto)")
	check(Bubble.is_omemo_notice("🔒 Mensaje cifrado con OMEMO: xat todavía no puede leerlo."), "detecta placeholder OMEMO")
	check(not Bubble.is_omemo_notice("hola"), "sin falsos positivos")
	check(Bubble.notice_text("🔒 Mensaje cifrado con OMEMO: xat todavía no puede leerlo.") == "Mensaje cifrado con OMEMO · no se pudo leer", "notice_text limpia el glifo")
	check(Bubble.notice_text("texto normal") == "texto normal", "notice_text deja el resto igual")

	# --- línea de estado de la cabecera (helper puro en chat_panel.gd) ---
	var CP = load("res://addons/xat_xmpp/ui/chat_panel.gd")
	check(CP.status_line({"activity": "processing", "context": {"used": 42, "max": 100}, "model": "gpt"}, true) == "trabajando · contexto 42% · gpt", "status: línea completa")
	check(CP.status_line({}) == "", "status: sin datos -> vacío")
	check(CP.status_line({}, false) == "desconectado", "status: desconectado")
	check(CP.status_line({"activity": "pending", "context": {"max": 0}}) == "esperando aprobación", "status: sin contexto si max=0")

	# --- integración en el chat: chip de sistema + fila de preguntas ---
	var p = CP.new()
	get_root().add_child(p)
	p.set_peer("a@h")
	p.add_message({"from": "a@h", "body": "🔒 Mensaje cifrado con OMEMO: xat todavía no puede leerlo.", "direction": "in", "timestamp": "2026-01-01T10:00:00Z", "id": "e1"})
	var bub = p._bub(0)
	check(bub != null and bub._system, "chat: placeholder OMEMO -> chip de sistema")
	var qq = p.quick_questions()
	check(qq.size() == QQ.MAX_QUESTIONS + 1 and qq[qq.size() - 1] == QQ.STATUS_VALUE, "chat: fila de preguntas + /status")
	p.set_room("sala@conference.h", "yo", [])
	check(p.quick_questions().empty(), "chat: sin preguntas en sala")
	p.free()

	if _fail == 0:
		print("QUICK_QUESTIONS_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
