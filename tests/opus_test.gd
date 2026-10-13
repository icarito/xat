extends SceneTree

# Códec Opus nativo (modules/xmpp): encode PCM16 -> Ogg Opus y decode -> PCM16.
# Requiere el binario con el módulo (tools/build.sh).

var _fail := 0

func _init():
	if not ClassDB.class_exists("OpusCodec"):
		check(false, "OpusCodec registrado")
		print("OPUS_CHECK_FAIL (sin módulo)")
		quit()
		return
	check(true, "OpusCodec registrado")
	var codec = ClassDB.instance("OpusCodec")

	var rate = 16000
	var n = rate / 2 # 0.5 s
	var pcm = PoolByteArray()
	pcm.resize(n * 2)
	for i in range(n):
		var v = int(sin(TAU * 440.0 * float(i) / float(rate)) * 8000.0)
		var u = v & 0xFFFF
		pcm.set(i * 2, u & 0xFF)
		pcm.set(i * 2 + 1, (u >> 8) & 0xFF)

	var ogg = codec.encode(pcm, rate, 1, 24000)
	check(ogg.size() > 0, "encode produce bytes (%d)" % ogg.size())

	var magic = ""
	for i in range(min(4, ogg.size())):
		magic += char(ogg[i])
	check(magic == "OggS", "empieza con 'OggS'")

	var dec = codec.decode(ogg)
	check(dec.has("pcm") and dec["pcm"].size() > 0, "decode devuelve PCM")
	check(int(dec.get("rate", 0)) == 48000, "rate 48k (opusfile) (%d)" % int(dec.get("rate", 0)))
	check(int(dec.get("channels", 0)) == 1, "canales preservados")
	var samples = dec["pcm"].size() / 2
	check(samples >= n / 2, "muestras decodificadas ~ original (%d vs %d)" % [samples, n])

	if _fail == 0:
		print("OPUS_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
