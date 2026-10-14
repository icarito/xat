extends Control

signal canceled
signal completed(outcome)
# Aditiva (X1.1): el usuario pidió reintentar un paso que falló. La app decide
# cómo re-disparar la conexión; el splash sólo informa el motivo del fallo.
signal retry_requested(step_id)

const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const Orb = preload("res://addons/xat_xmpp/ui/agent_orb.gd")
const CONNECT_TIMEOUT := 15.0
const FADE_SECONDS := 0.32
const TOUCH_MIN := 44

# Pasos REALES de conexión (X1.1). El orden define el barrido del anillo.
const STEP_ORDER := ["tls", "sasl", "roster", "mam", "fleet"]
const STEP_LABELS := {
	"tls": "Cifrado TLS",
	"sasl": "Sesión SASL",
	"roster": "Contactos (roster)",
	"mam": "Historial (MAM)",
	"fleet": "Snapshot de flota",
}

var timeout_seconds := CONNECT_TIMEOUT
var state := "idle"
# Aditiva (X1.1): si es true, show_success() espera a MAM antes de entrar y
# ofrece "Entrar sin esperar el historial". Por defecto false para no romper el
# arranque actual (main.gd no la activa todavía).
var wait_for_history := false
# Estado por paso: id -> {status: pending|active|done|failed, reason: String}.
var steps := {}
var _orb
var _status: Label
var _cancel: Button
var _skip_history: Button
var _steps_box: VBoxContainer
var _step_rows := {}
var _timer: Timer
var _tween: Tween
var _finished := false
var _activity := "processing"
var _session
var _fleet_jid := ""
var _fleet_node := ""

func _init():
	name = "StartupSplash"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	var bg := ColorRect.new()
	bg.color = P.BG0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGN_CENTER
	content.add_constant_override("separation", 12)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(content)
	_orb = Orb.new()
	_orb.rect_min_size = Vector2(280, 302)
	_orb.set_state({"activity": "processing"})
	content.add_child(_orb)
	_status = Label.new()
	_status.text = "Conectando…"
	_status.align = Label.ALIGN_CENTER
	_status.add_color_override("font_color", P.TEXT)
	content.add_child(_status)

	# Lista de pasos reales de conexión.
	_steps_box = VBoxContainer.new()
	_steps_box.add_constant_override("separation", 4)
	_steps_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(_steps_box)
	for id in STEP_ORDER:
		steps[id] = {"status": "pending", "reason": ""}
		_steps_box.add_child(_make_step(id))

	_skip_history = Button.new()
	_skip_history.text = "Entrar sin esperar el historial"
	_skip_history.rect_min_size = Vector2(0, TOUCH_MIN)
	_skip_history.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_skip_history.visible = false
	_skip_history.connect("pressed", self, "_on_skip_history")
	content.add_child(_skip_history)

	_cancel = Button.new()
	_cancel.text = "Cancelar"
	_cancel.rect_min_size = Vector2(0, TOUCH_MIN)
	_cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cancel.connect("pressed", self, "_on_cancel")
	content.add_child(_cancel)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.connect("timeout", self, "_on_timeout")
	add_child(_timer)
	_tween = Tween.new()
	add_child(_tween)

# --- API aditiva de pasos (X1.1). main.gd/C2 la usará; los tests la ejercen. ---

# Fija el estado de un paso: pending | active | done | failed (+ motivo en failed).
# Honestidad P1: sólo "done" pinta el ítem en verde y avanza el anillo.
func set_step(p_id: String, p_status: String, p_reason := "") -> void:
	if not steps.has(p_id):
		return
	var st: Dictionary = steps[p_id]
	st["status"] = p_status
	if p_status == "failed":
		st["reason"] = str(p_reason) if str(p_reason) != "" else "Error"
	else:
		st["reason"] = ""
	_apply_step(p_id)
	if p_status == "active":
		_status.text = "%s…" % str(STEP_LABELS[p_id])
	_refresh_orb()

func fail_step(p_id: String, p_reason := "") -> void:
	set_step(p_id, "failed", p_reason)

func step_status(p_id: String) -> String:
	return str(steps.get(p_id, {}).get("status", ""))

func steps_done() -> int:
	return _done_count()

