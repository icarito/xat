extends PanelContainer

# Panel de chat: burbujas agrupadas por remitente, estado de chat, chips de
# acciones (comandos ad-hoc / quick responses) y composer multilínea. Mantiene
# el modelo de mensajes para plegar correcciones 0308 y marcas de entrega 0184.

signal back_requested() # vista de un panel (móvil): volver al roster
signal message_submitted(bare, text)
signal action_selected(bare, item)
signal quick_selected(bare, value)
signal chat_state_sent(bare, state)
signal media_action(peer, rec, action) # abrir/descargar/reproducir media
signal attach_picked(peer, path)       # archivo elegido para enviar
signal attach_requested(peer)          # pedir el selector nativo (Android)
signal camera_requested(peer)          # tomar foto
signal voice_toggle(peer, start)       # empezar/terminar grabación
signal voice_cancel(peer)              # descartar la grabación en curso
signal text_copied(text)               # texto de una burbuja copiado al portapapeles
signal room_leave_requested()          # salir de la sala abierta
signal room_invite_requested()         # invitar a un contacto a la sala
signal room_settings_requested()       # editar la config de la sala (dueño/admin)
signal room_subject_requested()        # cambiar el tema de la sala
signal room_destroy_requested()        # destruir la sala (dueño)
signal occupant_action(room, nick, jid, action) # moderación sobre un ocupante

const Palette = preload("res://addons/xat_xmpp/ui/palette.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")
const Bubble = preload("res://addons/xat_xmpp/ui/bubble.gd")
const LocalTime = preload("res://addons/xat_xmpp/ui/localtime.gd")
const Media = preload("res://addons/xat_xmpp/xmpp/media.gd")
const FilePicker = preload("res://addons/xat_xmpp/ui/file_picker.gd")
const ToolCard = preload("res://addons/xat_xmpp/ui/tool_card.gd")
const ApprovalCard = preload("res://addons/xat_xmpp/ui/approval_card.gd")
const Shimmer = preload("res://addons/xat_xmpp/ui/fx/shimmer.gd")
const IconButton = preload("res://addons/xat_xmpp/ui/icon_button.gd")
const Waveform = preload("res://addons/xat_xmpp/ui/waveform.gd")

const MAX_LINES := 6
# Umbrales del gesto de voz (px lógicos ≈ dp). Ver docs/input-bar-design.md §5.1.
const HOLD_DELAY_MS := 150      # un toque más corto es tap, no grabación
const MIN_RECORD_MS := 800      # soltar antes descarta "demasiado corto"
const LOCK_THRESHOLD := 72.0    # deslizar ↑ para bloquear
const CANCEL_THRESHOLD := 110.0 # deslizar ← para cancelar
const MAX_BUBBLES := 200  # más viejas se liberan (el modelo _messages queda completo)
const RENDER_CHUNK := 12  # burbujas por frame en el render diferido (no bloquear la UI)
const NEAR_PX := 80.0
const WHEEL_STEP := 72.0  # px por muesca de rueda/pan; el ScrollContainer usa page/8 (brusco en pantallas grandes)
const WEEKDAYS := ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"]
const MONTHS := ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]

var _peer := ""
var _messages := []
var _room := ""          # sala activa ("" = chat 1:1)
var _room_nick := ""     # nick propio recordado en la sala
var _occupants := []     # ocupantes (dicts) de la sala activa
var _room_affiliation := "" # nuestra afiliación (owner/admin/member/none)
var _room_role := ""     # nuestro rol (moderator/participant/...)
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
var _render_seq := 0  # aborta renders diferidos cuando llega uno nuevo
var header_slot: HBoxContainer  # a la derecha del título (mini-orbe, etc.)
var _head: PanelContainer      # franja de cabecera (ocultable en landscape)

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
var _file_dialog: FileDialog
var _picker # FilePicker nativo (escritorio)
var _attach_btn            # IconButton: adjuntar
var _compose: MarginContainer
var _row: HBoxContainer
var _field: PanelContainer      # pastilla del campo
var _emoji_btn                  # IconButton: emoji
var _tail_btn                   # IconButton: mic <-> enviar
var _rec_strip: PanelContainer  # tira de grabación
var _rec_dot: Control
var _rec_timer: Label
var _rec_wave                    # Waveform
var _rec_hint: Label
var _rec_trash                   # IconButton: cancelar grabación
var _emoji_menu: PopupMenu
var _attach_menu: PopupMenu
var _emoji_values := []
var _bottom_inset := 0
var _attach_enabled := true
var _voice_enabled := true
var juice = null                 # inyectado por main (háptica/sonido), opcional
var _recording := false
var _sel_bar: PanelContainer
var _lp: Timer
var _press := false
var _press_pos := Vector2.ZERO
var _press_moved := false
var _sel_bubble = null
var _occ_btn: Button
var _occ_popup: PopupPanel
var _occ_list: VBoxContainer
var _leave_btn: Button
var _room_menu_btn: Button
var _room_menu: PopupMenu
var _occ_action_menu: PopupMenu
var _occ_action_ctx := {}
var _header_actions := true

# Estado del gesto de voz (máquina de estados, ver docs/input-bar-design.md §5.1).
var _rec_phase := "idle"        # idle | armed | held | locked | cancel
var _rec_index := -1            # índice de toque que posee el gesto (-2 = mouse)
var _rec_origin := Vector2.ZERO
var _rec_arm_timer: Timer
var _rec_cancel := false
var _rec_started_ms := 0
var _rec_elapsed_ms := 0
var _tail_mode := "mic"
var _mobile_override := -1      # -1 = auto; 1/0 fuerza para tests

func _init() -> void:
	name = "ChatPanel"
	rect_min_size = Vector2(360, 0)
	_build()

