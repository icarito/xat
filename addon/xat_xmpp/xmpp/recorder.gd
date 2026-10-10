extends Node

# Grabador de voz: micro -> bus "XatRecord" con AudioEffectRecord -> WAV.
# La señal se comprime a IMA-ADPCM 16 kHz mono (voz) para que pese ~13x menos
# que PCM 44.1 kHz estéreo. El encode corre en un Thread propio para no congelar
# la UI en grabaciones largas; `recording_finished` se emite desde el hilo
# principal (call_deferred).
#
# El bus de grabación se manda a Master con el volumen al mínimo: así no se
# realimenta el micrófono a los parlantes. Requiere
# `audio/driver/enable_input=true` (project.godot).

signal recording_started()
signal recording_finished(path, duration_ms, bytes)
signal recording_failed(reason)

const Media = preload("res://addons/xat_xmpp/xmpp/media.gd")
const Adpcm = preload("res://addons/xat_xmpp/xmpp/adpcm.gd")

const BUS := "XatRecord"
const MEDIA_DIR := "user://media/"
const MAX_MS := 5 * 60 * 1000
const MIC_GAIN_DB := 12.0 # ganancia de captura del micrófono (+12 dB)
const VOICE_RATE := 16000 # Hz de salida (voz)
const VOICE_CHANNELS := 1

var is_recording := false

var _effect: AudioEffectRecord = null
var _player: AudioStreamPlayer = null
var _start_ms := 0
var _path := ""
var _bus_idx := -1
var _analyzer_idx := -1
var _thread: Thread = null
var _job := {}

func _ready() -> void:
	_setup_bus()

# No dejar un thread de encode huérfano al salir.
func _exit_tree() -> void:
	if _thread != null and _thread.is_active():
		_thread.wait_to_finish()
	_thread = null

func _setup_bus() -> void:
	var idx = AudioServer.get_bus_index(BUS)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS)
	# El micrófono no debe salir por los parlantes (feedback). El efecto de la
	# bus captura la señal antes del control de volumen.
	AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(idx, -80.0)
	AudioServer.set_bus_mute(idx, false)
	if AudioServer.get_bus_effect_count(idx) == 0:
		_effect = AudioEffectRecord.new()
		_effect.format = AudioStreamSample.FORMAT_16_BITS
		AudioServer.add_bus_effect(idx, _effect)
	else:
		_effect = AudioServer.get_bus_effect(idx, 0) as AudioEffectRecord
	_bus_idx = idx
	# Analizador de espectro para la forma de onda en vivo: sólo mide la señal
	# (no altera lo grabado). Se reutiliza si ya existe en la bus.
	_analyzer_idx = -1
	for i in range(AudioServer.get_bus_effect_count(idx)):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectSpectrumAnalyzer:
			_analyzer_idx = i
	if _analyzer_idx < 0:
		var an = AudioEffectSpectrumAnalyzer.new()
		an.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_512
		AudioServer.add_bus_effect(idx, an)
		_analyzer_idx = AudioServer.get_bus_effect_count(idx) - 1

# Amplitud 0..1 del micrófono (banda de voz) para la onda en vivo; -1 si no hay
# dato. No se inventa onda (regla de honestidad de docs/ui.md).
func level() -> float:
	if not is_recording or _analyzer_idx < 0:
		return -1.0
	var inst = AudioServer.get_bus_effect_instance(_bus_idx, _analyzer_idx)
	if inst == null or not (inst is AudioEffectSpectrumAnalyzerInstance):
		return -1.0
	var m = inst.get_magnitude_for_frequency_range(200.0, 2400.0)
	var mag = max(m.x, m.y)
	if mag <= 0.0:
		return 0.0
	return clamp(sqrt(mag) * 2.0, 0.0, 1.0)

func available() -> bool:
	return _effect != null and AudioServer.get_bus_index(BUS) >= 0

func start() -> bool:
	if is_recording or _effect == null:
		return false
	if not available():
		emit_signal("recording_failed", "sin-microfono")
		return false
	var d = Directory.new()
	if not d.dir_exists(MEDIA_DIR):
		d.make_dir_recursive(MEDIA_DIR)
	_path = MEDIA_DIR + "voz_%d.wav" % OS.get_ticks_msec()
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = BUS
	# Ganancia de captura: el mic crudo llega muy bajo. El bus va mudo a Master
	# (sin feedback), así que amplificar acá sólo sube lo que captura el efecto.
	_player.volume_db = MIC_GAIN_DB
	add_child(_player)
	_player.play()
	_effect.set_recording_active(true)
	_start_ms = OS.get_ticks_msec()
	is_recording = true
	emit_signal("recording_started")
	return true

