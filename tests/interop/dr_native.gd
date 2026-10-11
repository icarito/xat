extends SceneTree

# Un paso de Double Ratchet nativo para el test de interop (tests/interop/dr_interop.py).
# Lee la operación de XAT_DR_OP y el JSON de XAT_DR_INPUT (valores hex), y
# escribe "XAT_DR_OUT <json>" con los bytes de salida en hex.

func _init():
	var op := OS.get_environment("XAT_DR_OP")
	var inp = parse_json(OS.get_environment("XAT_DR_INPUT"))
	var o = ClassDB.instance("XatOmemo")
	var out := {}
	match op:
		"active":
			out = o.dr_start_active(_hex(inp["ss"]), _hex(inp["recipient_pub"]), _hex(inp["ad"]), _hex(inp["plain"]))
		"passive":
			out = o.dr_start_passive(_hex(inp["ss"]), _hex(inp["own_ratchet_priv"]), _hex(inp["ad"]), _hex(inp["ciphertext"]))
		"encrypt":
			out = o.dr_encrypt(_hex(inp["state"]), _hex(inp["ad"]), _hex(inp["plain"]))
		"decrypt":
			out = o.dr_decrypt(_hex(inp["state"]), _hex(inp["ad"]), _hex(inp["ciphertext"]))
		"aead_encrypt":
			var header := {"n": int(inp["n"]), "pn": int(inp["pn"]), "dh_pub": _hex(inp["dh_pub"])}
			out = {"ciphertext": o.dr_aead_encrypt(_hex(inp["mk"]), _hex(inp["plain"]), _hex(inp["ad"]), header)}
		"aead_decrypt":
			out = o.dr_aead_decrypt(_hex(inp["mk"]), _hex(inp["ad"]), _hex(inp["ciphertext"]))
	var json := {}
	for k in out.keys():
		var v = out[k]
		if v is PoolByteArray:
			json[k] = v.hex_encode()
		else:
			json[k] = v
	print("XAT_DR_OUT %s" % to_json(json))
	quit()

func _hex(p_s: String) -> PoolByteArray:
	var out := PoolByteArray()
	var i := 0
	while i < p_s.length():
		out.append(("0x" + p_s.substr(i, 2)).hex_to_int())
		i += 2
	return out
