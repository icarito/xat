extends PanelContainer

# Panel de chat: burbujas agrupadas por remitente, estado de chat, chips de
# acciones (comandos ad-hoc / quick responses) y composer multilínea. Mantiene
# el modelo de mensajes para plegar correcciones 0308 y marcas de entrega 0184.

signal back_requested() # vista de un panel (móvil): volver al roster
signal message_submitted(bare, text)
signal action_selected(bare, item)
signal quick_selected(bare, value)
signal chat_state_sent(bare, state)

const Palette = preload("res://addons/xat_xmpp/ui/palette.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")
const Bubble = preload("res://addons/xat_xmpp/ui/bubble.gd")
const LocalTime = preload("res://addons/xat_xmpp/ui/localtime.gd")
const ToolCard = preload("res://addons/xat_xmpp/ui/tool_card.gd")
const ApprovalCard = preload("res://addons/xat_xmpp/ui/approval_card.gd")
const Shimmer = preload("res://addons/xat_xmpp/ui/fx/shimmer.gd")

const MAX_LINES := 6
const MAX_BUBBLES := 200  # más viejas se liberan (el modelo _messages queda completo)
const NEAR_PX := 80.0
const WEEKDAYS := ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"]
const MONTHS := ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]

var _peer := ""
var _messages := []
var _bubbles := []  # burbujas de _messages[_first:]
var _first := 0
var _limit := MAX_BUBBLES
var _last_day := ""
var _pinned := true  # el usuario está pegado al final (se actualiza al scrollear)
var _unseen := 0
var _unread_idx := -1
var _unread_node = null
var _skip_clear := false
var _hold := false  # scroll al marcador pendiente: no ir al final todavía
var _pending_actions = null
var _card = null  # card de aprobación activa (ApprovalCard)
var _card_hook = null  # hook que llegó antes que su mensaje
var _tool = null  # última tool card (ToolCard)
var _break := false  # una tool card corta el grupo de burbujas
var _typing := ""
var _thinking := false
var header_slot: HBoxContainer  # a la derecha del título (mini-orbe, etc.)

var _title: Label
var back_button: Button
var _scroll: ScrollContainer
var _list: VBoxContainer
var _state: RichTextLabel
var _actions: HBoxContainer  # botones de la card de aprobación activa
var _input: TextEdit
var _hint: Label
var _content: Control
var _jump: Button
var _more: Button
var _anim: Timer  # fuerza redibujo del shimmer (low_processor_mode lo congela)

func _init() -> void:
	name = "ChatPanel"
	rect_min_size = Vector2(360, 0)
	_build()