# Enlaza el splash a una sesión real y traduce sus señales en pasos. Aditiva:
# main.gd puede llamar bind_session(session, fleet_jid, fleet_node).
func bind_session(p_session, p_fleet_jid := "", p_fleet_node := "") -> void:
	if p_session == null:
		return
	_session = p_session
	_fleet_jid = str(p_fleet_jid)
	_fleet_node = str(p_fleet_node)
	_connect_signal(p_session, "state_changed", "_on_session_state")
	_connect_signal(p_session, "roster_changed", "_on_roster_changed")
	_connect_signal(p_session, "history_fetched", "_on_history_fetched")
	_connect_signal(p_session, "auth_failed", "_on_auth_failed")
	_connect_signal(p_session, "pubsub_items_received", "_on_pubsub_items")

func start() -> void:
	if _finished:
		return
	state = "connecting"
	_activity = "processing"
	_status.text = "Conectando…"
	_skip_history.visible = false
	for id in STEP_ORDER:
		steps[id]["status"] = "pending"
		steps[id]["reason"] = ""
		_apply_step(id)
	set_step("tls", "active")
	_timer.start(timeout_seconds)
	modulate.a = 0.0
	_tween.interpolate_property(self, "modulate:a", 0.0, 1.0, 0.38, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	_tween.interpolate_property(_orb, "rect_scale", Vector2(0.82, 0.82), Vector2.ONE, 0.48, Tween.TRANS_BACK, Tween.EASE_OUT)
	_tween.start()

func show_success() -> void:
	if _finished:
		return
	state = "success"
	_timer.stop()
	# CONNECTED confirma TLS + SASL (libstrophe ya negoció y autenticó).
	if step_status("tls") != "failed":
		set_step("tls", "done")
	if step_status("sasl") != "failed":
		set_step("sasl", "done")
	if step_status("roster") == "pending":
		set_step("roster", "active")
	_activity = "available"
	_orb.set_connected(true)
	_refresh_orb()
	_cancel.visible = false
	_status.text = "Conectado"
	# CONNECTED may arrive before the entrance tween finishes.
	_tween.stop_all()
	modulate.a = 1.0
	# X1.1: si faltan pasos de fondo (MAM) y la app pidió esperarlos, mostrar la
	# salida "sin esperar" en vez de cortar el splash.
	if wait_for_history and step_status("mam") != "done":
		_skip_history.visible = true
		return
	_finish_after(0.85, "connected")

func cancel() -> void:
	if _finished:
		return
	_finished = true
	state = "canceled"
	_timer.stop()
	emit_signal("canceled")

func finish(p_outcome: String, p_status := "") -> void:
	if _finished:
		return
	_finished = true
	state = p_outcome
	_timer.stop()
	if p_status != "":
		_status.text = p_status
	_apply_outcome_steps(p_outcome, p_status)
	_tween.stop_all()
	_tween.interpolate_property(self, "modulate:a", modulate.a, 0.0, FADE_SECONDS, Tween.TRANS_CUBIC, Tween.EASE_IN)
	_tween.start()
	yield(get_tree().create_timer(FADE_SECONDS), "timeout")
	emit_signal("completed", p_outcome)

func _finish_after(p_delay: float, p_outcome: String) -> void:
	_finished = true
	_tween.stop_all()
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = max(p_delay, 0.001)
	timer.connect("timeout", self, "_on_finish_delay", [p_outcome, timer])
	add_child(timer)
	timer.start()

func _on_finish_delay(p_outcome: String, p_timer: Timer) -> void:
	p_timer.queue_free()
	_tween.interpolate_property(self, "modulate:a", modulate.a, 0.0, FADE_SECONDS, Tween.TRANS_CUBIC, Tween.EASE_IN)
	_tween.start()
	yield(get_tree().create_timer(FADE_SECONDS), "timeout")
	state = p_outcome
	emit_signal("completed", p_outcome)

func _on_cancel() -> void:
	cancel()

func _on_timeout() -> void:
	finish("timeout")

func _on_skip_history() -> void:
	if _finished:
		return
	_skip_history.visible = false
	_status.text = "Entrando…"
	_finish_after(0.0, "connected")

func _on_retry(p_id: String) -> void:
	if not steps.has(p_id):
		return
	set_step(p_id, "active")
	if _timer.is_stopped() and not _finished:
		_timer.start(timeout_seconds)
	emit_signal("retry_requested", p_id)

# --- señales de la sesión enlazada ---

func _on_session_state(_p_state) -> void:
	if _session == null:
		return
	if _session.is_connected_to_server():
		if step_status("tls") != "done":
			set_step("tls", "done")
		if step_status("sasl") != "done":
			set_step("sasl", "done")
		if step_status("roster") == "pending":
			set_step("roster", "active")

func _on_roster_changed() -> void:
	set_step("roster", "done")

func _on_history_fetched(_p_bare, _p_rows, _p_complete) -> void:
	set_step("mam", "done")
	if state == "success" and not _finished and not _skip_history.visible:
		_finish_after(0.0, "connected")

func _on_auth_failed() -> void:
	# Un SASL ya confirmado no se pinta como fallido por una señal tardía.
	if step_status("sasl") != "done":
		fail_step("sasl", "Usuario o contraseña incorrectos")

func _on_pubsub_items(_p_from, p_node, _p_items) -> void:
	if _fleet_node != "" and str(p_node) == _fleet_node:
		set_step("fleet", "done")

# --- UI de pasos ---

func _make_step(p_id: String) -> Control:
	var box := VBoxContainer.new()
	box.add_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ind := Label.new()
	ind.rect_min_size = Vector2(24, 0)
	ind.align = Label.ALIGN_CENTER
	row.add_child(ind)
	var title := Label.new()
	title.text = str(STEP_LABELS[p_id])
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var retry := Button.new()
	retry.text = "Reintentar"
	retry.rect_min_size = Vector2(0, TOUCH_MIN)
	retry.visible = false
	retry.connect("pressed", self, "_on_retry", [p_id])
	row.add_child(retry)
	box.add_child(row)
	var reason := Label.new()
	reason.autowrap = true
	reason.visible = false
	box.add_child(reason)
	_step_rows[p_id] = {"row": row, "indicator": ind, "title": title, "retry": retry, "reason": reason}
	_apply_step(p_id)
	return box

func _apply_step(p_id: String) -> void:
	if not _step_rows.has(p_id):
		return
	var r: Dictionary = _step_rows[p_id]
	var st: Dictionary = steps[p_id]
	var ind: Label = r["indicator"]
	var title: Label = r["title"]
	var retry: Button = r["retry"]
	var reason: Label = r["reason"]
	match str(st["status"]):
		"done":
			ind.text = "✓"
			ind.add_color_override("font_color", P.OK)
			title.add_color_override("font_color", P.TEXT)
			retry.visible = false
			reason.visible = false
		"failed":
			ind.text = "×"
			ind.add_color_override("font_color", P.ERROR)
			title.add_color_override("font_color", P.ERROR)
			reason.text = str(st["reason"])
			reason.add_color_override("font_color", P.ERROR)
			reason.visible = true
			retry.visible = true
		"active":
			ind.text = "●"
			ind.add_color_override("font_color", P.PROCESSING)
			title.add_color_override("font_color", P.TEXT)
			retry.visible = false
			reason.visible = false
		_:
			ind.text = "○"
			ind.add_color_override("font_color", P.TEXT_DIM)
			title.add_color_override("font_color", P.TEXT_DIM)
			retry.visible = false
			reason.visible = false

func _done_count() -> int:
	var n := 0
	for id in STEP_ORDER:
		if step_status(id) == "done":
			n += 1
	return n

func _refresh_orb() -> void:
	_orb.set_state({"activity": _activity, "context": {"used": _done_count(), "max": STEP_ORDER.size()}})

func _active_step_id() -> String:
	for id in STEP_ORDER:
		if step_status(id) == "active":
			return id
	for id in STEP_ORDER:
		if step_status(id) == "pending":
			return id
	return ""

func _apply_outcome_steps(p_outcome: String, p_status: String) -> void:
	var reason := str(p_status)
	match p_outcome:
		"auth_failed":
			set_step("sasl", "failed", reason if reason != "" else "Usuario o contraseña incorrectos")
		"error", "timeout":
			var id := _active_step_id()
			if id != "":
				var fallback := "No se pudo conectar" if p_outcome == "error" else "Tiempo de espera agotado"
				set_step(id, "failed", reason if reason != "" else fallback)

func _connect_signal(p_obj, p_sig: String, p_method: String) -> void:
	if p_obj.has_signal(p_sig) and not p_obj.is_connected(p_sig, self, p_method):
		p_obj.connect(p_sig, self, p_method)