func _build() -> void:
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 0)
	# Cabecera con el peer.
	var head = PanelContainer.new()
	_head = head
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
	_occ_btn = Button.new()
	_occ_btn.text = "Ocupantes"
	_occ_btn.visible = false
	_occ_btn.flat = true
	_occ_btn.focus_mode = Control.FOCUS_NONE
	_occ_btn.connect("pressed", self, "_toggle_occupants")
	hh.add_child(_occ_btn)
	_room_menu_btn = Button.new()
	_room_menu_btn.text = "⋯"
	_room_menu_btn.visible = false
	_room_menu_btn.flat = true
	_room_menu_btn.focus_mode = Control.FOCUS_NONE
	_room_menu_btn.hint_tooltip = "Acciones de la sala"
	_room_menu_btn.connect("pressed", self, "_open_room_menu")
	hh.add_child(_room_menu_btn)
	_room_menu = PopupMenu.new()
	_room_menu.connect("id_pressed", self, "_on_room_menu")
	add_child(_room_menu)
	_leave_btn = Button.new()
	_leave_btn.text = "Salir"
	_leave_btn.visible = false
	_leave_btn.flat = true
	_leave_btn.focus_mode = Control.FOCUS_NONE
	_leave_btn.connect("pressed", self, "emit_signal", ["room_leave_requested"])
	hh.add_child(_leave_btn)
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
	foot.add_stylebox_override("panel", XatTheme.box(Palette.BG1, 0, 12, 10))
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
	# Composer: una sola fila con iconos incrustados y botón cola que muta
	# (mic <-> enviar). Ver docs/input-bar-design.md §3–§5.
	_compose = MarginContainer.new()
	_compose.add_constant_override("margin_left", 8)
	_compose.add_constant_override("margin_right", 8)
	_compose.add_constant_override("margin_top", 6)
	_compose.add_constant_override("margin_bottom", 6)
	_row = HBoxContainer.new()
	_row.add_constant_override("separation", 8)
	_attach_btn = IconButton.new()
	_attach_btn.setup("paperclip", 40, Palette.TEXT_DIM, "Adjuntar (archivo o foto)")
	_attach_btn.connect("pressed", self, "_on_attach")
	_row.add_child(_attach_btn)
	# Pastilla del campo: el borde lo dibuja el PanelContainer (TextEdit sin caja).
	_field = PanelContainer.new()
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.size_flags_vertical = Control.SIZE_SHRINK_END
	_field.rect_min_size = Vector2(0, 44)
	_field.add_stylebox_override("panel", _pill_box(Palette.BG2, Palette.LINE))
	var field_row = HBoxContainer.new()
	field_row.add_constant_override("separation", 0)
	_input = TextEdit.new()
	_input.wrap_enabled = true
	_input.context_menu_enabled = true
	_input.shortcut_keys_enabled = true
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.size_flags_vertical = Control.SIZE_SHRINK_END
	_input.connect("gui_input", self, "_on_input_event")
	_input.connect("text_changed", self, "_fit_input")
	_input.connect("text_changed", self, "_update_tail")
	_input.connect("focus_entered", self, "_on_input_focus", [true])
	_input.connect("focus_exited", self, "_on_input_focus", [false])
	var empty = StyleBoxEmpty.new()
	for side in ["left", "right", "top", "bottom"]:
		var mv = {"left": 14, "right": 4, "top": 11, "bottom": 11}[side]
		empty.set("content_margin_" + side, mv)
	for st in ["normal", "focus", "read_only"]:
		_input.add_stylebox_override(st, empty)
	_hint = Label.new()
	_hint.text = "Escribe un mensaje…"
	_hint.add_color_override("font_color", Palette.TEXT_DIM)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.rect_position = Vector2(14, 11)
	_input.add_child(_hint)
	field_row.add_child(_input)
	_emoji_btn = IconButton.new()
	_emoji_btn.setup("emoji", 36, Palette.TEXT_DIM, "Emoji")
	_emoji_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_emoji_btn.connect("pressed", self, "_on_emoji")
	field_row.add_child(_emoji_btn)
	_field.add_child(field_row)
	_row.add_child(_field)
	# Tira de grabación (reemplaza a la pastilla mientras se graba).
	_rec_strip = PanelContainer.new()
	_rec_strip.visible = false
	_rec_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rec_strip.size_flags_vertical = Control.SIZE_SHRINK_END
	_rec_strip.rect_min_size = Vector2(0, 44)
	_rec_strip.add_stylebox_override("panel", _pill_box(Palette.BG2, Palette.LINE))
	var rec_row = HBoxContainer.new()
	rec_row.add_constant_override("separation", 8)
	rec_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rec_dot = Control.new()
	_rec_dot.rect_min_size = Vector2(12, 12)
	_rec_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rec_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rec_dot.connect("draw", self, "_draw_rec_dot")
	rec_row.add_child(_rec_dot)
	_rec_timer = Label.new()
	_rec_timer.text = "0:00"
	_rec_timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rec_timer.add_color_override("font_color", Palette.TEXT)
	_rec_timer.add_font_override("font", XatTheme.font(Palette.FONT_MONO, Palette.FONT_SIZE - 2))
	rec_row.add_child(_rec_timer)
	_rec_wave = Waveform.new()
	_rec_wave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rec_wave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rec_wave.rect_min_size = Vector2(60, 24)
	_rec_wave.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rec_row.add_child(_rec_wave)
	_rec_hint = Label.new()
	_rec_hint.text = "← desliza para cancelar"
	_rec_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rec_hint.add_color_override("font_color", Palette.TEXT_DIM)
	_rec_hint.add_font_override("font", XatTheme.font(Palette.FONT_REGULAR, Palette.FONT_SIZE - 3))
	rec_row.add_child(_rec_hint)
	_rec_trash = IconButton.new()
	_rec_trash.setup("trash", 40, Palette.ERROR, "Cancelar la grabación")
	_rec_trash.visible = false
	_rec_trash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rec_trash.connect("pressed", self, "_on_rec_trash")
	rec_row.add_child(_rec_trash)
	_rec_strip.add_child(rec_row)
	_row.add_child(_rec_strip)
	# Botón cola: mic cuando vacío, enviar con texto o grabando bloqueado.
	_tail_btn = IconButton.new()
	_tail_btn.setup("mic", 48, Palette.TEXT, "Grabar un mensaje de voz")
	_tail_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	# El mouse/tacto del tail se rastrea en _input (gesto); ignoramos el mouse
	# del Control para no disparar dos veces con emulate_mouse_from_touch.
	_tail_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_tail_btn)
	_compose.add_child(_row)
	f.add_child(_compose)
	foot.add_child(f)
	v.add_child(foot)
	add_child(v)
	_update_tail()
	_fit_input()
	_build_select()
	_build_occupants()
	_build_emoji_menu()
	# Timer de armado del gesto: al disparar, el toque se vuelve grabación.
	_rec_arm_timer = Timer.new()
	_rec_arm_timer.one_shot = true
	_rec_arm_timer.wait_time = float(HOLD_DELAY_MS) / 1000.0
	_rec_arm_timer.connect("timeout", self, "_on_arm_timeout")
	add_child(_rec_arm_timer)

# Pastilla redondeada del campo/tira (radio 22 = RADIUS + 6).
func _pill_box(p_bg: Color, p_border: Color) -> StyleBoxFlat:
	return XatTheme.with_border(XatTheme.box(p_bg, Palette.RADIUS + 6, 0, 0), p_border)