func _build() -> void:
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 0)
	# Cabecera con el peer.
	var head = PanelContainer.new()
	head.add_stylebox_override("panel", XatTheme.with_border(XatTheme.box(Palette.BG1, 0, 16, 12), Palette.LINE))
	_title = Label.new()
	_title.text = "—"
	_title.add_font_override("font", XatTheme.font(Palette.FONT_BOLD, Palette.FONT_SIZE + 2))
	var hh = HBoxContainer.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	back_button = Button.new()
	back_button.text = "←"
	back_button.flat = true
	back_button.visible = false
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.rect_min_size = Vector2(40, 0)
	back_button.connect("pressed", self, "emit_signal", ["back_requested"])
	hh.add_child(back_button)
	hh.add_child(_title)
	header_slot = HBoxContainer.new()
	hh.add_child(header_slot)
	head.add_child(hh)
	v.add_child(head)
	# Log de burbujas.
	_scroll = ScrollContainer.new()
	_scroll.scroll_horizontal_enabled = false
	_scroll.add_stylebox_override("bg", XatTheme.box(Palette.BG0, 0, 0, 0))
	var m = MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE # deja pasar el arrastre táctil al ScrollContainer
	for side in ["left", "right", "top", "bottom"]:
		m.add_constant_override("margin_" + side, 14)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_constant_override("separation", 0)
	_content = m
	var top = VBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_constant_override("separation", 0)
	_more = _pill_button("Cargar anteriores")
	_more.visible = false
	_more.connect("pressed", self, "_on_more")
	top.add_child(_more)
	top.add_child(_list)
	m.add_child(top)
	_scroll.add_child(m)
	_scroll.get_v_scrollbar().connect("value_changed", self, "_on_scrolled")
	# Pila: el log y, encima, el botón flotante "ir al final".
	var stack = Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(_scroll)
	_scroll.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_jump = _pill_button("")
	_jump.align = Button.ALIGN_RIGHT
	_jump.visible = false
	_jump.anchor_left = 1.0
	_jump.anchor_right = 1.0
	_jump.anchor_top = 1.0
	_jump.anchor_bottom = 1.0
	_jump.margin_left = -84
	_jump.margin_right = -14
	_jump.margin_top = -54
	_jump.margin_bottom = -14
	_jump.connect("pressed", self, "_on_jump")
	_jump.connect("draw", self, "_draw_jump")
	stack.add_child(_jump)
	v.add_child(stack)
	# Pie: estado, chips y composer sobre BG1.
	var foot = PanelContainer.new()
	foot.add_stylebox_override("panel", XatTheme.box(Palette.BG1, 0, 12, 8))
	var f = VBoxContainer.new()
	f.add_constant_override("separation", 6)
	_state = RichTextLabel.new()
	_state.bbcode_enabled = true
	_state.fit_content_height = true
	_state.scroll_active = false
	_state.visible = false
	_state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_state.custom_effects = [Shimmer.new()]
	_state.add_color_override("default_color", Palette.TEXT_DIM)
	_state.add_font_override("normal_font", XatTheme.font(Palette.FONT_REGULAR, Palette.FONT_SIZE - 2))
	f.add_child(_state)
	_anim = Timer.new()
	_anim.wait_time = 0.05
	_anim.connect("timeout", _state, "update")
	add_child(_anim)
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 8)
	_input = TextEdit.new()
	_input.wrap_enabled = true
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.size_flags_vertical = Control.SIZE_SHRINK_END
	_input.connect("gui_input", self, "_on_input_event")
	_input.connect("text_changed", self, "_fit_input")
	_hint = Label.new()
	_hint.text = "Escribe un mensaje…"
	_hint.add_color_override("font_color", Palette.TEXT_DIM)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.rect_position = Vector2(15, 10)
	_input.add_child(_hint)
	h.add_child(_input)
	var send = Button.new()
	send.connect("draw", self, "_draw_send", [send])
	send.rect_min_size = Vector2(44, 44)
	send.size_flags_vertical = Control.SIZE_SHRINK_END
	for st in ["normal", "hover", "pressed", "focus"]:
		var s = XatTheme.box(Palette.USER if st != "hover" else Palette.USER.lightened(0.15), 22, 0, 0)
		send.add_stylebox_override(st, s)
	send.connect("pressed", self, "_on_send")
	h.add_child(send)
	f.add_child(h)
	foot.add_child(f)
	v.add_child(foot)
	add_child(v)
	_fit_input()

# Flecha hacia arriba dibujada (la fuente no trae ↑).
func _draw_send(p_btn: Button) -> void:
	var c = p_btn.rect_size / 2
	p_btn.draw_polyline(PoolVector2Array([c + Vector2(-7, 2), c + Vector2(0, -6), c + Vector2(7, 2)]), Palette.TEXT, 2.5, true)
	p_btn.draw_line(c + Vector2(0, -5), c + Vector2(0, 8), Palette.TEXT, 2.5, true)

# Al elegir un chat se puede escribir de inmediato (deferred: el panel puede
# estar recién visible y aún no aceptar foco).
func focus_composer() -> void:
	_input.call_deferred("grab_focus")

func set_peer(p_bare: String) -> void:
	_peer = p_bare
	_title.text = p_bare.split("@")[0]
	_title.hint_tooltip = p_bare
	_messages = []
	_pending_actions = null
	_clear_actions()
	_clear_tools()
	_reset_view()
	_rebuild()

