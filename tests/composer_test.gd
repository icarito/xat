extends SceneTree

# Composer rediseñado (docs/input-bar-design.md): Enter vs Shift+Enter en
# escritorio/celular, morph del botón cola mic<->enviar y máquina de estados del
# gesto de voz (cancelar vs bloquear). Determinista y headless.

var _fail := 0
var _sent := []
var _toggles := []
var _cancels := 0

func _on_msg(p_peer, p_text) -> void:
	_sent.append([p_peer, p_text])

func _on_toggle(p_peer, p_start) -> void:
	_toggles.append(p_start)

func _on_cancel(_p_peer) -> void:
	_cancels += 1

func _enter(p, p_shift: bool, p_ctrl: bool) -> void:
	var e = InputEventKey.new()
	e.scancode = KEY_ENTER
	e.pressed = true
	e.shift = p_shift
	e.control = p_ctrl
	e.echo = false
	p._on_input_event(e)

func _init():
	var CP = load("res://addons/xat_xmpp/ui/chat_panel.gd")
	var IconButton = load("res://addons/xat_xmpp/ui/icon_button.gd")
	var Waveform = load("res://addons/xat_xmpp/ui/waveform.gd")
	var root = get_root()

	# --- Widgets nuevos ---
	var ib = IconButton.new()
	root.add_child(ib)
	ib.setup("mic", 48, Color(1, 1, 1), "t")
	check(ib.glyph == "mic" and ib.rect_min_size == Vector2(48, 48), "icon_button: setup")
	ib.set_glyph("send")
	check(ib.glyph == "send", "icon_button: cambia glifo")

	var wv = Waveform.new()
	root.add_child(wv)
	wv.rect_size = Vector2(120, 24)
	wv.push(0.5)
	wv.push(1.5)
	check(wv._samples.size() == 2 and wv._samples[1] == 1.0, "waveform: clamp y push")
	for i in range(Waveform.CAP + 10):
		wv.push(0.2)
	check(wv._samples.size() == Waveform.CAP, "waveform: buffer circular topado")
	wv.clear()
	check(wv._samples.empty(), "waveform: clear")
	ib.free()
	wv.free()

	# --- Recorder: la bus de grabación monta el analizador y no inventa nivel ---
	var Rec = load("res://addons/xat_xmpp/xmpp/recorder.gd")
	var rec = Rec.new()
	root.add_child(rec)
	check(rec.level() == -1.0, "recorder: nivel -1 sin grabar")
	rec.free()

	var p = CP.new()
	root.add_child(p)
	p.connect("message_submitted", self, "_on_msg")
	p.connect("voice_toggle", self, "_on_toggle")
	p.connect("voice_cancel", self, "_on_cancel")
	p._mobile_override = 0
	p.set_peer("a@h")

	# --- Morph del botón cola ---
	check(p._tail_mode == "mic", "vacío: tail micrófono")
	p._input.text = "hola"
	p._update_tail()
	check(p._tail_mode == "send", "con texto: tail enviar")
	p._input.text = "   "
	p._update_tail()
	check(p._tail_mode == "mic", "sólo espacios: tail micrófono")
	p._input.text = ""

	# --- Enter vs Shift+Enter (escritorio) ---
	p._input.text = "uno"
	p._fit_input()
	_enter(p, false, false)
	check(_sent.size() == 1 and _sent[0][1] == "uno", "escritorio: Enter envía")
	check(p._input.text == "", "escritorio: Enter limpia el campo")
	p._input.text = "dos"
	_enter(p, true, false)
	check(_sent.size() == 1, "escritorio: Shift+Enter NO envía")
	p._input.text = "tres"
	_enter(p, false, true)
	check(_sent.size() == 2 and _sent[1][1] == "tres", "escritorio: Ctrl+Enter envía")

	# --- Móvil: Enter inserta salto, no envía ---
	p._mobile_override = 1
	p._input.text = "cuatro"
	_enter(p, false, false)
	check(_sent.size() == 2, "móvil: Enter NO envía")
	p._mobile_override = 0
	p._input.text = ""
	p._update_tail()

	# --- Gesto táctil: tap corto -> grabación bloqueada (accesible) ---
	_toggles.clear()
	_cancels = 0
	p.set_recording(false, 0)
	p._gesture_press(0, Vector2(100, 100))
	check(p._rec_phase == "armed", "tap táctil: fase armed")
	p._gesture_release()
	check(p._rec_phase == "locked" and p._recording, "tap corto: grabación bloqueada")
	check(_toggles.size() == 1 and _toggles[0] == true, "tap: voice_toggle(true)")
	check(p._tail_mode == "send" and p._rec_trash.visible, "bloqueado: tail enviar + papelera")
	# Tap en el tail mientras está bloqueado = enviar la nota.
	p._gesture_press(-2, Vector2(100, 100))
	check(_toggles.size() == 2 and _toggles[1] == false, "bloqueado: tap tail envía")
	p.set_recording(false, 0)
	check(p._rec_phase == "idle" and not p._recording, "volver a idle")

	# --- Escritorio: clic de mouse -> grabación bloqueada directa ---
	_toggles.clear()
	p._gesture_press(-2, Vector2(100, 100))
	check(p._rec_phase == "armed_click", "mouse: fase armed_click (sin mantener)")
	p._gesture_release()
	check(p._rec_phase == "locked" and p._recording, "mouse: clic bloquea la grabación")
	p.set_recording(false, 0)

	# --- Gesto táctil: mantener -> held; soltar con duración -> enviar ---
	_toggles.clear()
	_cancels = 0
	p._gesture_press(0, Vector2(100, 100))
	p._on_arm_timeout()
	check(p._rec_phase == "held" and p._recording, "hold: fase held")
	check(not p._rec_trash.visible, "held: sin papelera aún")
	p._rec_started_ms = OS.get_ticks_msec() - 1000
	p._gesture_release()
	check(_toggles.size() == 2 and _toggles[1] == false, "hold soltar: envía")
	p.set_recording(false, 0)

	# --- Gesto táctil: demasiado corto -> descartar ---
	_toggles.clear()
	_cancels = 0
	p._gesture_press(0, Vector2(100, 100))
	p._on_arm_timeout()
	p._rec_started_ms = OS.get_ticks_msec() - 100
	p._gesture_release()
	check(_cancels == 1 and _toggles.size() == 1, "demasiado corto: cancela")
	p.set_recording(false, 0)

	# --- Gesto táctil: deslizar ↑ >= LOCK -> bloquear ---
	_toggles.clear()
	p._gesture_press(0, Vector2(100, 100))
	p._on_arm_timeout()
	p._gesture_move(Vector2(100, 100 - CP.LOCK_THRESHOLD - 5))
	check(p._rec_phase == "locked", "deslizar ↑: bloquea")
	check(p._rec_trash.visible, "bloqueado: papelera visible")
	p.set_recording(false, 0)

	# --- Gesto táctil: deslizar ← >= CANCEL -> cancelar armado ---
	_toggles.clear()
	_cancels = 0
	p._gesture_press(0, Vector2(100, 100))
	p._on_arm_timeout()
	p._gesture_move(Vector2(100 - CP.CANCEL_THRESHOLD - 5, 100))
	check(p._rec_phase == "cancel" and p._rec_cancel, "deslizar ←: cancelar armado")
	p._gesture_release()
	check(_cancels == 1, "soltar en cancelar: descarta (no envía)")
	p.set_recording(false, 0)

	# --- Volver desde cancelar reanuda held ---
	_toggles.clear()
	_cancels = 0
	p._gesture_press(0, Vector2(100, 100))
	p._on_arm_timeout()
	p._gesture_move(Vector2(100 - CP.CANCEL_THRESHOLD - 5, 100))
	p._gesture_move(Vector2(100, 100))
	check(p._rec_phase == "held" and not p._rec_cancel, "volver del cancelar: reanuda")
	p.set_recording(false, 0)

	# --- Modo sala: adjuntos y voz deshabilitados (sin regresión) ---
	p.set_room("sala@conference.h", "yo", [])
	check(not p._attach_enabled and not p._voice_enabled, "sala: adjuntos/voz off")
	check(p._attach_btn.disabled, "sala: botón adjuntar deshabilitado")
	_toggles.clear()
	p._gesture_press(-2, Vector2(100, 100))
	p._gesture_release()
	check(_toggles.empty() and p._rec_phase == "idle", "sala: tail vacío no graba")
	p.set_peer("a@h")
	check(p._attach_enabled and not p._attach_btn.disabled, "1:1: adjuntos habilitados")

	# --- Inset inferior de safe area ---
	p.set_bottom_inset(24)
	check(p._compose.get_constant("margin_bottom") == 30, "inset inferior suma al margen base 6")

	p.free()
	if _fail == 0:
		print("COMPOSER_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
