extends SceneTree

# Volcado de X3DH para el test de interop (tests/interop/x3dh_interop.py).
# Claves fijas y deterministas para poder comparar contra la librería `x3dh`.

const A_SEED := "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
const B_SEED := "0101010101010101010101010101010101010101010101010101010101010101"
const B_SPK_PRIV := "0202020202020202020202020202020202020202020202020202020202020202"
const B_PREKEY_PRIV := "0303030303030303030303030303030303030303030303030303030303030303"
const A_EPHEMERAL := "0404040404040404040404040404040404040404040404040404040404040404"

func _init():
	var o = ClassDB.instance("XatOmemo")
	var a_seed = _hex(A_SEED)
	var b_seed = _hex(B_SEED)
	var b_spk_priv = _hex(B_SPK_PRIV)
	var b_prekey_priv = _hex(B_PREKEY_PRIV)
	var a_eph = _hex(A_EPHEMERAL)

	var b_ik = o.ed25519_public_key(b_seed)
	var b_spk = o.x25519_public_key(b_spk_priv)
	var b_prekey = o.x25519_public_key(b_prekey_priv)
	var b_sig = o.ed25519_sign(b_seed, b_spk)
	var bundle_b = {"ik": b_ik, "spk": b_spk, "spk_sig": b_sig, "prekey": b_prekey}

	var active = o.x3dh_active(a_seed, bundle_b, a_eph)
	print("A_IK %s" % active["ik"].hex_encode())
	print("HEADER_EK %s" % active["ek"].hex_encode())
	print("SS_ACTIVE %s" % active["ss"].hex_encode())
	print("AD_ACTIVE %s" % active["ad"].hex_encode())

	var header = {"ik": active["ik"], "ek": active["ek"]}
	var passive = o.x3dh_passive(b_seed, b_spk_priv, b_prekey_priv, header)
	print("SS_PASSIVE %s" % passive["ss"].hex_encode())
	print("AD_PASSIVE %s" % passive["ad"].hex_encode())

	print("B_IK %s" % b_ik.hex_encode())
	print("B_SPK %s" % b_spk.hex_encode())
	print("B_PREKEY %s" % b_prekey.hex_encode())
	quit()

func _hex(p_s: String) -> PoolByteArray:
	var out := PoolByteArray()
	var i := 0
	while i < p_s.length():
		out.append(("0x" + p_s.substr(i, 2)).hex_to_int())
		i += 2
	return out