# Tras cambiar el zoom, conservar el punto de lectura: ancla el ÚLTIMO mensaje
# visible (no el primero) a su misma posición en pantalla.
func refit_scroll() -> void:
	if _pinned:
		_to_bottom()
		return
	for b in _bubbles:
		if is_instance_valid(b) and b.has_method("_fit"):
			b._fit()
	var v = _scroll.scroll_vertical
	var view_bottom = v + _scroll.rect_size.y
	var anchor = null
	var screen_y = 0.0
	for b in _bubbles:
		if is_instance_valid(b) and b.rect_position.y < view_bottom:
			anchor = b
			screen_y = b.rect_position.y - v
	if anchor == null:
		return
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	if is_instance_valid(anchor):
		_scroll.scroll_vertical = int(max(anchor.rect_position.y - screen_y, 0.0))

func deselect_all() -> void:
	for b in _bubbles:
		if is_instance_valid(b) and b.has_method("deselect"):
			b.deselect()

func set_history(p_rows: Array) -> void:
	_messages = []
	_limit = MAX_BUBBLES
	for r in p_rows:
		_messages.append({
			"from": _peer,
			"to": "",
			"body": r.get("body", ""),
			"timestamp": r.get("ts", ""),
			"direction": r.get("direction", "in"),
			"id": r.get("request_id", ""),
			"quick_responses": r.get("quick", []),
			"commands": r.get("commands", []),
		})
	_rebuild()

func _reset_view() -> void:
	_limit = MAX_BUBBLES
	_unread_idx = -1
	_unseen = 0
	_pinned = true
	_jump.visible = false

func add_message(p_rec: Dictionary) -> void:
	_messages.append(p_rec)
	# Historial (MAM) o mensajes con delay entran quietos: sin animación.
	_append_bubble(p_rec, not p_rec.get("is_mam", false) and not p_rec.get("delayed", false))
	if p_rec.has("commands") or p_rec.has("quick_responses"):
		set_actions(p_rec)

func apply_correction(p_rec: Dictionary) -> void:
	var target = p_rec.get("replace_id", "")
	for i in range(_messages.size()):
		if str(_messages[i].get("id", "")) == target:
			_messages[i]["body"] = p_rec.get("body", "")
			_messages[i]["edited"] = true
			if _bub(i) != null:
				_bub(i).refresh()
			return
	_messages.append(p_rec)
	_append_bubble(p_rec, true)

# Marca ✓✓ (XEP-0184) en la burbuja propia con ese id.
func mark_delivered(p_id: String) -> void:
	for i in range(_messages.size()):
		if str(_messages[i].get("id", "")) == p_id:
			_messages[i]["delivered"] = true
			if _bub(i) != null:
				_bub(i).refresh()
			return

func set_chat_state(p_text: String) -> void:
	_typing = p_text
	_refresh_state()

# "pensando…" mientras el agente procesa (shimmer); gana sobre el chat state.
func set_thinking(p_on: bool) -> void:
	_thinking = p_on
	_refresh_state()

func _refresh_state() -> void:
	var t = "pensando…" if _thinking else _typing
	_state.visible = t != ""
	_anim.autostart = t != ""
	if t == "":
		_anim.stop()
	elif is_inside_tree() and _anim.is_stopped():
		_anim.start()
	_state.bbcode_text = "[shimmer]%s[/shimmer]" % t if t != "" else ""

func tool_started(p_name: String, p_detail: String = "") -> void:
	if _tool != null and _tool.state == "running" and _tool.tool_name == p_name:
		_tool.set_detail(p_detail)
		return
	_tool = ToolCard.new()
	_tool.start(p_name, p_detail)
	_list.add_child(_gap_wrap(_tool))
	_break = true
	_follow()

func tool_finished(p_ok: bool = true) -> void:
	if _tool != null:
		_tool.finish(p_ok)

func _gap_wrap(p_node: Control) -> Control:
	var m = MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_constant_override("margin_top", Palette.GROUP_GAP)
	m.add_child(p_node)
	return m

func _clear_tools() -> void:
	_tool = null
	_break = false
	_card = null
	_card_hook = null
	_drop_extras()

func _drop_extras() -> void:
	_unread_node = null
	for c in _list.get_children():
		if not c is Bubble:
			_list.remove_child(c)
			c.queue_free()