func _draw_rec_dot() -> void:
	var c = _rec_dot.rect_size * 0.5
	_rec_dot.draw_circle(c, min(4.0, _rec_dot.rect_size.x * 0.4), Palette.ERROR)

# Menú de emoji mínimo (Fase 1: unos pocos; el picker completo es Fase 2).
func _build_emoji_menu() -> void:
	_emoji_values = ["😀", "😂", "😊", "😍", "👍", "🙏", "🎉", "❤️"]
	_emoji_menu = PopupMenu.new()
	for i in range(_emoji_values.size()):
		_emoji_menu.add_item(_emoji_values[i], i)
	_emoji_menu.connect("id_pressed", self, "_on_emoji_pick")
	add_child(_emoji_menu)

func _on_emoji() -> void:
	if _emoji_menu == null:
		return
	_emoji_menu.popup_centered()

func _on_emoji_pick(p_id: int) -> void:
	if p_id < 0 or p_id >= _emoji_values.size():
		return
	_input.insert_text_at_cursor(_emoji_values[p_id])
	_fit_input()
	_update_tail()


# Popup de ocupantes de la sala: cada fila inserta `@nick` en el composer.
func _build_occupants() -> void:
	_occ_popup = PopupPanel.new()
	_occ_popup.rect_min_size = Vector2(220, 160)
	var wrap = MarginContainer.new()
	wrap.add_constant_override("margin_left", 10)
	wrap.add_constant_override("margin_right", 10)
	wrap.add_constant_override("margin_top", 10)
	wrap.add_constant_override("margin_bottom", 10)
	var sc = ScrollContainer.new()
	sc.scroll_horizontal_enabled = false
	_occ_list = VBoxContainer.new()
	_occ_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_occ_list.add_constant_override("separation", 2)
	sc.add_child(_occ_list)
	wrap.add_child(sc)
	_occ_popup.add_child(wrap)
	add_child(_occ_popup)
	_occ_action_menu = PopupMenu.new()
	_occ_action_menu.connect("id_pressed", self, "_on_occ_action")
	add_child(_occ_action_menu)

# Barra flotante de selección (pulsación larga en táctil, o mantener el clic en
# escritorio) con Copiar/Listo, y el detector de pulsación larga.
func _build_select() -> void:
	_sel_bar = PanelContainer.new()
	_sel_bar.anchor_left = 0.5
	_sel_bar.anchor_right = 0.5
	_sel_bar.anchor_top = 0.0
	_sel_bar.anchor_bottom = 0.0
	_sel_bar.margin_left = -96
	_sel_bar.margin_right = 96
	_sel_bar.margin_top = 52
	_sel_bar.margin_bottom = 96
	_sel_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb = XatTheme.box(Palette.BG2, 12, 10, 8)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	_sel_bar.add_stylebox_override("panel", sb)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGN_CENTER
	row.add_constant_override("separation", 8)
	var copy = Button.new()
	copy.text = "Copiar"
	copy.focus_mode = Control.FOCUS_NONE
	copy.connect("pressed", self, "_on_copy_selection")
	var allb = Button.new()
	allb.text = "Todo"
	allb.hint_tooltip = "Seleccionar todo el mensaje"
	allb.focus_mode = Control.FOCUS_NONE
	allb.connect("pressed", self, "_on_select_all")
	var done = Button.new()
	done.text = "Listo"
	done.focus_mode = Control.FOCUS_NONE
	done.connect("pressed", self, "_exit_selection")
	row.add_child(copy)
	row.add_child(allb)
	row.add_child(done)
	_sel_bar.add_child(row)
	_sel_bar.visible = false
	add_child(_sel_bar)
	_lp = Timer.new()
	_lp.one_shot = true
	_lp.wait_time = 0.4
	_lp.connect("timeout", self, "_on_long_press")
	add_child(_lp)

# Al elegir un chat se puede escribir de inmediato (deferred: el panel puede
# estar recién visible y aún no aceptar foco).
func focus_composer() -> void:
	_input.call_deferred("grab_focus")

# Juice (háptica/sonido) inyectado por main; opcional para instanciar en tests.
func set_juice(p_juice) -> void:
	juice = p_juice

# Inset inferior de safe area (barra de gestos). Súmalo al margen del composer.
func set_bottom_inset(p_px: int) -> void:
	_bottom_inset = p_px
	if _compose != null:
		_compose.add_constant_override("margin_bottom", 6 + p_px)

func _ready() -> void:
	if get_tree() != null and not get_tree().is_connected("files_dropped", self, "_on_files_dropped"):
		get_tree().connect("files_dropped", self, "_on_files_dropped")

# Arrastrar y soltar archivos sobre la ventana: se adjunta el primero (Fase 1,
# envío inmediato como hoy). Alternativa sin arrastre: el botón adjuntar.
func _on_files_dropped(p_files: PoolStringArray, _screen: int) -> void:
	if not visible or _peer == "" or p_files.empty() or not _attach_enabled:
		return
	emit_signal("attach_picked", _peer, p_files[0])

# En landscape la navegación y el título viven en el sidebar: cabecera compacta.
func set_nav_visible(p_back: bool, p_title: bool) -> void:
	back_button.visible = p_back
	_title.visible = p_title

# Oculta toda la franja de cabecera (en landscape el título/identidad viven en
# el sidebar y el alto es escaso).
func set_header_visible(p_visible: bool) -> void:
	if _head != null:
		_head.visible = p_visible

# Los botones de acción de sala (Ocupantes/⋯/Salir) pueden vivir en el sidebar.
func set_header_actions_visible(p_visible: bool) -> void:
	_header_actions = p_visible
	_apply_header_actions()

func _apply_header_actions() -> void:
	var room = _room != ""
	if _occ_btn != null:
		_occ_btn.visible = room and _header_actions
	if _room_menu_btn != null:
		_room_menu_btn.visible = room and _header_actions
	if _leave_btn != null:
		_leave_btn.visible = room and _header_actions

# Disparadores para los botones equivalentes del sidebar.
func toggle_occupants() -> void:
	if _room != "":
		_toggle_occupants()

func popup_room_menu() -> void:
	if _room != "":
		_open_room_menu()

# --- Adjuntos (composer) ---

# Un solo icono de adjuntar: abre un menú con archivo (selector) y cámara/foto,
# preservando ambos accesos del composer anterior.
func _on_attach() -> void:
	if _peer == "" or not _attach_enabled:
		return
	if _attach_menu == null:
		_attach_menu = PopupMenu.new()
		_attach_menu.add_item("Archivo…", 1)
		_attach_menu.add_item("Cámara / Foto…", 2)
		_attach_menu.connect("id_pressed", self, "_on_attach_menu")
		add_child(_attach_menu)
	_attach_menu.popup_centered()

