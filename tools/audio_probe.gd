extends SceneTree

# Diagnóstico de playback: reproduce un WAV en el device de audio actual y
# reporta el estado del AudioServer. Uso:
#   bin/godot-xat --no-window --path app -s tools/audio_probe.gd -- <ruta.wav>
# Sin argumento usa un WAV de la caché de media si existe.

const MediaUtil = preload("res://addons/xat_xmpp/ui/media_util.gd")

func _init():
	var args = OS.get_cmdline_args()
	var path = ""
	for a in args:
		if a.ends_with(".wav"):
			path = a
	if path == "":
		var dir = Directory.new()
		if dir.open("user://media") == OK:
			dir.list_dir_begin(true, true)
			var f = dir.get_next()
			while f != "":
				if f.ends_with(".wav"):
					path = "user://media/" + f
					break
				f = dir.get_next()
	print("audio_probe: device=%s" % AudioServer.get_device())
	print("audio_probe: mix_rate=%d" % AudioServer.get_mix_rate())
	print("audio_probe: master_muted=%s master_volume_db=%.1f" % [AudioServer.is_bus_mute(0), AudioServer.get_bus_volume_db(0)])
	print("audio_probe: path=%s" % path)
	if path == "":
		print("audio_probe: SIN WAV de prueba")
		quit()
		return
	var stream = MediaUtil.load_audio(path)
	if stream == null:
		print("audio_probe: load_audio => null (formato no soportado)")
		quit()
		return
	print("audio_probe: stream=%s length=%.3f" % [stream.get_class(), stream.get_length()])
	# Replica el bus de grabación de la app: si esto deja el output mudo, es la
	# causa del "no se oye" en xat.
	var idx = AudioServer.get_bus_index("XatRecord")
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "XatRecord")
	AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(idx, -80.0)
	var eff = AudioEffectRecord.new()
	AudioServer.add_bus_effect(idx, eff)
	print("audio_probe: bus XatRecord idx=%d send=%s" % [idx, AudioServer.get_bus_send(idx)])
	# Fuerza la APERTURA del micrófono (como al grabar): si esto silencia la
	# salida en SDL2/PipeWire, es la causa del playback mudo de la app.
	var mic = AudioStreamPlayer.new()
	mic.stream = AudioStreamMicrophone.new()
	mic.bus = "XatRecord"
	get_root().add_child(mic)
	mic.play()
	print("audio_probe: mic input playing=%s" % mic.playing)
	var p = AudioStreamPlayer.new()
	p.bus = "Master"
	p.stream = stream
	p.volume_db = 0.0
	get_root().add_child(p)
	# Conectar terminado/error.
	p.connect("finished", self, "_fin")
	p.play()
	print("audio_probe: play() -> playing=%s" % p.playing)
	# Corta a los 4 s por si no termina.
	var t = Timer.new()
	t.wait_time = 4.0
	t.one_shot = true
	t.connect("timeout", self, "_fin")
	get_root().add_child(t)
	t.start()

func _fin():
	print("audio_probe: fin")
	quit()