extends Control

# Punto de entrada de xat. Construye la UI por código y la conecta a una
# `Session` (que a su vez maneja el nodo nativo XmppConnection). Fase 3.

const SessionScript = preload("res://addons/xat_xmpp/xmpp/session.gd")
const AccountPanel = preload("res://addons/xat_xmpp/ui/account_panel.gd")
const RosterPanel = preload("res://addons/xat_xmpp/ui/roster_panel.gd")
const ChatPanel = preload("res://addons/xat_xmpp/ui/chat_panel.gd")
const CommandDialog = preload("res://addons/xat_xmpp/ui/command_dialog.gd")
const Credentials = preload("res://addons/xat_xmpp/xmpp/credentials.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")
const MindPanel = preload("res://addons/xat_xmpp/ui/mind_panel.gd")
const AgentOrb = preload("res://addons/xat_xmpp/ui/agent_orb.gd")
const AvatarBadge = preload("res://addons/xat_xmpp/ui/avatar_badge.gd")
const Juice = preload("res://addons/xat_xmpp/ui/juice.gd")
const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const StartupSplash = preload("res://addons/xat_xmpp/ui/startup_splash.gd")

# Por debajo de este ancho el panel "mente" se oculta (se abre con el orbe del header).
const MIND_MIN_WIDTH := 1000
# Por debajo de este ancho: un panel por vez (roster o chat, con ←).
const SINGLE_PANE_MAX := 700
# Lado corto lógico en móvil. Al girar, se recalcula la base de stretch con este
# lado corto para que la letra no encoja en landscape (ver _apply_mobile_stretch).
const MOBILE_BASE_SHORT := 420.0

var session
var _account
var _roster
var _chat
var _split
var _mind
var _mind_pinned := false # abierto a mano en pantallas angostas
var _header_orb
var _header_avatar
var _show_roster := true # vista de un panel: qué se ve
var _kb_timer: Timer
var juice
var _last_tool := {} # bare -> tool en curso (para abrir/cerrar tool cards)
var _unread := {} # bare -> mensajes vivos llegados sin tener el chat abierto
var _cmd_dialog
var _credentials
var _startup_splash
var _startup_cfg := {}
var _pending_cfg := {}
var _pending_command := {}
var _peer := ""
var _stretch_base := Vector2.ZERO