func _on_attach_menu(p_id: int) -> void:
	if p_id == 1:
		_open_file_dialog()
	elif p_id == 2:
		_on_camera()

func _open_file_dialog() -> void:
	if _peer == "":
		return
	# En Android se usa el selector nativo (Storage Access Framework) vía el
	# singleton XatMedia: el FileDialog del motor no puede navegar el
	# almacenamiento compartido (scoped storage).
	if Engine.has_singleton("XatMedia"):
		emit_signal("attach_requested", _peer)
		return
	# Escritorio con backend nativo (zenity/kdialog/osascript/PowerShell): mejor
	# que el FileDialog dibujado por el motor.
	if FilePicker.has_native():
		if _picker == null:
			_picker = FilePicker.new()
			_picker.name = "FilePicker"
			add_child(_picker)
			_picker.connect("picked", self, "_on_native_file_picked")
			_picker.connect("unavailable", self, "_on_picker_unavailable")
		_picker.open("Elegir archivo", [
			"Imágenes | *.png *.jpg *.jpeg *.webp *.gif *.bmp *.heic",
			"Audio | *.ogg *.oga *.opus *.mp3 *.m4a *.wav *.flac",
			"Todos | *",
		])
		return
	_show_engine_dialog()

# Fallback: FileDialog dibujado por el motor (sin backend nativo disponible).
func _show_engine_dialog() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.mode = FileDialog.MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.resizable = true
		_file_dialog.rect_min_size = Vector2(560, 400)
		_file_dialog.add_filter("*.png, *.jpg, *.jpeg, *.webp, *.gif, *.bmp, *.heic ; Imágenes")
		_file_dialog.add_filter("*.ogg, *.oga, *.opus, *.mp3, *.m4a, *.wav, *.flac ; Audio")
		_file_dialog.add_filter("*.* ; Todos los archivos")
		_file_dialog.connect("file_selected", self, "_on_file_selected")
		add_child(_file_dialog)
	if OS.get_name() == "Android":
		# En Android no hay picker nativo: se abre el diálogo del motor en la
		# carpeta de imágenes (accesible vía MediaStore con el permiso de media).
		var d = Directory.new()
		for dir in [OS.SYSTEM_DIR_PICTURES, OS.SYSTEM_DIR_DCIM]:
			var p = OS.get_system_dir(dir, true)
			if p != "" and d.dir_exists(p):
				_file_dialog.current_dir = p
				break
	_file_dialog.popup_centered_ratio(0.7)

func _on_native_file_picked(p_path: String) -> void:
	if _peer != "" and p_path != "":
		emit_signal("attach_picked", _peer, p_path)

func _on_picker_unavailable() -> void:
	_show_engine_dialog()

# Galería del teléfono (fallback cuando no hay cámara nativa).
func open_gallery() -> void:
	_open_file_dialog()

func _on_file_selected(p_path: String) -> void:
	if _peer != "" and p_path != "":
		emit_signal("attach_picked", _peer, p_path)

func _on_camera() -> void:
	if _peer != "":
		emit_signal("camera_requested", _peer)

# --- Gesto de voz y botón cola (ver docs/input-bar-design.md §5–§6) ---

func _is_mobile() -> bool:
	if _mobile_override >= 0:
		return _mobile_override == 1
	return OS.has_feature("mobile")

func _juice_haptic(p_kind: String) -> void:
	if juice != null:
		juice.haptic(p_kind)

# El botón cola muta: mic (vacío) / enviar (con texto) / enviar (grabación
# bloqueada); durante la grabación en curso sin bloquear sigue mostrando mic.
func _update_tail() -> void:
	if _input == null:
		return
	var has_text = _input.text.strip_edges() != ""
	var mode = "mic"
	if _recording:
		mode = "send" if _rec_phase == "locked" else "mic"
	elif has_text:
		mode = "send"
	_tail_set_mode(mode)

func _tail_set_mode(p_mode: String) -> void:
	if _tail_btn == null:
		return
	_tail_mode = p_mode
	if p_mode == "send":
		_tail_btn.set_glyph("send")
		_tail_btn.set_icon_color(Palette.TEXT)
		_tail_btn.hint_tooltip = "Enviar"
		for st in ["normal", "pressed", "focus", "disabled"]:
			_tail_btn.add_stylebox_override(st, XatTheme.box(Palette.USER, 24, 0, 0))
		_tail_btn.add_stylebox_override("hover", XatTheme.box(Palette.USER.lightened(0.15), 24, 0, 0))
	else:
		_tail_btn.set_glyph("mic")
		_tail_btn.set_icon_color(Palette.TEXT)
		_tail_btn.hint_tooltip = "Grabar un mensaje de voz"
		for st in ["normal", "pressed", "focus", "disabled"]:
			_tail_btn.add_stylebox_override(st, XatTheme.box(Palette.BG2, 24, 0, 0))
		_tail_btn.add_stylebox_override("hover", XatTheme.box(Palette.BG2.lightened(0.15), 24, 0, 0))

# Un clic/tap "seco" en el botón cola sin gesto (p. ej. activación externa).
func _on_tail() -> void:
	if _peer == "":
		return
	if _recording or _rec_phase in ["locked", "held", "cancel"]:
		_rec_send()
		return
	if _input != null and _input.text.strip_edges() != "":
		_on_send()
		return
	if _voice_enabled:
		_start_locked_recording()

func _on_input_focus(p_entered: bool) -> void:
	if _field == null:
		return
	_field.add_stylebox_override("panel", _pill_box(Palette.BG2, Palette.AGENT_EDGE if p_entered else Palette.LINE))

# Gesto del composer: rastrea el toque del botón cola por ÍNDICE. Godot 3 no
# tiene pointer capture, así que se consume el evento acá y se sigue por drag.
func _composer_gesture(p_event) -> bool:
	if _tail_btn == null:
		return false
	if p_event is InputEventScreenTouch:
		if p_event.pressed:
			if _tail_hit(p_event.position):
				_gesture_press(p_event.index, p_event.position)
				_consume_input()
				return true
		elif p_event.index == _rec_index:
			_consume_input()
			_gesture_release()
			return true
	elif p_event is InputEventScreenDrag:
		if p_event.index == _rec_index:
			_consume_input()
			_gesture_move(p_event.position)
			return true
	elif p_event is InputEventMouseButton and p_event.button_index == BUTTON_LEFT:
		if p_event.pressed:
			if _tail_hit(p_event.position):
				_gesture_press(-2, p_event.position)
				_consume_input()
				return true
			elif _rec_index == -2 and _rec_phase != "idle":
				_consume_input()
				return true
		elif _rec_index == -2:
			_consume_input()
			_gesture_release()
			return true
	elif p_event is InputEventMouseMotion and _rec_index == -2 and _rec_phase in ["armed", "held", "cancel"]:
		_consume_input()
		_gesture_move(p_event.position)
		return true
	return false

