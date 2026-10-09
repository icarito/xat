extends Node

# Grabador de voz: micro -> bus "XatRecord" con AudioEffectRecord -> WAV.
# Godot 3 no expone un encoder Opus; se guarda PCM WAV (formato que el propio
# motor reproduce con AudioStreamSample). Un grabador por sesión.
#
# El bus de grabación se manda a Master con el volumen al mínimo: el efecto
# captura ANTES de aplicar el volumen, así se graba sin realimentar el micrófono
# a los parlantes. Requiere `audio/driver/enable_input=true` (project.godot).

signal recording_started()
signal recording_finished(path, duration_ms)
signal recording_failed(reason)

const Media = preload("res://addons/xat_xmpp/xmpp/media.gd")

const BUS := "XatRecord"
const MEDIA_DIR := "user://media/"
const MAX_MS := 5 * 60 * 1000

var is_recording := false

var _effect: AudioEffectRecord = null
var _player: AudioStreamPlayer = null
var _start_ms := 0
var _path := ""

func _ready() -> void:
	_setup_bus()

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
	add_child(_player)
	_player.play()
	_effect.set_recording_active(true)
	_start_ms = OS.get_ticks_msec()
	is_recording = true
	emit_signal("recording_started")
	return true

# Detiene y guarda. `discard=true` descarta. Devuelve
# {path, duration_ms, mime} o {} si no había grabación.
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
	if sample.save_to_wav(_path) != OK:
		emit_signal("recording_failed", "guardar")
		return {}
	emit_signal("recording_finished", _path, duration_ms)
	return {"path": _path, "duration_ms": duration_ms, "mime": "audio/wav"}

func elapsed_ms() -> int:
	return int(OS.get_ticks_msec() - _start_ms) if is_recording else 0

func cancel() -> void:
	stop(true)