func _ready() -> void:
	theme = XatTheme.build()
	juice = Juice.new()
	add_child(juice)
	# Zoom tipográfico persistido (Ctrl+scroll / Ctrl+±): aplicar antes de armar
	# la UI para que las fuentes nazcan ya al tamaño guardado.
	var fz = get_node_or_null("/root/FontZoom")
	if fz != null:
		fz.set_scale(float(juice.settings.get("font_scale", 1.0)))
	session = SessionScript.new()
	session.name = "Session"
	add_child(session)
	session.connect("state_changed", self, "_on_state_changed")
	session.connect("roster_changed", self, "_on_roster_changed")
	session.connect("presence_changed", self, "_on_presence_changed")
	session.connect("message_received", self, "_on_message_received")
	session.connect("message_corrected", self, "_on_message_corrected")
	session.connect("chat_state_received", self, "_on_chat_state")
	session.connect("history_fetched", self, "_on_history_fetched")
	session.connect("command_form", self, "_on_command_form")
	session.connect("command_response", self, "_on_command_response")
	session.connect("log_message", self, "_on_log")
	session.connect("delivery_received", self, "_on_delivery")
	session.connect("auth_failed", self, "_on_auth_failed")
	session.connect("avatar_changed", self, "_on_avatar_changed")
	session.connect("agent_state_changed", self, "_on_agent_state")
	session.connect("agent_hook", self, "_on_agent_hook")

	_account = AccountPanel.new()
	_account.anchor_right = 1.0
	_account.anchor_bottom = 1.0
	add_child(_account)
	_account.connect("connect_requested", self, "_on_connect_requested")

	_credentials = Credentials.new()
	var saved = _credentials.load_with_env(Credentials.DEFAULT_PATH)
	if _has_login_credentials(saved):
		_account.prefill(saved)
		if OS.get_environment("XAT_AUTOCONNECT") != "0":
			_startup_cfg = _account.config()
			# Se oculta ya, antes del primer frame visible.
			_account.visible = false

	_split = HBoxContainer.new()
	_split.add_constant_override("separation", 0)
	_split.anchor_right = 1.0
	_split.anchor_bottom = 1.0
	_split.visible = false
	add_child(_split)
	_roster = RosterPanel.new()
	_split.add_child(_roster)
	_roster.connect("peer_selected", self, "_on_peer_selected")
	_roster.set_juice(juice)
	_chat = ChatPanel.new()
	_split.add_child(_chat)
	_chat.connect("message_submitted", self, "_on_message_submitted")
	_chat.connect("action_selected", self, "_on_action_selected")
	_chat.connect("quick_selected", self, "_on_quick_selected")
	_chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mind = MindPanel.new()
	_mind.visible = false
	_split.add_child(_mind)
	_mind.connect("command_requested", self, "_on_agent_command")
	_mind.connect("back_requested", self, "_on_mind_back")
	# Mini-orbe en el header del chat: abre/cierra la mente en pantallas angostas.
	_header_avatar = AvatarBadge.new(34.0)
	_chat.header_slot.add_child(_header_avatar)
	_header_orb = AgentOrb.new()
	_header_orb.set_compact(true)
	_header_orb.visible = false
	_chat.header_slot.add_child(_header_orb)
	_header_orb.connect("clicked", self, "_on_header_orb")
	connect("resized", self, "_update_mind_visibility")
	connect("resized", self, "_apply_mobile_stretch")
	connect("resized", self, "_update_safe_area")
	_chat.connect("back_requested", self, "_on_back")
	# Móvil: el teclado virtual tapa el composer; se sigue su altura.
	if OS.has_feature("mobile"):
		_kb_timer = Timer.new()
		_kb_timer.wait_time = 0.25
		_kb_timer.autostart = true
		_kb_timer.connect("timeout", self, "_follow_keyboard")
		add_child(_kb_timer)

	_cmd_dialog = CommandDialog.new()
	add_child(_cmd_dialog)
	_cmd_dialog.connect("submitted", self, "_on_command_submitted")
	if not _startup_cfg.empty():
		_startup_splash = StartupSplash.new()
		_startup_splash.connect("canceled", self, "_on_startup_canceled")
		_startup_splash.connect("completed", self, "_on_startup_completed")
		add_child(_startup_splash)
		_startup_splash.start()
		call_deferred("_autoconnect")
	# Con la UI ya armada, fijar la base de stretch móvil (landscape/portrait).
	_apply_mobile_stretch()
	_update_safe_area()

func _autoconnect() -> void:
	if not _startup_cfg.empty():
		_on_connect_requested(_startup_cfg)

func _has_login_credentials(p_cfg: Dictionary) -> bool:
	return str(p_cfg.get("jid", "")).strip_edges() != "" and str(p_cfg.get("password", p_cfg.get("pass", ""))) != ""

func _on_connect_requested(p_cfg: Dictionary) -> void:
	_pending_cfg = p_cfg
	_account.set_busy(true)
	var rc = session.connect_account(p_cfg["jid"], p_cfg["pass"], p_cfg.get("host", ""), p_cfg.get("port", 5222), p_cfg.get("cafile", ""))
	if rc != 0:
		_account.set_busy(false)
		_account.set_status("No se pudo iniciar la conexión (código %d)." % rc)
		if _startup_splash != null:
			_startup_splash.finish("error")

