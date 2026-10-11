extends SceneTree

# Motor OMEMO extremo a extremo entre dos dispositivos, en memoria: X3DH (kex),
# Double Ratchet, continuación, fuera de orden y confianza.

var _fail := 0

func _init():
	if not ClassDB.class_exists("SQLiteBinding") or not ClassDB.class_exists("XatOmemo"):
		print("FAIL: faltan clases nativas")
		OS.exit_code = 1
		quit()
		return
	var Store = load("res://addons/xat_xmpp/xmpp/omemo_store.gd")
	var Device = load("res://addons/xat_xmpp/xmpp/omemo_device.gd")
	var Session = load("res://addons/xat_xmpp/xmpp/omemo_session.gd")
	var omemo = ClassDB.instance("XatOmemo")

	var bare_a := "alice@h"
	var bare_b := "bob@h"

	var db_a = ClassDB.instance("SQLiteBinding")
	db_a.open(":memory:")
	var store_a = Store.new(db_a)
	store_a.ensure_schema()
	var dev_a = Device.new(store_a, omemo)
	dev_a.ensure_created()
	var eng_a = Session.new(store_a, dev_a, omemo)

	var db_b = ClassDB.instance("SQLiteBinding")
	db_b.open(":memory:")
	var store_b = Store.new(db_b)
	store_b.ensure_schema()
	var dev_b = Device.new(store_b, omemo)
	dev_b.ensure_created()
	var eng_b = Session.new(store_b, dev_b, omemo)

	check(eng_a.available() and eng_b.available(), "motores disponibles")

	# Descubrimiento (lo que haría PEP): cada lado conoce la lista y el bundle del otro.
	eng_a.set_peer_devices(bare_b, [dev_b.device_id()])
	eng_a.set_peer_bundle(bare_b, dev_b.device_id(), dev_b.bundle())
	eng_b.set_peer_devices(bare_a, [dev_a.device_id()])
	eng_b.set_peer_bundle(bare_a, dev_a.device_id(), dev_a.bundle())

	# 1) A -> B (KeyExchange).
	var e1 = eng_a.encrypt(bare_a, bare_b, "hola bob")
	check(e1["ok"], "A cifra #1")
	var d1 = eng_b.decrypt(bare_a, e1["element"])
	check(d1["ok"] and d1["body"] == "hola bob", "B descifra #1")
	check(d1["sender_device"] == dev_a.device_id(), "B identifica el dispositivo emisor")

	# 2) B -> A (KeyExchange en sentido inverso).
	var e2 = eng_b.encrypt(bare_b, bare_a, "hola alice")
	var d2 = eng_a.decrypt(bare_b, e2["element"])
	check(d2["ok"] and d2["body"] == "hola alice", "A descifra #2")

	# 3) Continuación sobre la sesión ya establecida (sin kex).
	var e3 = eng_a.encrypt(bare_a, bare_b, "segundo mensaje")
	var d3 = eng_b.decrypt(bare_a, e3["element"])
	check(d3["ok"] and d3["body"] == "segundo mensaje", "continuación A→B")

	# 4) Fuera de orden A→B.
	var e4 = eng_a.encrypt(bare_a, bare_b, "cuarto")
	var e5 = eng_a.encrypt(bare_a, bare_b, "quinto")
	var d5 = eng_b.decrypt(bare_a, e5["element"])
	var d4 = eng_b.decrypt(bare_a, e4["element"])
	check(d5["body"] == "quinto" and d4["body"] == "cuarto", "fuera de orden A→B")

	# 5) Confianza: B guardó la identidad de A.
	check(eng_b.trust_key(bare_a, dev_a.device_id()) == dev_a.identity_key(), "confianza: identidad de A")

	# 6) Un mensaje para otro dispositivo no aplica.
	var foreign = eng_a.encrypt(bare_a, bare_b, "efímero")
	check(not eng_b.decrypt("carol@h", foreign["element"])["ok"], "rechaza remitente sin match")

	if _fail == 0:
		print("OMEMO_SESSION_CHECK_OK")
	quit()

func check(p_ok: bool, p_label: String) -> void:
	if p_ok:
		print("ok %s" % p_label)
	else:
		_fail += 1
		print("FAIL %s" % p_label)
		OS.exit_code = 1