# Acciones del mensaje -> card de aprobación inline bajo su burbuja.
func set_actions(p_rec: Dictionary) -> void:
	_pending_actions = p_rec
	_clear_actions()
	if p_rec.get("commands", []).empty() and p_rec.get("quick_responses", []).empty():
		return
	var card = ApprovalCard.new()
	card.set_actions(p_rec)
	card.connect("decided", self, "_on_decided")
	_card = card
	_actions = card.row
	var host = _bubble_for(str(p_rec.get("id", "")))
	if host != null:
		host.attach(card)
	else:
		_list.add_child(_gap_wrap(card))
	var h = _card_hook
	_card_hook = null
	if h != null and (str(h.get("stanzaId", "")) in ["", card.msg_id]):
		card.set_hook(h)
	_follow()

# Hook de aprobación: estado/expiración de la card activa (match por stanzaId).
func apply_approval_hook(p_hook: Dictionary) -> void:
	var sid = str(p_hook.get("stanzaId", ""))
	if _card != null and is_instance_valid(_card) and (sid == "" or _card.msg_id == "" or sid == _card.msg_id):
		_card.set_hook(p_hook)
	elif str(p_hook.get("state", "")) == "pending":
		_card_hook = p_hook

func _bubble_for(p_id: String):
	if p_id != "":
		for i in range(_messages.size()):
			if str(_messages[i].get("id", "")) == p_id:
				return _bub(i)
	return _bubbles.back() if not _bubbles.empty() else null

func _bub(i: int):
	var k = i - _first
	return _bubbles[k] if k >= 0 and k < _bubbles.size() else null

# Una card sin decidir se reemplaza por la nueva; las selladas quedan de historial.
func _clear_actions() -> void:
	if _card != null and is_instance_valid(_card) and not _card.sealed:
		_card.get_parent().remove_child(_card)
		_card.queue_free()
	_card = null
	_actions = null

func _on_decided(p_kind: String, p_value) -> void:
	if p_kind == "command":
		emit_signal("action_selected", _peer, p_value)
	else:
		emit_signal("quick_selected", _peer, str(p_value))

func _rebuild(p_settle: bool = true) -> void:
	var keep = _card if _card != null and is_instance_valid(_card) and _card.get_parent() != null else null
	if keep != null:
		keep.get_parent().remove_child(keep)
	_tool = null
	_drop_extras()
	for b in _bubbles:
		_list.remove_child(b)
		b.queue_free()
	_bubbles = []
	_first = int(max(0, _messages.size() - _limit))
	_last_day = ""
	_break = false
	for i in range(_first, _messages.size()):
		_make_bubble(i, false)
	_more.visible = _first > 0
	if keep != null:
		var host = _bubble_for(keep.msg_id)
		if host != null:
			host.attach(keep)
	if p_settle:
		if _unread_idx >= 0 and _unread_node != null:
			_to_marker()
		else:
			_to_bottom()

func _append_bubble(p_rec: Dictionary, p_new: bool) -> void:
	_make_bubble(_messages.size() - 1, p_new)
	if _pinned:
		_trim()
	if p_rec.get("direction", "in") == "out" or _pinned:
		_to_bottom()
	else:
		_unseen += 1
		_refresh_jump()

# Libera las burbujas más viejas (y sus separadores) pasado el límite.
func _trim() -> void:
	while _bubbles.size() > _limit:
		var b = _bubbles.pop_front()
		_first += 1
		while _list.get_child_count() > 0 and _list.get_child(0) != b:
			var c = _list.get_child(0)
			_list.remove_child(c)
			c.queue_free()
		_list.remove_child(b)
		b.queue_free()
	_more.visible = _first > 0

func _on_more() -> void:
	_limit += 100
	_rebuild(false)