func _on_state_changed(p_state: int) -> void:
	print("xat: estado %d" % p_state)
	match p_state:
		SessionScript.State.CONNECTING:
			_account.set_busy(true)
		SessionScript.State.CONNECTED:
			_account.set_busy(false)
			_account.set_status("Conectado como %s" % session.bare())
			_account.visible = false
			_split.visible = true
			if _startup_splash != null:
				_startup_splash.show_success()
			# Fijar el layout ya (móvil: un panel; escritorio: ambos). Sin esto
			# dependía de un resize posterior y podía quedar en dos paneles.
			_update_mind_visibility()
			# Persistir la cuenta recién conectada (archivo 0600).
			if not _pending_cfg.empty():
				_credentials.save(Credentials.DEFAULT_PATH, _pending_cfg)
				_pending_cfg = {}
		SessionScript.State.RECONNECTING:
			_account.set_status("Reconectando…")
		SessionScript.State.DISCONNECTED:
			_account.set_busy(false)
			_account.set_status("Desconectado.")

func _on_roster_changed() -> void:
	_roster.set_peers(session.roster_model.bare_jids())
	# Orden por actividad: último mensaje guardado de cada contacto.
	for b in session.roster_model.bare_jids():
		var last = session.get_recent_history(b, 1)
		if not last.empty():
			_roster.touch(b, str(last.back().get("ts", "")))
	print("xat: roster con %d contactos" % session.roster_model.bare_jids().size())

func _on_presence_changed(p_bare: String) -> void:
	_roster.set_online(p_bare, session.presence_model.is_online(p_bare))
	if p_bare == _peer:
		_mind.set_connected(session.presence_model.is_online(p_bare))

func _on_peer_selected(p_bare: String) -> void:
	_peer = p_bare
	_header_avatar.bare = p_bare
	_header_avatar.set_texture(session.avatars.get(p_bare))
	_mind.set_agent(p_bare)
	_mind.set_state(session.agent_model.get_state(p_bare) if session.agent_model.has_agent(p_bare) else {})
	_mind.set_connected(session.presence_model.is_online(p_bare))
	if session.agent_model.has_agent(p_bare):
		_header_orb.set_state(session.agent_model.get_state(p_bare))
	_last_tool[p_bare] = ""
	_show_roster = false
	_update_mind_visibility()
	# En móvil no auto-enfocar el composer: abriría el teclado virtual solo.
	if not (OS.get_name() in ["Android", "iOS"]):
		_chat.focus_composer()
	_chat.set_peer(p_bare)
	_chat.set_history(session.get_recent_history(p_bare))
	var n = int(_unread.get(p_bare, 0))
	if n > 0:
		_chat.mark_unread_from(-n)
		_unread[p_bare] = 0
		_roster.set_unread(p_bare, 0)
	session.load_history(p_bare)

func _on_message_submitted(p_bare: String, p_text: String) -> void:
	var rc = session.send_message(p_bare, p_text)
	_roster.touch(p_bare, _now_iso())
	if rc == 0:
		juice.play("send")
		juice.haptic("tick")
	_chat.add_message({
		"from": session.bare(),
		"to": p_bare,
		"body": p_text,
		"direction": "out",
		"timestamp": _now_iso(),
		"id": session.last_sent_id if rc == 0 else "",
		"commands": [],
		"quick_responses": [],
	})

func _on_message_received(p_rec: Dictionary) -> void:
	# Salientes (carbons/MAM propios): el peer es `to`.
	var peer = p_rec.get("to", "") if p_rec.get("direction", "in") == "out" else p_rec.get("from", "")
	if peer == "":
		peer = p_rec.get("to", "")
	peer = _bare(peer)
	_roster.touch(peer, str(p_rec.get("timestamp", "")) if str(p_rec.get("timestamp", "")) != "" else _now_iso())
	# Sonido sólo para mensajes vivos entrantes (no MAM, no carbons propios, no viejos).
	if p_rec.get("direction", "in") != "out" and not p_rec.get("is_mam", false) and not p_rec.get("stale", false) and str(p_rec.get("body", "")) != "":
		juice.play("receive")
		juice.haptic("receive")
	if peer == _peer:
		_chat.add_message(p_rec)
	elif p_rec.get("direction", "in") != "out" and not p_rec.get("is_mam", false) and str(p_rec.get("body", "")) != "":
		_unread[peer] = int(_unread.get(peer, 0)) + 1
		_roster.set_unread(peer, _unread[peer])