# Detiene la captura y lanza el encode en un Thread. Devuelve {path, duration_ms,
# mime, pending=true} inmediatamente; `recording_finished(path, ms, bytes)` llega
# cuando el thread termina de comprimir y guardar. `discard=true` descarta.
func stop(p_discard: bool = false) -> Dictionary:
	if not is_recording:
		return {}
	is_recording = false
	_effect.set_recording_active(false)
	if _player != null:
		_player.stop()
		_player.queue_free()
		_player = null
	var duration_ms = int(OS.get_ticks_msec() - _start_ms)
	var sample = _effect.get_recording()
	if p_discard or sample == null:
		return {}
	# Normaliza el mic (llega muy bajo) y pasa el PCM crudo al thread de encode.
	var pcm: PoolByteArray = sample.data if sample.format == AudioStreamSample.FORMAT_16_BITS else PoolByteArray()
	var channels = 2 if sample.stereo else 1
	var rate = int(sample.mix_rate)
	pcm = normalize_pcm16(pcm)
	_job = {
		"pcm": pcm,
		"channels": channels,
		"rate": rate,
		"path": _path,
		"duration_ms": duration_ms,
	}
	_start_encode_thread()
	return {"path": _path, "duration_ms": duration_ms, "mime": "audio/wav", "pending": true}

func _start_encode_thread() -> void:
	_thread = Thread.new()
	var err = _thread.start(self, "_encode_worker", _job)
	if err != OK:
		# Sin thread: cae al encode sincrónico (peor latencia, pero no pierde voz).
		_thread = null
		call_deferred("_finish_encode", _encode_pcm(_job))

# Corre en el thread de encode: SOLO computa (downmix + ADPCM). No toca el
# filesystem ni el árbol (no son thread-safe en Godot 3); el guardado ocurre en
# el hilo principal, en _finish_encode.
func _encode_worker(p_job) -> Dictionary:
	return _encode_pcm(p_job)

# Puro: downmix+remuestreo a voz, ADPCM y armado del WAV (sin escribir).
func _encode_pcm(p_job: Dictionary) -> Dictionary:
	var pcm: PoolByteArray = p_job["pcm"]
	if pcm.empty():
		return {"ok": false, "reason": "vacio"}
	var mono = Media.downmix_resample(pcm, int(p_job["channels"]), int(p_job["rate"]), VOICE_RATE)
	var enc = Adpcm.encode(mono, VOICE_CHANNELS, VOICE_RATE)
	var wav = Media.build_wav_adpcm(enc)
	return {"ok": true, "wav": wav, "path": str(p_job["path"]), "duration_ms": int(p_job["duration_ms"]), "bytes": wav.size()}

# Vuelve al hilo principal: escribe el archivo y emite el resultado.
func _finish_encode(p_res: Dictionary) -> void:
	if _thread != null and _thread.is_active():
		_thread.wait_to_finish()
	_thread = null
	_job = {}
	if not p_res.get("ok", false):
		emit_signal("recording_failed", str(p_res.get("reason", "guardar")))
		return
	var f = File.new()
	if f.open(str(p_res["path"]), File.WRITE) != OK:
		emit_signal("recording_failed", "guardar")
		return
	f.store_buffer(p_res["wav"])
	f.close()
	emit_signal("recording_finished", str(p_res["path"]), int(p_res["duration_ms"]), int(p_res.get("bytes", 0)))

# Lógica pura (testeable): amplifica PCM 16-bit LE al pico objetivo, con tope de
# ganancia. Devuelve el mismo buffer si es silencio o ya está fuerte.
static func normalize_pcm16(p_data: PoolByteArray, p_target: float = 0.85, p_max_gain: float = 30.0) -> PoolByteArray:
	var d := p_data
	var n = d.size() / 2
	if n == 0:
		return d
	var peak := 0
	var i := 0
	while i < n:
		var v = d[i * 2] | (d[i * 2 + 1] << 8)
		if v >= 32768:
			v -= 65536
		if v < 0:
			v = -v
		if v > peak:
			peak = v
		i += 1
	if peak == 0:
		return d # silencio digital: nada que amplificar
	var gain := min((p_target * 32767.0) / float(peak), p_max_gain)
	if gain <= 1.0:
		return d
	i = 0
	while i < n:
		var s = d[i * 2] | (d[i * 2 + 1] << 8)
		if s >= 32768:
			s -= 65536
		var a = int(round(s * gain))
		a = int(clamp(a, -32768, 32767))
		if a < 0:
			a += 65536
		d[i * 2] = a & 0xFF
		d[i * 2 + 1] = (a >> 8) & 0xFF
		i += 1
	return d

func elapsed_ms() -> int:
	return int(OS.get_ticks_msec() - _start_ms) if is_recording else 0

func cancel() -> void:
	stop(true)
