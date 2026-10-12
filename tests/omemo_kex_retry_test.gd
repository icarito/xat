extends SceneTree

# XEP-0384 §5.4.2: el activo repite el kex hasta recibir respuesta. Si los
# primeros mensajes se pierden, el par abre la sesión con el que llegue
# (n > 0), y los repetidos que lleguen después siguen esa misma sesión.

var _fail := 0

func _init():
	if not ClassDB.class_exists("SQLiteBinding") or not ClassDB.class_exists("XatOmemo"):
		print("FAIL: faltan clases nativas")
		OS.exit_code = 1
		quit()
		return
	var omemo = ClassDB.instance("XatOmemo")
	var c = _engine(omemo)
	var d = _engine(omemo)
	var bare_c := "carol@h"
	var bare_d := "dave@h"
	c["eng"].set_peer_devices(bare_d, [d["dev"].device_id()])
	c["eng"].set_peer_bundle(bare_d, d["dev"].device_id(), d["dev"].bundle())
	d["eng"].set_peer_devices(bare_c, [c["dev"].device_id()])
	d["eng"].set_peer_bundle(bare_c, c["dev"].device_id(), c["dev"].bundle())

	var m1 = c["eng"].encrypt(bare_c, bare_d, "uno")
	var m2 = c["eng"].encrypt(bare_c, bare_d, "dos")
	var m3 = c["eng"].encrypt(bare_c, bare_d, "tres")
	check(_is_kex(m1) and _is_kex(m2) and _is_kex(m3), "sin respuesta, cada mensaje lleva kex")

	# Se perdieron #1 y #2: D abre la sesión con #3 (n = 2).
	var d3 = d["eng"].decrypt(bare_c, m3["element"])
	check(d3.get("ok", false) and d3.get("body", "") == "tres", "abre la sesión con un kex n > 0")
	# #1 llega tarde: mismo EK, sigue la sesión (su prekey ya se consumió).
	var d1 = d["eng"].decrypt(bare_c, m1["element"])
	check(d1.get("ok", false) and d1.get("body", "") == "uno", "kex repetido tardío usa la sesión abierta")

	# D responde: confirma la sesión en C, que deja de enviar kex.
	var r = d["eng"].encrypt(bare_d, bare_c, "recibido")
	check(not _is_kex(r), "el pasivo responde sin kex")
	var dr = c["eng"].decrypt(bare_d, r["element"])
	check(dr.get("ok", false) and dr.get("body", "") == "recibido", "C descifra la respuesta")
	var m4 = c["eng"].encrypt(bare_c, bare_d, "cuatro")
	check(not _is_kex(m4), "confirmada la sesión, sin kex")
	var d4 = d["eng"].decrypt(bare_c, m4["element"])
	check(d4.get("ok", false) and d4.get("body", "") == "cuatro", "continuación tras confirmar")
	# #2 llega muy tarde: clave saltada todavía guardada.
	var d2 = d["eng"].decrypt(bare_c, m2["element"])
	check(d2.get("ok", false) and d2.get("body", "") == "dos", "kex muy tardío con clave saltada")

	if _fail == 0:
		print("OMEMO_KEX_RETRY_CHECK_OK")
	quit()

func _engine(p_omemo) -> Dictionary:
	var Store = load("res://addons/xat_xmpp/xmpp/omemo_store.gd")
	var Device = load("res://addons/xat_xmpp/xmpp/omemo_device.gd")
	var Session = load("res://addons/xat_xmpp/xmpp/omemo_session.gd")
	var db = ClassDB.instance("SQLiteBinding")
	db.open(":memory:")
	var store = Store.new(db)
	store.ensure_schema()
	var dev = Device.new(store, p_omemo)
	dev.ensure_created()
	return {"db": db, "dev": dev, "eng": Session.new(store, dev, p_omemo)}

func _is_kex(p_enc: Dictionary) -> bool:
	if not p_enc.get("ok", false):
		return false
	var header = p_enc["element"].get_child("header")
	var keys = header.get_child("keys") if header != null else null
	var key = keys.get_child("key") if keys != null else null
	return key != null and key.get_attr("kex", "") == "true"

func check(p_ok: bool, p_label: String) -> void:
	if p_ok:
		print("ok %s" % p_label)
	else:
		_fail += 1
		print("FAIL %s" % p_label)
		OS.exit_code = 1