func _on_message_corrected(p_rec: Dictionary) -> void:
	if _bare(p_rec.get("from", "")) == _peer:
		_chat.apply_correction(p_rec)

func _on_chat_state(p_bare: String, p_state: String) -> void:
	if p_bare == _peer:
		if p_state == "composing":
			_chat.set_chat_state("escribiendo…")
		elif p_state == "active":
			_chat.set_chat_state("")

func _on_history_fetched(p_bare: String, p_rows: Array, _p_complete: bool) -> void:
	if p_bare == _peer and not p_rows.empty():
		_chat.set_history(p_rows)

func _on_action_selected(p_bare: String, p_item) -> void:
	_celebrate()
	session.execute_command(str(p_item.get("jid", p_bare)), str(p_item.get("node", "")))

func _on_quick_selected(p_bare: String, p_value: String) -> void:
	_celebrate()
	session.send_message(p_bare, p_value)

func _on_command_form(p_from_jid: String, p_resp: Dictionary) -> void:
	_pending_command = {
		"jid": p_from_jid,
		"node": p_resp.get("node", ""),
		"sessionid": p_resp.get("sessionid", ""),
	}
	_cmd_dialog.open_form("Comando: " + str(p_resp.get("node", "")), p_resp.get("form", {}))
	_cmd_dialog.popup_centered()

func _on_command_submitted(p_fields: Array) -> void:
	if _pending_command.empty():
		return
	session.submit_command(_pending_command["jid"], _pending_command["node"], _pending_command["sessionid"], p_fields)

func _on_agent_state(p_bare: String, p_state: Dictionary) -> void:
	_roster.set_agent_state(p_bare, p_state)
	_sync_tool(p_bare, str(p_state.get("tool", "")))
	if p_bare == _peer:
		_mind.set_state(p_state)
		_header_orb.set_state(p_state)
		_chat.set_thinking(str(p_state.get("activity", "")) in ["processing", "busy"])
		_update_mind_visibility()

# Telemetría trae sólo la tool actual: un cambio cierra la card previa y abre otra.
func _sync_tool(p_bare: String, p_tool: String) -> void:
	var prev = _last_tool.get(p_bare, "")
	if p_tool == prev:
		return
	_last_tool[p_bare] = p_tool
	if p_bare != _peer:
		return
	if prev != "":
		_chat.tool_finished(true)
		if p_tool == "":
			juice.play("tool_done")
	if p_tool != "":
		_chat.tool_started(p_tool)
		juice.play("tool_start")
		juice.haptic("tick")

# Panel "mente" sólo para agentes (con telemetría) y si hay ancho, o fijado a mano.
func _update_mind_visibility() -> void:
	var is_agent = _peer != "" and session.agent_model.has_agent(_peer)
	var single = _single_pane()
	# Un solo panel (móvil/angosto): la mente ocupa toda la pantalla. Ancho: sólo
	# convive con los demás paneles si hay espacio o si se fijó a mano.
	var mind = is_agent and (_mind_pinned if single else (rect_size.x >= MIND_MIN_WIDTH or _mind_pinned))
	_update_panes(single, mind)
	_mind.visible = mind
	_mind.set_back_visible(mind and single)
	# El mini-orbe del header aparece cuando la mente no cabe, o siempre en un
	# solo panel (móvil/landscape) para poder abrirla.
	_header_orb.visible = is_agent and (single or rect_size.x < MIND_MIN_WIDTH)

# Un panel por vez: pantalla angosta, o móvil en landscape (ahí se colapsa el
# roster y el nombre/orbe del agente quedan fijos en el header, a la derecha).
func _single_pane() -> bool:
	if rect_size.x < SINGLE_PANE_MAX:
		return true
	return _is_mobile_landscape()

func _is_mobile_landscape() -> bool:
	return OS.get_name() in ["Android", "iOS"] and rect_size.x > rect_size.y

