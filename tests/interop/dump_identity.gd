extends SceneTree

# Volcado para el test de interop de identidad OMEMO (tests/interop/).
# Imprime una línea por dato; lo consume `omemo_identity_interop.sh` y lo
# verifica contra la implementación de referencia (xeddsa de Syndace, la que
# usa OpenClaw). No forma parte de la suite: no termina en `_test.gd`.

func _init():
	var o = ClassDB.instance("XatOmemo")
	var id_seed = _hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
	var kp = o.ed25519_keypair(id_seed)
	var sig = o.ed25519_sign(id_seed, "xat signed prekey".to_utf8())
	print("SEED %s" % id_seed.hex_encode())
	print("PUB %s" % kp["public"].hex_encode())
	print("SIG %s" % sig.hex_encode())
	print("X25519 %s" % o.ed25519_to_x25519(kp["public"]).hex_encode())
	quit()

func _hex(p_s: String) -> PoolByteArray:
	var out := PoolByteArray()
	var i := 0
	while i < p_s.length():
		out.append(("0x" + p_s.substr(i, 2)).hex_to_int())
		i += 2
	return out
