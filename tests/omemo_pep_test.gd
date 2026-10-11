extends SceneTree

# PEP de OMEMO: construcción de los items de device-list y bundle, y del IQ de
# publicación (XEP-0060) con publish-options.

var _fail := 0

func _init():
	var Omemo = load("res://addons/xat_xmpp/xmpp/omemo.gd")
	var PubSub = load("res://addons/xat_xmpp/xmpp/pubsub.gd")
	var o = ClassDB.instance("XatOmemo")

	# Device list.
	var devices_el = Omemo.build_devices_element([{"id": 1234, "label": "xat"}])
	check(devices_el.name == "devices" and devices_el.get_attr("xmlns", "") == "urn:xmpp:omemo:2", "devices: elemento y ns")
	check(Omemo.parse_device_list(devices_el)[0]["id"] == 1234, "devices: parsea id")

	# Bundle.
	var id_seed = o.random_bytes(32)
	var spk = o.x25519_keypair()
	var sig = o.ed25519_sign(id_seed, spk["public"])
	var pk = o.x25519_keypair()
	var dev_bundle = {
		"ik": o.ed25519_public_key(id_seed),
		"spk": spk["public"], "spk_id": 77, "spk_sig": sig,
		"prekeys": [{"id": 5, "pub": pk["public"]}],
	}
	var bundle_el = Omemo.build_bundle_element(dev_bundle)
	check(bundle_el.name == "bundle" and bundle_el.get_attr("xmlns", "") == "urn:xmpp:omemo:2", "bundle: elemento y ns")
	var parsed = Omemo.parse_bundle(bundle_el)
	check(parsed["identity_b64"] == Marshalls.raw_to_base64(dev_bundle["ik"]), "bundle: ik")
	check(parsed["spk"]["id"] == 77 and parsed["spk_sig_b64"] == Marshalls.raw_to_base64(sig), "bundle: spk y firma")
	check(parsed["prekeys"].size() == 1 and parsed["prekeys"][0]["id"] == 5, "bundle: prekeys")

	# IQ de publicación.
	var iq = PubSub.build_publish("p1", "", "urn:xmpp:omemo:2:devices", "current", devices_el)
	check(iq.get_attr("type") == "set" and iq.get_attr("id") == "p1", "publish: iq set")
	var pubsub = iq.get_child("pubsub", "http://jabber.org/protocol/pubsub")
	var publish = pubsub.get_child("publish")
	check(publish.get_attr("node", "") == "urn:xmpp:omemo:2:devices", "publish: node")
	var item = publish.get_child("item")
	check(item.get_attr("id", "") == "current" and item.get_child("devices") != null, "publish: item y payload")
	var opts = pubsub.get_child("publish-options").get_child("x", "jabber:x:data")
	var form_type = ""
	var access = ""
	for f in opts.get_children("field"):
		if f.get_attr("var", "") == "FORM_TYPE":
			form_type = f.get_child("value").get_text()
		elif f.get_attr("var", "") == "pubsub#access_model":
			access = f.get_child("value").get_text()
	check(form_type == "http://jabber.org/protocol/pubsub#publish-options", "publish: FORM_TYPE")
	check(access == "open", "publish: access_model")

	if _fail == 0:
		print("OMEMO_PEP_CHECK_OK")
	quit()

func check(p_ok: bool, p_label: String) -> void:
	if p_ok:
		print("ok %s" % p_label)
	else:
		_fail += 1
		print("FAIL %s" % p_label)
		OS.exit_code = 1