func _on_agent_command(p_node: String) -> void:
	var res = session.presence_model.best(_peer)
	if res == null:
		_mind.show_note("El agente no está en línea")
		return
	session.execute_command(str(res["full"]), p_node)

# Comandos sin formulario (status/context/compact…): sus notas salen del orbe.
func _on_command_response(p_resp: Dictionary) -> void:
	if p_resp.get("form") != null and str(p_resp["form"].get("type", "")) == "form":
		return
	for n in p_resp.get("notes", []):
		_mind.show_note(str(n.get("text", "")))

func _on_agent_hook(p_bare: String, p_hook: Dictionary) -> void:
	if p_bare != _peer:
		return
	match str(p_hook.get("event", "")):
		"approval":
			_chat.apply_approval_hook(p_hook)
			if str(p_hook.get("state", "")) == "pending":
				juice.play("alert")
				juice.haptic("alert")
		"progress":
			# Fin de turno: nada sigue "pensando" ni ejecutando.
			if str(p_hook.get("state", "")) == "end":
				_chat.set_thinking(false)
				if _last_tool.get(p_bare, "") != "":
					_last_tool[p_bare] = ""
					_chat.tool_finished(true)

# Decisión de aprobación: chime + chispas donde se hizo clic.
func _celebrate() -> void:
	juice.play("approve")
	juice.burst(get_global_mouse_position(), P.OK)
	juice.haptic("success")

# Angosto: un panel por vez (roster, chat o mente); ancho: ambos (+ mente si cabe).
func _update_panes(p_single: bool, p_mind: bool) -> void:
	if p_single:
		var roster = _peer == "" or _show_roster
		_roster.visible = roster and not p_mind
		_chat.visible = not roster and not p_mind
	else:
		_roster.visible = true
		_chat.visible = true
	_roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL if p_single else 0
	_mind.size_flags_horizontal = Control.SIZE_EXPAND_FILL if p_single else 0
	_chat.back_button.visible = p_single and _chat.visible

func _on_back() -> void:
	_show_roster = true
	_mind_pinned = false
	_update_mind_visibility()

func _on_mind_back() -> void:
	_mind_pinned = false
	_update_mind_visibility()

# Atrás del sistema (Android): cierra la mente o vuelve al roster según el panel.
func _notification(p_what: int) -> void:
	if p_what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var single = _single_pane()
		if _mind_pinned:
			_on_mind_back()
		elif single and _chat.visible:
			_on_back()

# En móvil la base de stretch del proyecto es portrait (420x880): al girar a
# landscape Godot encogería todo para encajar la altura y la letra se ve chica.
# Se recalcula la base con el mismo aspecto que la ventana y lado corto fijo, de
# modo que la densidad (y la letra) es igual en portrait y en landscape. La señal
# resized re-ejecuta esto al girar; el guard evita bucles de re-stretch.
func _apply_mobile_stretch() -> void:
	if not (OS.get_name() in ["Android", "iOS"]):
		return
	var w = OS.window_size
	if w.x <= 0.0 or w.y <= 0.0:
		return
	var base = w * (MOBILE_BASE_SHORT / min(w.x, w.y))
	if base.is_equal_approx(_stretch_base):
		return
	_stretch_base = base
	# Diferido: no reentrar el layout durante la propia señal resized.
	call_deferred("_do_stretch", base)

func _do_stretch(p_base: Vector2) -> void:
	get_tree().set_screen_stretch(SceneTree.STRETCH_MODE_2D, SceneTree.STRETCH_ASPECT_EXPAND, p_base)
	# La base cambió: recomponer el layout de paneles con el ancho lógico nuevo.
	_update_mind_visibility()
	_update_safe_area()

# Móvil: deja sitio para el notch/recorte superior (si no, tapa el margen del
# roster y la cabecera). get_window_safe_area() viene en píxeles de pantalla.
func _update_safe_area() -> void:
	if not (OS.get_name() in ["Android", "iOS"]):
		return
	var safe = OS.get_window_safe_area()
	var win_h = OS.window_size.y
	if safe.position.y <= 0.0 or win_h <= 0.0 or rect_size.y <= 0.0:
		return
	_split.margin_top = safe.position.y * (rect_size.y / win_h)