func _consume_input() -> void:
	var t = get_tree()
	if t != null:
		t.set_input_as_handled()

func _tail_hit(p_pos: Vector2) -> bool:
	return _tail_btn.get_global_rect().grow(6).has_point(p_pos)

func _gesture_press(p_index: int, p_pos: Vector2) -> void:
	if _rec_phase == "locked":
		_rec_send()
		return
	if _rec_phase != "idle" or _recording:
		return
	if _input != null and _input.text.strip_edges() != "":
		_rec_index = p_index
		_rec_phase = "tap_send"   # enviar recién al soltar (WCAG 2.5.2)
		return
	if not _voice_enabled:
		return
	_rec_index = p_index
	_rec_origin = p_pos
	_rec_cancel = false
	# Escritorio (mouse): clic directo a grabación bloqueada, sin mantener.
	if p_index == -2:
		_rec_phase = "armed_click"
		return
	_rec_phase = "armed"
	_rec_arm_timer.start()

func _gesture_move(p_pos: Vector2) -> void:
	if _rec_phase in ["idle", "locked", "tap_send", "armed_click"]:
		return
	var dx = p_pos.x - _rec_origin.x
	var dy = p_pos.y - _rec_origin.y
	var lock_p = clamp(-dy / LOCK_THRESHOLD, 0.0, 1.0)
	if _rec_phase == "armed":
		# Antes de armar sólo bloquear (subir) es válido; cancelar se ignora.
		_rec_wave.set_progress(lock_p, 0.0)
		if lock_p >= 1.0:
			_lock_recording()
		return
	var cancel_p = clamp(-dx / CANCEL_THRESHOLD, 0.0, 1.0)
	_rec_wave.set_progress(lock_p, cancel_p)
	if cancel_p >= 1.0:
		if not _rec_cancel:
			_rec_cancel = true
			_rec_phase = "cancel"
			_juice_haptic("alert")
			_tint_rec_strip(true)
			_rec_hint.text = "Suelta para cancelar"
		return
	if _rec_cancel:
		_rec_cancel = false
		_rec_phase = "held"
		_tint_rec_strip(false)
		_rec_hint.text = "← desliza para cancelar"
	if lock_p >= 1.0:
		_lock_recording()

func _gesture_release() -> void:
	if _rec_arm_timer != null:
		_rec_arm_timer.stop()
	var phase = _rec_phase
	_rec_index = -1
	if phase in ["idle", "locked"]:
		return
	if phase == "tap_send":
		_rec_phase = "idle"
		_on_send()
		return
	if phase == "cancel":
		_rec_phase = "idle"
		_rec_cancel = false
		_tint_rec_strip(false)
		_rec_cancel_recording()
		return
	if phase == "armed":
		# Tap corto sin llegar a grabar: grabación bloqueada (WCAG 2.5.1).
		_start_locked_recording()
		return
	if phase == "armed_click":
		# Escritorio: clic = grabación bloqueada.
		_start_locked_recording()
		return
	# held: comprobar duración mínima antes de enviar.
	var elapsed = OS.get_ticks_msec() - _rec_started_ms
	_rec_phase = "idle"
	if elapsed < MIN_RECORD_MS:
		_rec_cancel_recording()
		_juice_haptic("tick")
		if juice != null:
			juice.toast("Mantén para grabar")
		return
	_rec_send()

func _on_arm_timeout() -> void:
	_start_recording()

func _start_recording() -> void:
	if _rec_phase != "armed":
		return
	_rec_phase = "held"
	_rec_started_ms = OS.get_ticks_msec()
	_begin_recording_ui(false)
	emit_signal("voice_toggle", _peer, true)

func _start_locked_recording() -> void:
	if _recording or _rec_phase == "locked":
		return
	_rec_phase = "locked"
	_rec_index = -1
	_rec_cancel = false
	_rec_started_ms = OS.get_ticks_msec()
	_begin_recording_ui(true)
	emit_signal("voice_toggle", _peer, true)

func _lock_recording() -> void:
	if _rec_phase == "locked":
		return
	var was = _recording
	if _rec_arm_timer != null:
		_rec_arm_timer.stop()
	_rec_phase = "locked"
	_rec_cancel = false
	_tint_rec_strip(false)
	if not was:
		_rec_started_ms = OS.get_ticks_msec()
		_begin_recording_ui(true)
		emit_signal("voice_toggle", _peer, true)
	else:
		_rec_trash.visible = true
		_rec_hint.text = "Bloqueado"
		_tail_set_mode("send")
	_juice_haptic("success")
	if juice != null:
		juice.pop(_tail_btn)

func _rec_send() -> void:
	if _rec_arm_timer != null:
		_rec_arm_timer.stop()
	_rec_phase = "idle"
	_rec_index = -1
	_rec_cancel = false
	emit_signal("voice_toggle", _peer, false)

func _rec_cancel_recording() -> void:
	if _rec_arm_timer != null:
		_rec_arm_timer.stop()
	_rec_phase = "idle"
	_rec_index = -1
	_rec_cancel = false
	if _recording:
		_juice_haptic("error")
		if juice != null:
			juice.play("alert")
	emit_signal("voice_cancel", _peer)

func _on_rec_trash() -> void:
	if _peer != "" and _recording:
		_rec_cancel_recording()

func _begin_recording_ui(p_locked: bool) -> void:
	_recording = true
	_rec_cancel = false
	_rec_elapsed_ms = 0
	if _field != null:
		_field.visible = false
	if _rec_strip != null:
		_rec_strip.visible = true
	if _rec_wave != null:
		_rec_wave.clear()
	if _rec_timer != null:
		_rec_timer.text = "0:00"
	if _rec_trash != null:
		_rec_trash.visible = p_locked
	if _rec_hint != null:
		_rec_hint.text = "Bloqueado" if p_locked else "← desliza para cancelar"
	_tint_rec_strip(false)
	_tail_set_mode("send" if p_locked else "mic")
	_juice_haptic("receive")
	if juice != null:
		juice.play("tool_start")

func _tint_rec_strip(p_on: bool) -> void:
	if _rec_strip == null:
		return
	_rec_strip.add_stylebox_override("panel", _pill_box(Palette.BG2, Palette.ERROR if p_on else Palette.LINE))

