extends SceneTree

# Nodo nativo `XatOmemo`: primitivas de OMEMO (curva25519, payload 2.0).
# Contrasta vectores de RFC 7748 (X25519), RFC 8032 (Ed25519) y un vector de
# interop del payload generado con la implementación de openclaw-xmpp.

var _fail := 0

func _init():
	if not ClassDB.class_exists("XatOmemo"):
		print("FAIL XatOmemo no registrada")
		OS.exit_code = 1
		quit()
		return
	var o = ClassDB.instance("XatOmemo")

	var st = o.self_test()
	check(st == "", "self_test interno (RFC 7748/8032 + payload) %s" % st)

	# RFC 7748 §6.1.
	var alice_priv = _hex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
	var bob_pub = _hex("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f")
	check(o.x25519_public_key(alice_priv) == _hex("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a"), "X25519 pública")
	check(o.x25519_shared(alice_priv, bob_pub) == _hex("4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"), "X25519 compartido")

	# RFC 8032 §7.1 TEST 1.
	var ed_seed = _hex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
	var pub = _hex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
	check(o.ed25519_public_key(ed_seed) == pub, "Ed25519 pública")
	var sig = o.ed25519_sign(ed_seed, PoolByteArray())
	check(sig == _hex("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"), "Ed25519 firma")
	check(o.ed25519_check(pub, PoolByteArray(), sig), "Ed25519 verifica")
	var bad := PoolByteArray()
	bad.append_array(sig)
	bad[0] = bad[0] ^ 0x01
	check(not o.ed25519_check(pub, PoolByteArray(), bad), "Ed25519 rechaza firma alterada")

	# Material de llaves: interop contra xeddsa de Syndace (valores generados con
	# la misma implementación que usa OpenClaw).
	var id_seed = _hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
	var id_pub = _hex("03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8")
	check(o.ed25519_public_key(id_seed) == id_pub, "identity: pública Ed25519 == xeddsa")
	check(o.ed25519_to_x25519(id_pub) == _hex("4701d08488451f545a409fb58ae3e58581ca40ac3f7f114698cd71deac73ca01"), "identity: conversión a X25519 == xeddsa")
	check(o.ed25519_check(id_pub, "xat signed prekey".to_utf8(), _hex("4394a30210af2ecaf87ef4b0ee2c86fa65eaa313190038ba0b57b3aed47b9e947dac0832b9b3831c2ee8dffd9b051c017766dbac7ffe437add7c810d2c50710d")), "identity: acepta firma de libxeddsa")
	var peer_seed = _hex("0101010101010101010101010101010101010101010101010101010101010101")
	var peer_x = o.ed25519_to_x25519(o.ed25519_public_key(peer_seed))
	check(o.x25519_shared(o.ed25519_to_x25519_secret(id_seed), peer_x) == _hex("9a2e4e03705f0d2058492081b43c824082408e450eb03aba6e3a43ce6976a802"), "identity: DH == xeddsa")
	var kp = o.x25519_keypair()
	check(kp.has("secret") and kp["secret"].size() == 32 and o.x25519_public_key(kp["secret"]) == kp["public"], "x25519_keypair coherente")
	var ekp = o.ed25519_keypair(id_seed)
	check(ekp.has("secret") and ekp["secret"].size() == 64 and ekp["public"] == id_pub, "ed25519_keypair coherente")

	# X3DH: activo y pasivo derivan el mismo secreto y el mismo AD.
	var b_seed = _hex("0101010101010101010101010101010101010101010101010101010101010101")
	var b_spk_priv = _hex("0202020202020202020202020202020202020202020202020202020202020202")
	var b_pre_priv = _hex("0303030303030303030303030303030303030303030303030303030303030303")
	var b_ik = o.ed25519_public_key(b_seed)
	var b_spk = o.x25519_public_key(b_spk_priv)
	var b_pre = o.x25519_public_key(b_pre_priv)
	var bundle = {"ik": b_ik, "spk": b_spk, "spk_sig": o.ed25519_sign(b_seed, b_spk), "prekey": b_pre}
	var act = o.x3dh_active(id_seed, bundle, _hex("0404040404040404040404040404040404040404040404040404040404040404"))
	check(act.has("ss") and act["ad"] == (id_pub + b_ik), "x3dh: activo, AD = ikA||ikB")
	var pas = o.x3dh_passive(b_seed, b_spk_priv, b_pre_priv, {"ik": act["ik"], "ek": act["ek"]})
	check(pas["ss"] == act["ss"], "x3dh: pasivo deriva el mismo secreto")
	check(pas["ad"] == act["ad"], "x3dh: pasivo deriva el mismo AD")
	var bad_sig = _hex("00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")
	var bundle_bad = {"ik": b_ik, "spk": b_spk, "spk_sig": bad_sig, "prekey": b_pre}
	check(o.x3dh_active(id_seed, bundle_bad, PoolByteArray()).empty(), "x3dh: rechaza firma de spk inválida")

	# Double Ratchet: dos sesiones nativas se hablan en ambos sentidos, con
	# mensajes fuera de orden y detección de manipulación.
	var ss = _bytes(0x11, 32)
	var ad = _bytes(0x22, 64)
	var b2_priv = _bytes(0x02, 32)
	var b2_pub = o.x25519_public_key(b2_priv)
	var ses_a = o.dr_start_active(ss, b2_pub, ad, _bytes(0xA0, 48))
	check(ses_a.has("state") and ses_a.has("ciphertext"), "dr: sesión activa")
	var ses_b = o.dr_start_passive(ss, b2_priv, ad, ses_a["ciphertext"])
	check(ses_b.has("plaintext") and ses_b["plaintext"] == _bytes(0xA0, 48), "dr: inicial descifrado")
	var m1 = o.dr_encrypt(ses_a["state"], ad, _bytes(0xB1, 48))
	check(o.dr_decrypt(ses_b["state"], ad, m1["ciphertext"])["plaintext"] == _bytes(0xB1, 48), "dr: A→B")
	var m2 = o.dr_encrypt(ses_b["state"], ad, _bytes(0xC2, 48))
	var back = o.dr_decrypt(m1["state"], ad, m2["ciphertext"])
	check(back["plaintext"] == _bytes(0xC2, 48), "dr: B→A (ratchet DH)")
	# Fuera de orden.
	var o1 = o.dr_encrypt(m1["state"], ad, _bytes(0xD1, 16))
	var o2 = o.dr_encrypt(o1["state"], ad, _bytes(0xD2, 16))
	var rx2 = o.dr_decrypt(ses_b["state"], ad, o2["ciphertext"])
	var rx1 = o.dr_decrypt(rx2["state"], ad, o1["ciphertext"])
	check(rx2["plaintext"] == _bytes(0xD2, 16) and rx1["plaintext"] == _bytes(0xD1, 16), "dr: mensajes salteados")
	# MAC manipulado.
	var tampered = o1["ciphertext"]
	tampered[20] = tampered[20] ^ 0x01
	check(o.dr_decrypt(m1["state"], ad, tampered).empty(), "dr: rechaza ciphertext manipulado")

	# Payload de interop (misma clave y bytes que produce openclaw-xmpp).
	var key48 = _hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f6032e091967d4a46c46e5706855512ca")
	var vector = _hex("2c450ccc8ab79c1862cc619b8b898342")
	check(o.payload_decrypt(vector, key48) == "hola".to_utf8(), "payload interop OpenClaw")
	var key32 = _hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
	check(o.payload_encrypt_with_key(key32, "hola".to_utf8()) == vector, "payload_encrypt_with_key == vector")

	# Round-trip real con clave aleatoria.
	var d = o.payload_encrypt("mensaje secreto".to_utf8())
	check(d.has("key") and d["key"].size() == 48 and d.has("payload"), "payload_encrypt: key48 + payload")
	check(o.payload_decrypt(d["payload"], d["key"]) == "mensaje secreto".to_utf8(), "payload round-trip")
	var wrong := PoolByteArray()
	wrong.append_array(d["key"])
	wrong[0] = wrong[0] ^ 0x01
	check(o.payload_decrypt(d["payload"], wrong).empty(), "payload: mac inválido falla")
	check(o.payload_decrypt(d["payload"], key32).empty(), "payload: clave ajena falla")

	if _fail == 0:
		print("OMEMO_NATIVE_CHECK_OK")
	quit()

func _hex(p_s: String) -> PoolByteArray:
	var out := PoolByteArray()
	var i := 0
	while i < p_s.length():
		out.append(("0x" + p_s.substr(i, 2)).hex_to_int())
		i += 2
	return out

func _bytes(p_v: int, p_n: int) -> PoolByteArray:
	var out := PoolByteArray()
	for _i in range(p_n):
		out.append(p_v)
	return out

func check(p_ok: bool, p_label: String) -> void:
	if p_ok:
		print("ok %s" % p_label)
	else:
		_fail += 1
		print("FAIL %s" % p_label)
		OS.exit_code = 1