func _follow_keyboard() -> void:
	var kb = OS.get_virtual_keyboard_height()
	var ratio = get_viewport().get_visible_rect().size.y / max(1.0, OS.window_size.y)
	_split.margin_bottom = -kb * ratio

func _on_header_orb() -> void:
	_mind_pinned = not _mind_pinned
	_update_mind_visibility()

# Zoom de letra como en un navegador: Ctrl+scroll, Ctrl+= y Ctrl+-.
func _input(p_event) -> void:
	# Un clic en cualquier lado quita la selección de texto del chat (el doble/
	# triple clic la vuelven a crear después, en el propio RichTextLabel).
	if p_event is InputEventMouseButton and p_event.pressed and p_event.button_index == BUTTON_LEFT:
		if _chat != null:
			_chat.deselect_all()
	if p_event is InputEventMouseButton and p_event.control and p_event.pressed:
		if p_event.button_index == BUTTON_WHEEL_UP:
			_zoom(1)
		elif p_event.button_index == BUTTON_WHEEL_DOWN:
			_zoom(-1)
	elif p_event is InputEventKey and p_event.pressed and not p_event.echo and p_event.control:
		if p_event.scancode in [KEY_EQUAL, KEY_KP_ADD]:
			_zoom(1)
		elif p_event.scancode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			_zoom(-1)
		elif p_event.scancode == KEY_0:
			var fz = get_node_or_null("/root/FontZoom")
			if fz != null:
				fz.reset()
				_persist_scale()
				_roster.refresh()
				_chat.refit_scroll()
			get_tree().set_input_as_handled()

func _zoom(p_dir: int) -> void:
	var fz = get_node_or_null("/root/FontZoom")
	if fz == null:
		return
	if p_dir > 0:
		fz.zoom_in()
	else:
		fz.zoom_out()
	_persist_scale()
	_roster.refresh() # recalcula los anchos medidos (clip_text) al nuevo tamaño
	_chat.refit_scroll() # conserva el punto de lectura al cambiar la letra
	get_tree().set_input_as_handled()

func _persist_scale() -> void:
	var fz = get_node_or_null("/root/FontZoom")
	if fz != null and juice != null:
		juice.set_setting("font_scale", fz.scale)

func _on_avatar_changed(p_bare: String, p_tex) -> void:
	_roster.set_avatar(p_bare, p_tex)
	if p_bare == _peer:
		_header_avatar.set_texture(p_tex)

func _on_auth_failed() -> void:
	_account.visible = true
	_split.visible = false
	_account.set_busy(false)
	_account.set_status("Usuario o contraseña incorrectos.")
	if _startup_splash != null:
		_startup_splash.finish("auth_failed")
	juice.play("alert")
	juice.shake(_account)
	juice.haptic("error")

func _on_startup_canceled() -> void:
	var splash = _startup_splash
	_startup_splash = null
	_pending_cfg = {}
	session.disconnect_account()
	_account.visible = true
	_account.set_busy(false)
	_account.set_status("Conexión cancelada.")
	if splash != null:
		splash.queue_free()

func _on_startup_completed(p_outcome: String) -> void:
	var splash = _startup_splash
	_startup_splash = null
	if p_outcome == "timeout":
		_pending_cfg = {}
		session.disconnect_account()
	if p_outcome != "connected":
		_account.visible = true
		_split.visible = false
		_account.set_busy(false)
		if p_outcome == "timeout":
			_account.set_status("La conexión tarda más de lo esperado. Puedes reintentar.")
	if splash != null:
		splash.queue_free()

func _on_delivery(p_id: String, p_bare: String) -> void:
	if p_bare == _peer:
		_chat.mark_delivered(p_id)

func _on_log(_level: int, _msg: String) -> void:
	pass

func _bare(p_jid: String) -> String:
	var slash = p_jid.find("/")
	if slash < 0:
		return p_jid
	return p_jid.substr(0, slash)

func _now_iso() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"