# La app avisa del estado real de la grabación (por si el micro falla) y empuja
# la amplitud real del micrófono para la forma de onda (p_level < 0 = sin dato).
func set_recording(p_on: bool, p_elapsed_ms: int, p_level: float = -1.0) -> void:
	_recording = p_on
	if _rec_strip == null:
		return
	if p_on:
		_rec_elapsed_ms = p_elapsed_ms
		_rec_timer.text = Media.format_duration_ms(p_elapsed_ms)
		_field.visible = false
		_rec_strip.visible = true
		_rec_trash.visible = _rec_phase == "locked"
		_rec_hint.text = "Bloqueado" if _rec_phase == "locked" else "← desliza para cancelar"
		_tail_set_mode("send" if _rec_phase == "locked" else "mic")
		if p_level >= 0.0 and _rec_wave != null:
			_rec_wave.push(p_level)
	else:
		_rec_phase = "idle"
		_rec_index = -1
		_rec_cancel = false
		_rec_elapsed_ms = 0
		if _rec_arm_timer != null:
			_rec_arm_timer.stop()
		_field.visible = true
		_rec_strip.visible = false
		_rec_trash.visible = false
		if _rec_wave != null:
			_rec_wave.clear()
		_tint_rec_strip(false)
		_update_tail()


func _on_bubble_media_action(p_rec: Dictionary, p_action: String) -> void:
	emit_signal("media_action", _peer, p_rec, p_action)

# --- Selección de texto ---

# Pulsación larga (0.4 s sin moverse) sobre el texto de una burbuja -> modo
# selección. En escritorio además se puede seleccionar arrastrando (el label ya
# tiene selección habilitada).
func _input(p_event) -> void:
	if not visible or _peer == "":
		return
	if _file_dialog != null and _file_dialog.visible:
		return
	# Gesto del composer primero (consume el toque del botón cola).
	if _composer_gesture(p_event):
		return
	# Rueda/trackpad: paso propio y suave (ver _handle_wheel).
	if _handle_wheel(p_event):
		return
	# Sólo táctil: en escritorio la selección por arrastre del propio label basta.
	var pressed := false
	var pos := Vector2.ZERO
	if p_event is InputEventScreenTouch:
		pressed = p_event.pressed
		pos = p_event.position
	elif p_event is InputEventScreenDrag:
		if _press and p_event.position.distance_to(_press_pos) > 14.0:
			_press_moved = true
			if _lp != null:
				_lp.stop()
		return
	else:
		return
	if not get_global_rect().has_point(pos):
		return
	# El composer tiene su propia selección/gesto: no iniciar pulsación larga acá.
	if _in_composer(pos):
		return
	if pressed:
		# Un toque sobre la barra no debe disparar otra selección.
		if _sel_bar != null and _sel_bar.visible and _sel_bar.get_global_rect().has_point(pos):
			return
		_press = true
		_press_pos = pos
		_press_moved = false
		if _lp != null:
			_lp.start()
	else:
		_press = false
		if _lp != null:
			_lp.stop()

# ¿El punto cae dentro del composer? (para no robar el gesto de selección).
func _in_composer(p_pos: Vector2) -> bool:
	return _compose != null and _compose.get_global_rect().has_point(p_pos)


# Scroll de rueda/trackpad con paso fijo. Devuelve true si consumió el evento.
# El ScrollContainer por defecto mueve page/8 por muesca: con ventanas grandes
# son saltos enormes. Acá movemos unos pocos píxeles y respetamos el factor
# (ruedas de alta resolución mandan factor chico → queda suave).
func _handle_wheel(p_event) -> bool:
	if _scroll == null:
		return false
	var dy := 0.0
	if p_event is InputEventMouseButton:
		if not p_event.pressed:
			return false
		if p_event.button_index == BUTTON_WHEEL_UP:
			dy = -WHEEL_STEP * p_event.factor
		elif p_event.button_index == BUTTON_WHEEL_DOWN:
			dy = WHEEL_STEP * p_event.factor
		else:
			return false
	elif p_event is InputEventPanGesture:
		dy = WHEEL_STEP * p_event.delta.y
	else:
		return false
	if not get_global_rect().has_point(p_event.position):
		return false
	get_tree().set_input_as_handled()
	_scroll.scroll_vertical = _scroll.scroll_vertical + int(dy)
	return true

func _on_long_press() -> void:
	if not _press or _press_moved:
		return
	var b = _bubble_at(_press_pos)
	if b == null:
		return
	_enter_selection(b)

func _bubble_at(p_pos: Vector2):
	for i in range(_bubbles.size() - 1, -1, -1):
		var b = _bubbles[i]
		if not is_instance_valid(b) or not b.is_text_visible():
			continue
		if b.text_global_rect().has_point(p_pos):
			return b
	return null

func _enter_selection(p_bubble) -> void:
	if _sel_bubble == p_bubble:
		return
	if _sel_bubble != null and is_instance_valid(_sel_bubble):
		_sel_bubble.end_selection()
	_sel_bubble = p_bubble
	_sel_bubble.begin_selection_at(_press_pos)
	if _sel_bar != null:
		_sel_bar.visible = true

func _on_select_all() -> void:
	if _sel_bubble != null and is_instance_valid(_sel_bubble):
		_sel_bubble.select_all()

func _exit_selection() -> void:
	if _sel_bubble != null and is_instance_valid(_sel_bubble):
		_sel_bubble.end_selection()
	_sel_bubble = null
	if _sel_bar != null:
		_sel_bar.visible = false

func _on_copy_selection() -> void:
	if _sel_bubble == null or not is_instance_valid(_sel_bubble):
		_exit_selection()
		return
	var t = _sel_bubble.selected_text()
	if t.strip_edges() == "":
		t = str(_sel_bubble.rec.get("body", ""))
	if t != "":
		OS.set_clipboard(t)
		emit_signal("text_copied", t)
	_exit_selection()

# Actualiza el adjunto de una fila por id (subida enviada/fallida).
func update_media_state(p_id: String, p_state: String, p_url: String, p_error: String = "") -> void:
	for i in range(_messages.size()):
		if str(_messages[i].get("id", "")) == p_id:
			var rec = _messages[i]
			var attach = rec.get("attach", {})
			if not (attach is Dictionary):
				attach = {}
			attach["state"] = p_state
			attach["error"] = p_error
			if p_url != "":
				attach["url"] = p_url
				rec["body"] = p_url
			rec["attach"] = attach
			if _bub(i) != null:
				_bub(i).refresh()
			return

