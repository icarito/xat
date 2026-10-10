extends SceneTree

# Códec IMA-ADPCM: round-trip encode->decode y armado/lectura del WAV ADPCM.
# Todo puro (sin AudioServer ni FS), así que corre headless con cualquier binario.

var _fail := 0

func _init():
	var Adpcm = load("res://addons/xat_xmpp/xmpp/adpcm.gd")
	var Media = load("res://addons/xat_xmpp/xmpp/media.gd")

	# Round-trip de una onda conocida (seno 440Hz, 16kHz mono).
	var rate = 16000
	var n = rate / 2 # 0.5 s
	var pcm := PoolByteArray()
	for i in range(n):
		var s = int(sin(TAU * 440.0 * i / rate) * 12000)
		var u = s if s >= 0 else s + 65536
		pcm.append(u & 0xFF)
		pcm.append((u >> 8) & 0xFF)

	var enc = Adpcm.encode(pcm, 1, rate, 512)
	check(enc["data"].size() > 0, "encode produce datos")
	check(enc["data"].size() < pcm.size(), "encode comprime (adpcm %d < pcm %d)" % [enc["data"].size(), pcm.size()])
	var dec = Adpcm.decode(enc["data"], 1, enc["samples_per_block"])
	check(dec.size() > 0, "decode produce PCM")
	# La señal no tiene que ser idéntica (es lossy) pero debe correlacionar fuerte.
	var corr = _correlation(pcm, dec)
	check(corr > 0.95, "round-trip correlaciona (%.3f)" % corr)
	# Y no debe ser silencio.
	check(_rms(dec) > 1000, "decode no es silencio (rms %d)" % _rms(dec))

	# WAV ADPCM: armar y volver a leer.
	var wav = Media.build_wav_adpcm(enc)
	check(Media.is_wav_adpcm(wav), "el WAV se reconoce como ADPCM")
	var parsed = Media.parse_wav_adpcm(wav)
	check(parsed["ok"], "parse_wav_adpcm ok")
	check(parsed["channels"] == 1, "canales preservados")
	check(parsed["sample_rate"] == rate, "sample rate preservado")
	var dec2 = Adpcm.decode(parsed["data"], parsed["channels"], parsed["samples_per_block"])
	check(_correlation(pcm, dec2) > 0.95, "WAV ida y vuelta correlaciona")

	# Downmix+remuestreo: estéreo 44.1k -> mono 16k.
	var st := PoolByteArray()
	for i in range(4410):
		var s = int(sin(TAU * 200.0 * i / 44100.0) * 8000)
		var u = s if s >= 0 else s + 65536
		st.append(u & 0xFF); st.append((u >> 8) & 0xFF) # L
		st.append(u & 0xFF); st.append((u >> 8) & 0xFF) # R
	var mono = Media.downmix_resample(st, 2, 44100, 16000)
	check(mono.size() > 0, "downmix_resample produce salida")
	check(mono.size() / 2 < 4410, "downmix_resample baja la cantidad de samples")

	# Bloque parcial: una cantidad de samples que no es múltiplo del bloque.
	var odd := PoolByteArray()
	for i in range(1000):
		var s = int(sin(TAU * 300.0 * i / rate) * 9000)
		var u = s if s >= 0 else s + 65536
		odd.append(u & 0xFF); odd.append((u >> 8) & 0xFF)
	var eo = Adpcm.encode(odd, 1, rate, 512)
	var do = Adpcm.decode(eo["data"], 1, eo["samples_per_block"])
	check(do.size() / 2 >= 1000 - 2, "bloque parcial no pierde el final (%d de 1000)" % (do.size() / 2))
	check(_correlation(odd, do) > 0.95, "bloque parcial correlaciona")

	if _fail == 0:
		print("TODOS OK")
	OS.exit_code = _fail
	quit()

func _ints(p_pcm: PoolByteArray) -> Array:
	var out := []
	var i := 0
	while i < p_pcm.size() / 2:
		var v = p_pcm[i * 2] | (p_pcm[i * 2 + 1] << 8)
		if v >= 32768:
			v -= 65536
		out.append(v)
		i += 1
	return out

func _rms(p_pcm: PoolByteArray) -> int:
	var s = _ints(p_pcm)
	if s.empty():
		return 0
	var acc = 0.0
	for v in s:
		acc += v * v
	return int(sqrt(acc / s.size()))

# Correlación de Pearson entre dos buffers PCM16 (alinea al mínimo).
func _correlation(p_a: PoolByteArray, p_b: PoolByteArray) -> float:
	var a = _ints(p_a)
	var b = _ints(p_b)
	var n = min(a.size(), b.size())
	if n == 0:
		return 0.0
	var ma := 0.0
	var mb := 0.0
	for i in range(n):
		ma += a[i]
		mb += b[i]
	ma /= n
	mb /= n
	var num := 0.0
	var da := 0.0
	var db := 0.0
	for i in range(n):
		var x = a[i] - ma
		var y = b[i] - mb
		num += x * y
		da += x * x
		db += y * y
	if da <= 0.0 or db <= 0.0:
		return 0.0
	return num / sqrt(da * db)

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)