# Crea la burbuja del mensaje i; el grupo se decide por la dirección vecina.
func _make_bubble(i: int, p_new: bool) -> void:
	var rec = _messages[i]
	var dir = rec.get("direction", "in")
	# Separador de día y marcador de no leídos cortan el grupo.
	var sep := false
	var day = LocalTime.local_iso(str(rec.get("timestamp", ""))).substr(0, 10)
	if day.length() == 10 and day != _last_day:
		_list.add_child(_pill(day_label(day, today_iso())))
		_last_day = day
		sep = true
	if _unread_idx >= 0 and i == int(max(_unread_idx, _first)):
		_unread_node = _unread_marker()
		_list.add_child(_unread_node)
		sep = true
	var prev_same = i > _first and _messages[i - 1].get("direction", "in") == dir
	var same_prev = prev_same and not _break and not sep
	if prev_same and not same_prev and _bub(i - 1) != null:
		_bub(i - 1).set_group_last(true)
	_break = false
	var last = i == _messages.size() - 1 or _messages[i + 1].get("direction", "in") != dir
	if same_prev:
		_bubbles[i - 1 - _first].set_group_last(false)
	var gap = Palette.GAP if sep else (0 if i == _first else (Palette.GAP if same_prev else Palette.GROUP_GAP))
	var b = Bubble.new()
	b.set_record(rec, last, p_new, gap, p_new and dir == "in")
	_list.add_child(b)
	_bubbles.append(b)

# Sigue al final sólo si el usuario ya estaba abajo.
func _follow() -> void:
	if _pinned:
		_to_bottom()

func _to_bottom() -> void:
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	if not _hold:
		_scroll.scroll_vertical = int(_scroll.get_v_scrollbar().max_value)

func _to_marker() -> void:
	_hold = true
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	_hold = false
	if _unread_node == null or not is_instance_valid(_unread_node):
		return
	_skip_clear = true  # llegar acá no cuenta como "leyó todo"
	_scroll.scroll_vertical = int(max(_unread_node.rect_global_position.y - _content.rect_global_position.y - 24.0, 0.0))
	_skip_clear = false

# ¿Cerca del final? value/max/page de la ScrollBar; puro, para tests.
static func near_bottom(p_value: float, p_max: float, p_page: float, p_slack: float = NEAR_PX) -> bool:
	return p_max - p_page - p_value <= p_slack

func _on_scrolled(p_value: float) -> void:
	var sb = _scroll.get_v_scrollbar()
	_pinned = near_bottom(p_value, sb.max_value, sb.page)
	if _pinned:
		_unseen = 0
		if not _skip_clear:
			_clear_unread()
	_refresh_jump()

func _refresh_jump() -> void:
	_jump.visible = not _pinned
	_jump.text = str(_unseen) if _unseen > 0 else ""