# Registra la ruta local de un adjunto por id de mensaje y redibuja.
func set_media_local(p_id: String, p_path: String) -> void:
	for i in range(_messages.size()):
		if str(_messages[i].get("id", "")) == p_id:
			var attach = _messages[i].get("attach", {})
			if not (attach is Dictionary):
				attach = {}
			attach["local"] = p_path
			_messages[i]["attach"] = attach
			if _bub(i) != null:
				_bub(i).refresh()
			return

func set_peer(p_bare: String) -> void:
	_exit_selection()
	if _recording:
		_rec_cancel_recording()
	_peer = p_bare
	_room = ""
	_room_nick = ""
	_occupants = []
	_room_affiliation = ""
	_room_role = ""
	if _occ_btn != null:
		_occ_btn.visible = false
	if _leave_btn != null:
		_leave_btn.visible = false
	if _room_menu_btn != null:
		_room_menu_btn.visible = false
	_set_tools_visible(true)
	_title.text = p_bare.split("@")[0]
	_title.hint_tooltip = p_bare
	_messages = []
	_pending_actions = null
	_clear_actions()
	_clear_tools()
	_reset_view()
	_rebuild()

# Modo sala (XEP-0045): título = sala; se muestra la lista de ocupantes
# (oprimible -> @mención) y se suprimen acciones, estados y adjuntos.
# `p_affiliation`/`p_role` son los nuestros, para habilitar la moderación.
func set_room(p_room: String, p_nick: String, p_occupants: Array = [], p_affiliation: String = "", p_role: String = "") -> void:
	_exit_selection()
	_peer = p_room
	_room = p_room
	_room_nick = p_nick
	_occupants = p_occupants
	_room_affiliation = p_affiliation
	_room_role = p_role
	_title.text = p_room.split("@")[0]
	_title.hint_tooltip = p_room
	_occ_btn.visible = true
	_leave_btn.visible = true
	_room_menu_btn.visible = true
	_apply_header_actions()
	_set_tools_visible(false)
	_messages = []
	_pending_actions = null
	_clear_actions()
	_clear_tools()
	_reset_view()
	_refresh_occupants()
	_rebuild()

# Actualiza sólo la lista de ocupantes y su botón (cambios de presencia en vivo).
func update_occupants(p_occupants: Array) -> void:
	_occupants = p_occupants
	if _occ_btn != null and _room != "":
		_refresh_occupants()

# Cambia nuestra afiliación/rol (p.ej. si nos nombran moderadores).
func set_room_caps(p_affiliation: String, p_role: String) -> void:
	_room_affiliation = p_affiliation
	_room_role = p_role
	if _room != "" and _occ_popup != null and _occ_popup.visible:
		_refresh_occupants()

func set_room_subject(p_subject: String) -> void:
	if _room != "":
		_title.hint_tooltip = _room + (("\n" + p_subject) if p_subject != "" else "")

# En salas se suprimen adjuntos y voz (comportamiento previo): se deshabilitan
# el botón de adjuntar y el arranque de grabación por gesto/tap.
func _set_tools_visible(p_visible: bool) -> void:
	_attach_enabled = p_visible
	_voice_enabled = p_visible
	if _attach_btn != null:
		_attach_btn.disabled = not p_visible
		_attach_btn.set_icon_color(Palette.ASLEEP if not p_visible else Palette.TEXT_DIM)
	if not p_visible and _recording:
		_rec_cancel_recording()
	_update_tail()

func _refresh_occupants() -> void:
	_occ_btn.text = "Ocupantes (%d)" % _occupants.size()
	for c in _occ_list.get_children():
		_occ_list.remove_child(c)
		c.queue_free()
	for occ in _occupants:
		var nick = str(occ.get("nick", ""))
		var jid = str(occ.get("jid", ""))
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 2)
		var b = Button.new()
		b.text = nick + (" (yo)" if nick == _room_nick else "")
		b.flat = true
		b.align = Button.ALIGN_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.add_color_override("font_color", Bubble.color_for(nick))
		b.connect("pressed", self, "_on_occupant_pick", [nick])
		row.add_child(b)
		# Moderación: sólo sobre otros y si tenemos permiso.
		if nick != _room_nick and _can_moderate():
			var mb = Button.new()
			mb.text = "⋯"
			mb.flat = true
			mb.focus_mode = Control.FOCUS_NONE
			mb.connect("pressed", self, "_open_occupant_menu", [nick, jid, occ])
			row.add_child(mb)
		_occ_list.add_child(row)

func _can_admin() -> bool:
	return _room_affiliation == "owner" or _room_affiliation == "admin"

func _can_moderate() -> bool:
	return _can_admin() or _room_role == "moderator"

func _open_occupant_menu(p_nick: String, p_jid: String, p_occ: Dictionary) -> void:
	_occ_action_ctx = {"nick": p_nick, "jid": p_jid}
	_occ_action_menu.clear()
	var aff = str(p_occ.get("affiliation", ""))
	var role = str(p_occ.get("role", ""))
	if _can_admin():
		if aff != "member":
			_occ_action_menu.add_item("Hacer miembro", 1)
		if aff == "member":
			_occ_action_menu.add_item("Quitar miembro", 2)
		if aff != "admin":
			_occ_action_menu.add_item("Hacer admin", 3)
		if aff == "admin":
			_occ_action_menu.add_item("Quitar admin", 4)
		if role != "moderator":
			_occ_action_menu.add_item("Hacer moderador", 5)
		if role == "moderator":
			_occ_action_menu.add_item("Quitar moderador", 6)
		_occ_action_menu.add_separator()
		_occ_action_menu.add_item("Expulsar", 7)
		_occ_action_menu.add_item("Expulsar y banear", 8)
	elif _can_moderate():
		_occ_action_menu.add_item("Expulsar", 7)
	_occ_action_menu.popup_centered()

func _on_occ_action(p_id: int) -> void:
	var nick = str(_occ_action_ctx.get("nick", ""))
	var jid = str(_occ_action_ctx.get("jid", ""))
	var action = {1: "member", 2: "unmember", 3: "admin", 4: "unadmin", 5: "moderator", 6: "unmoderator", 7: "kick", 8: "ban"}.get(p_id, "")
	if action == "":
		return
	_occ_popup.hide()
	emit_signal("occupant_action", _room, nick, jid, action)

func _open_room_menu() -> void:
	_room_menu.clear()
	_room_menu.add_item("Invitar a contacto", 10)
	_room_menu.add_item("Cambiar tema", 11)
	if _can_admin():
		_room_menu.add_separator()
		_room_menu.add_item("Ajustes de sala", 20)
	if _room_affiliation == "owner":
		_room_menu.add_item("Destruir sala", 21)
	_room_menu.popup_centered()

