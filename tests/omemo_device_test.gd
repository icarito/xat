extends SceneTree

# Material de llaves OMEMO del dispositivo: generación, persistencia, rotación
# del signed prekey y pool de prekeys, sobre SQLite en memoria.

var _fail := 0
var _dev

func _init():
	if not ClassDB.class_exists("SQLiteBinding") or not ClassDB.class_exists("XatOmemo"):
		print("FAIL: faltan clases nativas")
		OS.exit_code = 1
		quit()
		return
	var Store = load("res://addons/xat_xmpp/xmpp/omemo_store.gd")
	var Device = load("res://addons/xat_xmpp/xmpp/omemo_device.gd")
	var db = ClassDB.instance("SQLiteBinding")
	check(db.open(":memory:") == 0, "sqlite en memoria")
	var store = Store.new(db)
	check(store.ensure_schema(), "schema omemo_kv")
	var omemo = ClassDB.instance("XatOmemo")

	var dev = Device.new(store, omemo)
	check(dev.ensure_created(), "device creado")
	_dev = dev
	check(dev.device_id() > 0, "device id")
	check(dev.identity_key().size() == 32, "identidad 32 bytes")
	check(dev.signed_pre_key_id() > 0 and dev.signed_pre_key().size() == 32, "signed prekey")
	check(omemo.ed25519_check(dev.identity_key(), dev.signed_pre_key(), dev.signed_pre_key_sig()), "firma del spk válida")
	check(dev.prekey_count() >= 99, "pool de prekeys (%d)" % dev.prekey_count())

	# Persistencia: un nuevo manager sobre la misma base lee lo mismo.
	var dev2 = Device.new(store, omemo)
	check(dev2.ensure_created(), "device recargado")
	check(dev2.identity_key() == dev.identity_key() and dev2.device_id() == dev.device_id(), "identidad y device id estables")
	check(dev2.signed_pre_key_id() == dev.signed_pre_key_id(), "spk estable")
	check(dev2.prekey_count() == dev.prekey_count(), "prekeys persistidas")

	# Bundle coherente.
	var b = dev.bundle()
	check(b["ik"] == dev.identity_key() and b["spk"] == dev.signed_pre_key(), "bundle: ik y spk")
	check(b["prekeys"].size() == dev.prekey_count(), "bundle: prekeys")
	var pk0 = b["prekeys"][0]
	check(dev.prekey_id_for_pub(pk0["pub"]) == pk0["id"], "bundle: prekey resoluble por pública")

	# Rotación: conserva el anterior y firma válida.
	var old_id = dev.signed_pre_key_id()
	var old_priv = dev.signed_pre_key_priv()
	dev.rotate_signed_prekey()
	check(dev.signed_pre_key_id() != old_id, "rotación: nuevo id")
	check(dev.old_signed_pre_key_priv() == old_priv, "rotación: conserva el anterior")
	check(omemo.ed25519_check(dev.identity_key(), dev.signed_pre_key(), dev.signed_pre_key_sig()), "rotación: firma válida")

	# Consumir una prekey la quita.
	var n = dev.prekey_count()
	var consumed_id = dev.prekey_ids()[0]
	var consumed_priv = dev.prekey_priv(consumed_id)
	dev.consume_prekey(consumed_id)
	check(dev.prekey_count() == n - 1 and dev.prekey_priv(consumed_id).empty(), "consume prekey")
	check(omemo.x25519_public_key(consumed_priv).size() == 32, "la prekey consumida era válida")

	if _fail == 0:
		print("OMEMO_DEVICE_CHECK_OK")
	quit()

func check(p_ok: bool, p_label: String) -> void:
	if p_ok:
		print("ok %s" % p_label)
	else:
		_fail += 1
		print("FAIL %s" % p_label)
		OS.exit_code = 1
