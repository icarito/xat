extends SceneTree

# Recorder: normalización del PCM 16-bit de la grabación. La captura del mic
# llega muy baja (rms de decenas), así que al guardar se amplifica al pico
# objetivo. Aquí se prueba la lógica pura `normalize_pcm16`.

var _fail := 0

func _init():
	var Recorder = load("res://addons/xat_xmpp/xmpp/recorder.gd")

	# Buffer de 4 samples s16: -2, 4, -4, 2 -> pico 4.
	var buf := _pcm([-2, 4, -4, 2])
	var out = Recorder.normalize_pcm16(buf, 0.85, 30.0)
	var vals = _read(out)
	var pk = 0
	for v in vals:
		pk = max(pk, abs(v))
	check(vals.size() == 4, "normalize conserva la cantidad de samples")
	check(pk > 4, "normalize amplifica un buffer bajo (peak %d)" % pk)
	check(pk <= 32767, "normalize no desborda int16 (peak %d)" % pk)
	# La forma relativa se conserva (signo y proporción).
	check(vals[0] < 0 and vals[1] > 0 and vals[2] < 0 and vals[3] > 0, "normalize conserva el signo")
	check(abs(vals[1]) == 2 * abs(vals[3]), "normalize mantiene la proporción")

	# Silencio digital: no debe tocarse (evita amplificar el vacío a ruido).
	var sil := _pcm([0, 0, 0, 0])
	check(_read(Recorder.normalize_pcm16(sil, 0.85, 30.0)) == [0, 0, 0, 0], "normalize deja el silencio en cero")

	# Ya fuerte: si el pico supera el objetivo no se reamplifica (gain<=1).
	var loud := _pcm([30000, -30000])
	check(_read(Recorder.normalize_pcm16(loud, 0.85, 30.0)) == [30000, -30000], "normalize no toca un buffer ya fuerte")

	# Tope de ganancia: un buffer bajísimo no se amplifica más que max_gain.
	var tiny := _pcm([1, -1])
	var t = _read(Recorder.normalize_pcm16(tiny, 0.85, 3.0))
	check(abs(t[0]) <= 3, "normalize respeta el tope de ganancia")

	if _fail == 0:
		print("TODOS OK")
	OS.exit_code = _fail
	quit()

func _pcm(p_vals: Array) -> PoolByteArray:
	var b := PoolByteArray()
	for v in p_vals:
		var u = v if v >= 0 else v + 65536
		b.append(u & 0xFF)
		b.append((u >> 8) & 0xFF)
	return b

func _read(p_buf: PoolByteArray) -> Array:
	var out := []
	var i := 0
	while i < p_buf.size() / 2:
		var v = p_buf[i * 2] | (p_buf[i * 2 + 1] << 8)
		if v >= 32768:
			v -= 65536
		out.append(v)
		i += 1
	return out

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)