func _on_room_menu(p_id: int) -> void:
	match p_id:
		10:
			emit_signal("room_invite_requested")
		11:
			emit_signal("room_subject_requested")
		20:
			emit_signal("room_settings_requested")
		21:
			emit_signal("room_destroy_requested")

func _toggle_occupants() -> void:
	if _occ_popup.visible:
		_occ_popup.hide()
		return
	_refresh_occupants()
	_occ_popup.popup_centered()

func _on_occupant_pick(p_nick: String) -> void:
	_occ_popup.hide()
	_insert_mention(p_nick)

func _on_nick_clicked(p_nick: String) -> void:
	_insert_mention(p_nick)

# Inserta `@nick ` en la posición del cursor del composer y le da foco.
func _insert_mention(p_nick: String) -> void:
	if p_nick == "":
		return
	_input.insert_text_at_cursor("@" + p_nick + " ")
	if not (OS.get_name() in ["Android", "iOS"]):
		_input.grab_focus()
	_fit_input()
	_update_tail()

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
	_fill_rows(p_rows)
	_render_seq += 1
	_rebuild()

# Igual que `set_history`, pero construye las burbujas repartidas en varios
# frames (RENDER_CHUNK por frame). El modelo queda listo al instante; la UI se
# puede pintar ya aunque el render tarde. `p_unread_from` es el índice del primer
# mensaje no leído (<0 = sin marcador).
func set_history_deferred(p_rows: Array, p_unread_from: int = -1) -> void:
	_fill_rows(p_rows)
	_render_seq += 1
	_unread_idx = p_unread_from if p_unread_from >= 0 and p_unread_from < _messages.size() else -1
	_render_chunked(_render_seq)

func _fill_rows(p_rows: Array) -> void:
	_messages = []
	_limit = MAX_BUBBLES
	for r in p_rows:
		_messages.append({
			"from": _peer if r.get("sender", "") == "" else (_peer + "/" + str(r.get("sender", ""))),
			"to": "",
			"body": r.get("body", ""),
			"timestamp": r.get("ts", ""),
			"direction": r.get("direction", "in"),
			"id": r.get("request_id", ""),
			"quick_responses": r.get("quick", []),
			"commands": r.get("commands", []),
			"attach": r.get("attach", {}),
			"sender": r.get("sender", ""),
			"muc": _room != "",
		})

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
	if _room != "":
		return
	_typing = p_text
	_refresh_state()

# "pensando…" mientras el agente procesa (shimmer); gana sobre el chat state.
func set_thinking(p_on: bool) -> void:
	if _room != "":
		return
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
	# En salas no hay cards de aprobación ni quick responses (construcciones 1:1).
	if _room != "":
		return
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
	if _room != "":
		return
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
	_exit_selection()
	var keep = _begin_render()
	for i in range(_first, _messages.size()):
		_make_bubble(i, false)
	if p_settle:
		_end_render(keep)

# Deja la lista vacía para reconstruir. Devuelve la card activa a reanclar (o
# null), que el llamador debe re-adjuntar en `_end_render`.
func _begin_render():
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
	_more.visible = _first > 0
	return keep

func _end_render(keep) -> void:
	if keep != null:
		var host = _bubble_for(keep.msg_id)
		if host != null:
			host.attach(keep)
	if _unread_idx >= 0 and _unread_node != null:
		_to_marker()
	else:
		_to_bottom()

# Construye las burbujas por tandas de RENDER_CHUNK, cediendo el frame entre
# tandas. Si un render más nuevo arranca (otro contacto/MAM), `_render_seq`
# cambia y este se aborta sin tocar nada más.
func _render_chunked(p_seq: int) -> void:
	_exit_selection()
	var keep = _begin_render()
	var i: int = _first
	while i < _messages.size():
		if p_seq != _render_seq:
			return
		var stop = int(min(i + RENDER_CHUNK, _messages.size()))
		while i < stop:
			_make_bubble(i, false)
			i += 1
		if i < _messages.size():
			yield(get_tree(), "idle_frame")
	if p_seq != _render_seq:
		return
	_end_render(keep)

func _append_bubble(p_rec: Dictionary, p_new: bool) -> void:
	# Si `_bubbles` quedó desincronizado de `_messages[_first:]` (p. ej. un render
	# por tandas abortado por otro contacto), reconstruir en vez de indexar mal.
	if _bubbles.size() != _messages.size() - 1 - _first:
		_rebuild()
		return
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
		if b == _sel_bubble:
			_exit_selection()
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
	if same_prev and _bub(i - 1) != null:
		_bub(i - 1).set_group_last(false)
	var gap = Palette.GAP if sep else (0 if i == _first else (Palette.GAP if same_prev else Palette.GROUP_GAP))
	var b = Bubble.new()
	b.connect("media_action", self, "_on_bubble_media_action")
	b.connect("nick_clicked", self, "_on_nick_clicked")
	b.set_record(rec, last, p_new, gap, p_new and dir == "in")
	# Chip de remitente en salas: sólo el primer mensaje de cada grupo entrante.
	if _room != "" and dir == "in":
		var nick = _sender_of(rec)
		var prev_same_sender = same_prev and i > _first and _sender_of(_messages[i - 1]) == nick
		if nick != "" and not prev_same_sender:
			b.set_sender(nick, Bubble.color_for(nick))
	_list.add_child(b)
	_bubbles.append(b)

# Remitente de un mensaje de sala: campo `sender` (store) o el recurso del
# `from` (vivo/MAM vienen como room/nick).
func _sender_of(p_rec: Dictionary) -> String:
	var s = str(p_rec.get("sender", ""))
	if s != "":
		return s
	var frm = str(p_rec.get("from", ""))
	var slash = frm.find("/")
	return "" if slash < 0 else frm.substr(slash + 1)

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
	# Desplazar sale del modo selección (el texto ya no está donde se tocó).
	if _sel_bubble != null:
		_exit_selection()
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
	if not (p_ev is InputEventKey) or not p_ev.pressed or p_ev.echo:
		return
	if p_ev.scancode != KEY_ENTER and p_ev.scancode != KEY_KP_ENTER:
		return
	# Móvil: Enter inserta salto de línea (se envía con el botón cola).
	if _is_mobile():
		return
	# Escritorio: Shift+Enter inserta salto de línea; Enter / Ctrl+Enter envían.
	if p_ev.shift:
		return
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
	_update_tail()
	if juice != null:
		juice.play("send")
	_clear_unread()
	emit_signal("message_submitted", _peer, text)

