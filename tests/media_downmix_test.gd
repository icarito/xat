extends SceneTree

# Filtro anti-alias del downmix: al bajar 44100->16000 sin filtro, todo lo que
# está por encima de 8 kHz se pliega de vuelta (sonido metálico/robótico).

const Media = preload("res://addons/xat_xmpp/xmpp/media.gd")

var _fail := 0

func _init():
	check(Media.downmix_resample(PoolByteArray(), 2, 44100, 16000).size() == 0, "vacio -> vacio")
	check(Media.downmix_resample(_sine(44100, 5000, 0.05, 10000), 1, 44100, 16000).size() > 0, "mono_ACCEPT")

	# Tono dentro de la banda (5 kHz < 7.3 kHz): pasa casi íntegro.
	var keep = Media.downmix_resample(_sine(44100, 5000, 0.1, 10000), 2, 44100, 16000)
	check(_peak(keep) > 5000, "banda util pasa")

	# Tono por encima del Nyquist de salida (12 kHz -> se plegaría a 4 kHz).
	# Con anti-alias debe caer fuerte en vez de quedar a volumen alto.
	var kill = Media.downmix_resample(_sine(44100, 12000, 0.1, 10000), 2, 44100, 16000)
	check(_peak(kill) < 3000, "anti-alias atenúa lo plegado")
	check(_peak(kill) < _peak(keep), "el plegado cae más que la banda útil")

	# Silencio sigue siendo silencio.
	check(_peak(Media.downmix_resample(_sine(44100, 5000, 0.1, 0), 2, 44100, 16000)) == 0, "silencio -> silencio")

	if _fail == 0:
		print("MEDIA_DOWNMIX_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)

func _sine(p_rate: int, p_freq: float, p_secs: float, p_amp: int) -> PoolByteArray:
	var n = int(p_rate * p_secs)
	var out = PoolByteArray()
	out.resize(n * 4) # estéreo, 16-bit
	for i in range(n):
		var v = round(float(p_amp) * sin(2.0 * PI * p_freq * float(i) / float(p_rate)))
		var u = int(v) if v >= 0 else int(v) + 65536
		out[i * 4] = u & 0xFF
		out[i * 4 + 1] = (u >> 8) & 0xFF
		out[i * 4 + 2] = u & 0xFF
		out[i * 4 + 3] = (u >> 8) & 0xFF
	return out

func _peak(p_pcm: PoolByteArray) -> int:
	var n = p_pcm.size() / 2
	var mx = 0
	for i in range(n):
		var v = p_pcm[i * 2] | (p_pcm[i * 2 + 1] << 8)
		if v >= 32768:
			v -= 65536
		v = abs(v)
		if v > mx:
			mx = v
	return mx
