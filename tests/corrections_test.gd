extends SceneTree

# Plegado de XEP-0308: cadenas de correcciones -> una fila.

var _fail := 0

func _init():
	var Correction = load("res://addons/xat_xmpp/xmpp/corrections.gd")

	# Cadena: ancla + dos ediciones que referencian el id original.
	var page = [
		{"bare_jid": "a@h", "body": "v1", "direction": "in", "ts": "T1", "mam_id": "m1", "request_id": "orig1"},
		{"bare_jid": "a@h", "body": "v2", "direction": "in", "ts": "T2", "mam_id": "m2", "replace_id": "orig1"},
		{"bare_jid": "a@h", "body": "v3", "direction": "in", "ts": "T3", "mam_id": "m3", "replace_id": "orig1"},
	]
	var out = Correction.fold_page(page)
	check(out.size() == 1, "cadena colapsa a una fila")
	check(out[0]["body"] == "v3", "queda la última edición")
	check(out[0]["ts"] == "T1" and out[0]["mam_id"] == "m1", "conserva ts/mam del ancla")
	check(out[0]["direction"] == "in", "conserva dirección del ancla")

	# Corrección cuyo objetivo es desconocido: se ancla bajo el id original y
	# las ediciones siguientes colapsan.
	var page2 = [
		{"bare_jid": "a@h", "body": "edit-only", "direction": "in", "ts": "T1", "mam_id": "", "replace_id": "ghost"},
		{"bare_jid": "a@h", "body": "edit-2", "direction": "in", "ts": "T2", "mam_id": "", "replace_id": "ghost"},
	]
	var out2 = Correction.fold_page(page2)
	check(out2.size() == 1, "objetivo desconocido se ancla")
	check(out2[0]["body"] == "edit-2", "edición sobre el ancla desconocida")

	# store con fila persistida: la corrección se descarta (no duplica).
	var fake_store = FakeStore.new(["persisted1"])
	var page3 = [
		{"bare_jid": "a@h", "body": "nueva", "direction": "in", "ts": "T9", "mam_id": "m9", "replace_id": "persisted1"},
	]
	var out3 = Correction.fold_page(page3, fake_store)
	check(out3.empty(), "corrección a fila persistida se descarta")
	check(fake_store.updates.size() == 1 and fake_store.updates[0] == ["a@h", "persisted1", "nueva"], "store recibió el update")

	# Mensajes salientes no se pliegan como correcciones de entrada.
	var page4 = [
		{"bare_jid": "a@h", "body": "v1", "direction": "in", "ts": "T1", "request_id": "orig1"},
		{"bare_jid": "a@h", "body": "out", "direction": "out", "ts": "T2", "replace_id": "orig1"},
	]
	var out4 = Correction.fold_page(page4)
	check(out4.size() == 2, "corrección 'out' no colapsa")

	if _fail == 0:
		print("CORRECTIONS_CHECK_OK")
	quit()

class FakeStore:
	var known := {}
	var updates := []
	func _init(p_known: Array) -> void:
		for k in p_known:
			known[k] = true
	func update_by_request_id(bare_jid: String, request_id: String, body: String) -> bool:
		if known.has(request_id):
			updates.append([bare_jid, request_id, body])
			return true
		return false

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
