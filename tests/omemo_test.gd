extends SceneTree

# OMEMO (XEP-0384): modelo puro (stanzas, PEP, SCE, protobuf). La cripto es
# nativa; acá se validan los formatos de cable con los que hay que interoperar
# (contraste: openclaw-xmpp src/omemo/index.ts y v2-crypto.ts).

var _fail := 0

func _init():
	var Omemo = load("res://addons/xat_xmpp/xmpp/omemo.gd")
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")

	# --- Mensaje cifrado OMEMO 2 ---
	var v2 = Stanza.parse('<message type="chat" from="bob@h/oc" to="me@h/xat">'
		+ '<encrypted xmlns="urn:xmpp:omemo:2"><header sid="111">'
		+ '<keys jid="me@h"><key rid="7" kex="true">aGVsbG8=</key><key rid="9">d29ybGQ=</key></keys>'
		+ '<keys jid="bob@h"><key rid="111">Ym9i</key></keys>'
		+ '</header><payload>UGFZTE9BRA==</payload></encrypted></message>')
	check(Omemo.is_encrypted(v2), "v2: detecta cifrado")
	var enc = Omemo.parse_encrypted(Omemo.encrypted_child(v2), 7)
	check(enc["namespace"] == "urn:xmpp:omemo:2" and enc["sid"] == 111, "v2: ns y sid")
	check(enc["keys"].size() == 3, "v2: tres claves")
	check(enc["payload_b64"] == "UGFZTE9BRA==", "v2: payload")
	check(enc["iv_b64"] == "", "v2: sin <iv> (se deriva por HKDF)")
	check(enc["our"]["rid"] == 7 and enc["our"]["key_b64"] == "aGVsbG8=", "v2: nuestra clave")
	check(enc["our_prekey"], "v2: kex marcado")

	# --- Mensaje cifrado legacy (0.3) ---
	var legacy = Stanza.parse('<message from="c@h"><encrypted xmlns="eu.siacs.conversations.axolotl">'
		+ '<header sid="42"><key rid="5" prekey="true">a2V5</key><iv>aXZpdml2aXY=</iv></header>'
		+ '<payload>cGF5</payload></encrypted></message>')
	var le = Omemo.parse_encrypted(Omemo.encrypted_child(legacy), 5)
	check(le["namespace"] == "eu.siacs.conversations.axolotl" and le["sid"] == 42, "legacy: ns y sid")
	check(le["iv_b64"] == "aXZpdml2aXY=", "legacy: iv")
	check(le["our"]["key_b64"] == "a2V5" and le["our_prekey"], "legacy: clave con prekey")

	# --- Lista de dispositivos (PEP) ---
	var devices = Stanza.parse('<devices xmlns="urn:xmpp:omemo:2"><device id="7" label="xat"/><device id="9"/></devices>')
	var dl = Omemo.parse_device_list(devices)
	check(dl.size() == 2 and dl[0]["id"] == 7 and dl[0]["label"] == "xat" and dl[1]["id"] == 9, "devices: parse")
	var dl2 = Omemo.parse_device_list(Stanza.parse(Omemo.serialize_device_list(dl)))
	check(dl2.size() == 2 and dl2[1]["label"] == "" and str(Omemo.serialize_device_list(dl)).find("urn:xmpp:omemo:2") >= 0, "devices: round-trip")

	# --- Bundle OMEMO 2 (formato de openclaw-xmpp) ---
	var b2 = Stanza.parse('<bundle xmlns="urn:xmpp:omemo:2"><spk id="456">c2lnbmVkS2V5UHVibGlj</spk>'
		+ '<spks>c2lnbmVkS2V5U2lnbmF0dXJl</spks><ik>aWRlbnRpdHlLZXlQdWJsaWM=</ik>'
		+ '<prekeys><pk id="10">cHJlS2V5UHVibGljMQ==</pk><pk id="20">cHJlS2V5UHVibGljMg==</pk></prekeys></bundle>')
	var bu = Omemo.parse_bundle(b2)
	check(bu["identity_b64"] == "aWRlbnRpdHlLZXlQdWJsaWM=", "bundle v2: ik")
	check(bu["spk"]["id"] == 456 and bu["spk_sig_b64"] == "c2lnbmVkS2V5U2lnbmF0dXJl", "bundle v2: spk")
	check(bu["prekeys"].size() == 2 and bu["prekeys"][0]["id"] == 10, "bundle v2: prekeys")
	var bu_rt = Omemo.parse_bundle(Stanza.parse(Omemo.serialize_bundle(bu)))
	check(bu_rt["spk"]["id"] == 456 and bu_rt["prekeys"][1]["b64"] == "cHJlS2V5UHVibGljMg==", "bundle v2: round-trip")

	# --- Bundle legacy ---
	var bl = Stanza.parse('<bundle xmlns="eu.siacs.conversations.axolotl">'
		+ '<signedPreKeyPublic signedPreKeyId="123">c2lnbmVkS2V5UHVibGlj</signedPreKeyPublic>'
		+ '<signedPreKeySignature>c2lnbmVkS2V5U2lnbmF0dXJl</signedPreKeySignature>'
		+ '<identityKey>aWRlbnRpdHlLZXlQdWJsaWM=</identityKey>'
		+ '<prekeys><preKeyPublic preKeyId="1">cHJlS2V5UHVibGljMQ==</preKeyPublic></prekeys></bundle>')
	var bul = Omemo.parse_bundle(bl)
	check(bul["spk"]["id"] == 123 and bul["prekeys"][0]["id"] == 1, "bundle legacy: parse")

	# --- Envelope SCE (XEP-0420) ---
	var env = Omemo.build_sce_envelope('hola <mundo> & "x"', "sala@conference.h", "AAA")
	check(env.find("urn:xmpp:sce:1") >= 0 and env.find('jid="sala@conference.h"') >= 0, "sce: construye envelope")
	check(Omemo.unwrap_sce(env) == 'hola <mundo> & "x"', "sce: round-trip")
	check(Omemo.unwrap_sce("texto plano") == "texto plano", "sce: passthrough sin SCE")

	# --- Protobuf: números de campo fijos (interop v2-crypto.ts) ---
	var ct := PoolByteArray([0x01, 0x02, 0x03])
	var mac := PoolByteArray([0x0a, 0x0b])
	var dh := PoolByteArray([0xde, 0xad, 0xbe, 0xef])
	var pb = Omemo.encode_authenticated_message(ct, mac, 5, 3, dh)
	var expect := PoolByteArray([0x0a, 0x02, 0x0a, 0x0b, 0x12, 0x0f,
		0x08, 0x05, 0x10, 0x03, 0x1a, 0x04, 0xde, 0xad, 0xbe, 0xef, 0x22, 0x03, 0x01, 0x02, 0x03])
	check(pb == expect, "protobuf: bytes exactos")
	var dec = Omemo.decode_authenticated_message(pb)
	check(dec["mac"] == mac and dec["ciphertext"] == ct, "protobuf: mac y ciphertext")
	check(dec["n"] == 5 and dec["pn"] == 3 and dec["dh_pub"] == dh, "protobuf: cabecera ratchet")

	if _fail == 0:
		print("OMEMO_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