func _on_jump() -> void:
	var sb = _scroll.get_v_scrollbar()
	var tw = Tween.new()
	add_child(tw)
	tw.interpolate_property(_scroll, "scroll_vertical", _scroll.scroll_vertical, int(sb.max_value - sb.page), 0.25, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	tw.connect("tween_all_completed", tw, "queue_free")
	tw.start()

# Flecha hacia abajo + contador de mensajes sin ver en el botón flotante.
func _draw_jump() -> void:
	var c = Vector2(20, _jump.rect_size.y / 2)
	_jump.draw_polyline(PoolVector2Array([c + Vector2(-6, -2), c + Vector2(0, 5), c + Vector2(6, -2)]), Palette.TEXT, 2.5, true)
	_jump.draw_line(c + Vector2(0, -6), c + Vector2(0, 4), Palette.TEXT, 2.5, true)

# Marca "Nuevos" antes del primer no leído: índice en _messages, o negativo =
# cuántos de los últimos. Se quita al llegar al final scrolleando o al enviar.
func mark_unread_from(p_idx: int) -> void:
	if p_idx < 0:
		p_idx = int(max(0, _messages.size() + p_idx))
	if p_idx >= _messages.size():
		return
	_clear_unread()
	_unread_idx = p_idx
	var b = _bub(int(max(p_idx, _first)))
	if b == null:
		return
	_unread_node = _unread_marker()
	_list.add_child(_unread_node)
	_list.move_child(_unread_node, b.get_index())
	_to_marker()

func _clear_unread() -> void:
	_unread_idx = -1
	if _unread_node != null and is_instance_valid(_unread_node):
		_unread_node.get_parent().remove_child(_unread_node)
		_unread_node.queue_free()
	_unread_node = null

func _unread_marker() -> Control:
	var h = HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_constant_override("separation", 10)
	var lc = Color(Palette.PENDING.r, Palette.PENDING.g, Palette.PENDING.b, 0.4)
	var l = Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = "Nuevos"
	l.add_color_override("font_color", Palette.PENDING)
	l.add_font_override("font", XatTheme.font(Palette.FONT_MEDIUM, Palette.FONT_SIZE - 3))
	for k in range(3):
		if k == 1:
			h.add_child(l)
			continue
		var line = PanelContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_stylebox_override("panel", XatTheme.box(lc, 0, 0, 0))
		line.rect_min_size.y = 1
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(line)
	return _gap_wrap(h)

# Píldora centrada (separador de día).
func _pill(p_text: String) -> Control:
	var c = CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p = PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_stylebox_override("panel", XatTheme.box(Palette.BG2, 99, 12, 3))
	var l = Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = p_text
	l.add_color_override("font_color", Palette.TEXT_DIM)
	l.add_font_override("font", XatTheme.font(Palette.FONT_MEDIUM, Palette.FONT_SIZE - 3))
	p.add_child(l)
	c.add_child(p)
	return _gap_wrap(c)

func _pill_button(p_text: String) -> Button:
	var b = Button.new()
	b.text = p_text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var edge = Color(Palette.AGENT_EDGE.r, Palette.AGENT_EDGE.g, Palette.AGENT_EDGE.b, 0.5)
	b.add_stylebox_override("normal", XatTheme.with_border(XatTheme.box(Palette.BG2, 99, 16, 6), edge))
	b.add_stylebox_override("hover", XatTheme.with_border(XatTheme.box(Palette.LINE, 99, 16, 6), Palette.AGENT_EDGE))
	b.add_stylebox_override("pressed", XatTheme.with_border(XatTheme.box(Palette.BG1, 99, 16, 6), Palette.AGENT_EDGE))
	b.add_font_override("font", XatTheme.font(Palette.FONT_MEDIUM, Palette.FONT_SIZE - 2))
	return b

static func today_iso() -> String:
	var d = OS.get_date()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

static func _day_dict(p_iso: String) -> Dictionary:
	return {"year": int(p_iso.substr(0, 4)), "month": int(p_iso.substr(5, 2)), "day": int(p_iso.substr(8, 2)), "hour": 0, "minute": 0, "second": 0}

# "Hoy" / "Ayer" / "lun 6 oct" (con año si no es el actual).
static func day_label(p_day: String, p_today: String) -> String:
	if p_day == p_today:
		return "Hoy"
	var y = OS.get_datetime_from_unix_time(OS.get_unix_time_from_datetime(_day_dict(p_today)) - 86400)
	if p_day == "%04d-%02d-%02d" % [y.year, y.month, y.day]:
		return "Ayer"
	var d = _day_dict(p_day)
	var wd = OS.get_datetime_from_unix_time(OS.get_unix_time_from_datetime(d)).weekday
	var out = "%s %d %s" % [WEEKDAYS[wd], d.day, MONTHS[clamp(d.month - 1, 0, 11)]]
	if p_day.substr(0, 4) != p_today.substr(0, 4):
		out += " " + p_day.substr(0, 4)
	return out

func _on_input_event(p_ev: InputEvent) -> void:
	if p_ev is InputEventKey and p_ev.pressed and not p_ev.shift \
			and (p_ev.scancode == KEY_ENTER or p_ev.scancode == KEY_KP_ENTER):
		_input.accept_event()
		_on_send()

# Crece de 1 a MAX_LINES líneas visuales (incluye las envueltas).
func _fit_input() -> void:
	var n := 0
	for i in range(_input.get_line_count()):
		n += 1 + _input.get_line_wrap_count(i)
	n = int(clamp(n, 1, MAX_LINES))
	var lh = _input.get_font("font").get_height() + _input.get_constant("line_spacing")
	_input.rect_min_size.y = n * lh + 22
	_input.rect_size.y = 0
	_hint.visible = _input.text == ""

func _on_send() -> void:
	var text = _input.text.strip_edges()
	if text == "" or _peer == "":
		return
	_input.text = ""
	_fit_input()
	_clear_unread()
	emit_signal("message_submitted", _peer, text)
