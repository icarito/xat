extends Control

# Punto de entrada de xat. Construye la UI por código y la conecta a una
# `Session` (que a su vez maneja el nodo nativo XmppConnection). Fase 3.

const SessionScript = preload("res://addons/xat_xmpp/xmpp/session.gd")
const AccountPanel = preload("res://addons/xat_xmpp/ui/account_panel.gd")
const RosterPanel = preload("res://addons/xat_xmpp/ui/roster_panel.gd")
const AddContactDialog = preload("res://addons/xat_xmpp/ui/add_contact_dialog.gd")
const JoinRoomDialog = preload("res://addons/xat_xmpp/ui/join_room_dialog.gd")
const InviteDialog = preload("res://addons/xat_xmpp/ui/invite_dialog.gd")
const TextPromptDialog = preload("res://addons/xat_xmpp/ui/text_prompt_dialog.gd")
const ChatPanel = preload("res://addons/xat_xmpp/ui/chat_panel.gd")
const IconButton = preload("res://addons/xat_xmpp/ui/icon_button.gd")
const CommandDialog = preload("res://addons/xat_xmpp/ui/command_dialog.gd")
const Credentials = preload("res://addons/xat_xmpp/xmpp/credentials.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")
const MindPanel = preload("res://addons/xat_xmpp/ui/mind_panel.gd")
const AgentOrb = preload("res://addons/xat_xmpp/ui/agent_orb.gd")
const AvatarBadge = preload("res://addons/xat_xmpp/ui/avatar_badge.gd")
const Juice = preload("res://addons/xat_xmpp/ui/juice.gd")
const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const StartupSplash = preload("res://addons/xat_xmpp/ui/startup_splash.gd")
const Recorder = preload("res://addons/xat_xmpp/xmpp/recorder.gd")
const CameraCapture = preload("res://addons/xat_xmpp/xmpp/camera.gd")
const Media = preload("res://addons/xat_xmpp/xmpp/media.gd")
const MediaUtil = preload("res://addons/xat_xmpp/ui/media_util.gd")
const MediaLightbox = preload("res://addons/xat_xmpp/ui/media_lightbox.gd")
const Notifier = preload("res://addons/xat_xmpp/ui/notifier.gd")
const Push = preload("res://addons/xat_xmpp/xmpp/push.gd")
const FilePicker = preload("res://addons/xat_xmpp/ui/file_picker.gd")
const ClipboardImage = preload("res://addons/xat_xmpp/ui/clipboard_image.gd")
const XatXmpp = preload("res://addons/xat_xmpp/xat_xmpp.gd")

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
var _add_contact
var _join_room
var _invite_dialog
var _prompt_dialog
var _room_settings
var _prompt_ctx := {}
var _sidebar
var _sidebar_title
var _sidebar_identity
var _sb_add
var _sb_room
var _sb_occ
var _sb_act
var _sb_leave
var _sb_sound
var _sb_haptic
var _sb_profile
var _sb_about
var _credentials
var _startup_splash
var _startup_cfg := {}
var _pending_cfg := {}
var _pending_command := {}
var _peer := ""
var _stretch_base := Vector2.ZERO
var _recorder
var _lightbox
var _audio: AudioStreamPlayer
var _media_pending := {} # message_id -> acción pendiente tras descargar la media
var _rec_timer: Timer
var _rec_start_ms := 0
var _playing_path := ""
var _native_media = null          # singleton XatMedia (selector/cámara nativa)
var _pending_media_peer := ""     # peer que espera el resultado del selector
var _pending_avatar := false      # el selector está eligiendo la foto de perfil
var _avatar_picker               # FilePicker nativo para la foto de perfil
var _avatar_file_dialog          # fallback FileDialog para la foto de perfil
var _clipboard                   # ClipboardImage (pegar imagen en escritorio)
var _notifier

func _ready() -> void:
	theme = XatTheme.build()
	juice = Juice.new()
	add_child(juice)
	_notifier = Notifier.new()
	_notifier.name = "Notifier"
	add_child(_notifier)
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
	session.connect("media_upload_state", self, "_on_media_upload_state")
	session.connect("media_ready", self, "_on_media_ready")
	session.connect("media_failed", self, "_on_media_failed")
	session.connect("subscription_request", self, "_on_subscription_request")
	session.connect("push_registration_changed", self, "_on_push_registration_changed")
	session.connect("muc_joined", self, "_on_muc_joined")
	session.connect("muc_left", self, "_on_muc_left")
	session.connect("muc_subject", self, "_on_muc_subject")
	session.connect("muc_occupants_changed", self, "_on_muc_occupants_changed")
	session.connect("muc_invite", self, "_on_muc_invite")
	session.connect("muc_error", self, "_on_muc_error")
	session.connect("muc_config_form", self, "_on_muc_config_form")

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
	_roster.connect("add_contact_requested", self, "_on_add_contact_requested")
	_roster.connect("subscription_accept", self, "_on_subscription_accept")
	_roster.connect("subscription_deny", self, "_on_subscription_deny")
	_roster.connect("avatar_requested", self, "_on_avatar_requested")
	_roster.connect("join_room_requested", self, "_on_join_room_requested")
	_roster.connect("room_invite_accept", self, "_on_room_invite_accept")
	_roster.connect("room_invite_ignore", self, "_on_room_invite_ignore")
	_roster.set_juice(juice)
	_chat = ChatPanel.new()
	_split.add_child(_chat)
	_chat.set_juice(juice)
	_chat.connect("message_submitted", self, "_on_message_submitted")
	_chat.connect("action_selected", self, "_on_action_selected")
	_chat.connect("quick_selected", self, "_on_quick_selected")
	_chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mind = MindPanel.new()
	_mind.visible = false
	_split.add_child(_mind)
	_mind.connect("command_requested", self, "_on_agent_command")
	_mind.connect("back_requested", self, "_on_mind_back")
	# Sidebar de navegación/acciones (sólo móvil landscape), a la derecha.
	_build_sidebar()
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
	_chat.connect("attach_picked", self, "_on_attach_picked")
	_chat.connect("attach_requested", self, "_on_attach_requested")
	_chat.connect("camera_requested", self, "_on_camera_requested")
	_chat.connect("voice_toggle", self, "_on_voice_toggle")
	_chat.connect("voice_cancel", self, "_on_voice_cancel")
	_chat.connect("media_action", self, "_on_media_action")
	_chat.connect("text_copied", self, "_on_text_copied")
	_chat.connect("room_leave_requested", self, "_on_room_leave_requested")
	_chat.connect("room_invite_requested", self, "_on_room_invite_requested")
	_chat.connect("room_settings_requested", self, "_on_room_settings_requested")
	_chat.connect("room_subject_requested", self, "_on_room_subject_requested")
	_chat.connect("room_destroy_requested", self, "_on_room_destroy_requested")
	_chat.connect("occupant_action", self, "_on_occupant_action")
	_recorder = Recorder.new()
	_recorder.name = "Recorder"
	add_child(_recorder)
	_audio = AudioStreamPlayer.new()
	_audio.name = "MediaAudio"
	_audio.connect("finished", self, "_on_audio_finished")
	add_child(_audio)
	_lightbox = MediaLightbox.new()
	add_child(_lightbox)
	_rec_timer = Timer.new()
	_rec_timer.wait_time = 0.2
	_rec_timer.connect("timeout", self, "_tick_recording")
	add_child(_rec_timer)
	_setup_native_media()
	if ClipboardImage.available():
		_clipboard = ClipboardImage.new()
		_clipboard.name = "ClipboardImage"
		add_child(_clipboard)
		_clipboard.connect("pasted", self, "_on_clipboard_pasted")
	# En Android los permisos peligrosos (micrófono, media) se piden en runtime;
	# Godot no los pide solo aunque estén declarados en el manifiesto.
	if OS.get_name() == "Android":
		OS.request_permissions()
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
	_add_contact = AddContactDialog.new()
	add_child(_add_contact)
	_add_contact.connect("submitted", self, "_on_add_contact_submitted")
	_join_room = JoinRoomDialog.new()
	add_child(_join_room)
	_join_room.connect("submitted", self, "_on_join_room_submitted")
	_invite_dialog = InviteDialog.new()
	add_child(_invite_dialog)
	_invite_dialog.connect("submitted", self, "_on_invite_submitted")
	_prompt_dialog = TextPromptDialog.new()
	add_child(_prompt_dialog)
	_prompt_dialog.connect("submitted", self, "_on_prompt_submitted")
	_room_settings = CommandDialog.new()
	add_child(_room_settings)
	_room_settings.window_title = "Ajustes de sala"
	_room_settings.connect("submitted", self, "_on_room_settings_submitted")
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
	# Hook de desarrollo: pinta los paneles con datos falsos (sin conectar) para
	# revisar el layout. Uso: XAT_DEV_PANELS=1 XAT_LANDSCAPE=1.
	if OS.get_environment("XAT_DEV_PANELS") == "1":
		_dev_seed()

func _dev_seed() -> void:
	_account.visible = false
	_split.visible = true
	var peers = ["kangurito@hablar.fuentelibre.org", "lazaro@hablar.fuentelibre.org", "mateo@hablar.fuentelibre.org", "ana@hablar.fuentelibre.org", "beto@hablar.fuentelibre.org"]
	_roster.set_peers(peers)
	for p in peers.slice(0, 3):
		_roster.set_online(p, true)
	_roster.set_rooms(["agentes@conference.hablar.fuentelibre.org", "general@conference.hablar.fuentelibre.org"])
	_peer = peers[0]
	_roster.select(peers[0])
	_header_avatar.visible = true
	_header_avatar.bare = peers[0]
	_mind.set_agent(peers[0])
	_chat.set_peer(peers[0])
	for i in range(8):
		_chat.add_message({"from": peers[0], "body": "mensaje de prueba %d con algo de texto" % i, "direction": "in" if i % 2 == 0 else "out", "timestamp": "2026-03-01T10:%02d:00Z" % i, "id": "d%d" % i, "commands": [], "quick_responses": []})
	_show_roster = false
	_update_mind_visibility()

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
			if _notifier != null:
				_notifier.set_connected()
				if OS.get_name() in ["Android", "iOS"]:
					_notifier.request_permission()
				_register_push()
			if _startup_splash != null:
				_startup_splash.show_success()
			# Fijar el layout ya (móvil: un panel; escritorio: ambos). Sin esto
			# dependía de un resize posterior y podía quedar en dos paneles.
			_update_mind_visibility()
			_refresh_rooms()
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
	if _notifier != null:
		_notifier.clear(p_bare)
	if session.is_room(p_bare):
		_open_room(p_bare)
		return
	_header_avatar.visible = true
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
	# Cambio de vista instantáneo: el panel se muestra ya, aunque vacío. El
	# historial (consulta SQLite + render de burbujas) va en un frame posterior
	# para no bloquear el frame que pinta el cambio de panel.
	_chat.set_peer(p_bare)
	# En móvil no auto-enfocar el composer: abriría el teclado virtual solo.
	if not (OS.get_name() in ["Android", "iOS"]):
		_chat.focus_composer()
	_load_peer(p_bare)

# Carga diferida del historial: cambia la vista al instante y rellena después.
func _load_peer(p_bare: String) -> void:
	yield(get_tree(), "idle_frame")
	if p_bare != _peer:
		return
	var hist = session.get_recent_history(p_bare)
	if p_bare != _peer:
		return
	var n = int(_unread.get(p_bare, 0))
	if n > 0:
		_unread[p_bare] = 0
		_roster.set_unread(p_bare, 0)
	# Render por tandas: no bloquea la UI aunque haya muchas burbujas.
	_chat.set_history_deferred(hist, int(max(0, hist.size() - n)) if n > 0 else -1)
	# Miniaturas de imágenes ya guardadas en el historial (descargas async).
	for r in hist:
		var att = r.get("attach", {})
		if att is Dictionary and str(att.get("kind", "")) == "image" and str(att.get("local", "")) == "":
			session.ensure_media(p_bare, {"id": r.get("request_id", ""), "attach": att, "direction": "in"})
	session.load_history(p_bare)

# --- Salas (MUC) ---

func _refresh_rooms() -> void:
	var rooms := []
	for r in session.saved_rooms():
		rooms.append(str(r.get("bare_jid", "")))
	_roster.set_rooms(rooms)

func _open_room(p_room: String) -> void:
	_show_roster = false
	_header_avatar.visible = false
	_header_orb.visible = false
	_update_mind_visibility()
	_chat.set_room(p_room, session.room_nick(p_room), session.muc_occupants(p_room), session.muc_affiliation(p_room), session.muc_role(p_room))
	if not (OS.get_name() in ["Android", "iOS"]):
		_chat.focus_composer()
	_load_room(p_room)

func _load_room(p_room: String) -> void:
	yield(get_tree(), "idle_frame")
	if p_room != _peer:
		return
	var hist = session.get_recent_history(p_room)
	if p_room != _peer:
		return
	var n = int(_unread.get(p_room, 0))
	if n > 0:
		_unread[p_room] = 0
		_roster.set_unread(p_room, 0)
	_chat.set_history_deferred(hist, int(max(0, hist.size() - n)) if n > 0 else -1)
	# Backfill MAM de la sala (query to=sala, sin with).
	session.load_history(p_room)

func _on_join_room_requested() -> void:
	if session.state != SessionScript.State.CONNECTED:
		juice.toast("Conectate antes de unirte a una sala", P.ERROR)
		return
	_join_room.open(session.muc_conference())

func _on_join_room_submitted(p_room: String) -> void:
	# El nick en la sala es el del usuario (no se pregunta).
	var rc = session.join_room(p_room, session.bare().split("@")[0])
	if rc != 0:
		juice.play("alert")
		juice.toast("No se pudo unir a la sala", P.ERROR)
		return
	juice.haptic("tick")
	juice.toast("Uniéndose a %s…" % p_room)
	_refresh_rooms()
	if _peer != p_room:
		_on_peer_selected(p_room)

func _on_room_leave_requested() -> void:
	if _peer == "" or not session.is_room(_peer):
		return
	var room = _peer
	session.leave_room(room)
	_peer = ""
	_show_roster = true
	_header_avatar.visible = true
	_update_mind_visibility()
	_refresh_rooms()
	juice.toast("Saliste de la sala")

func _on_muc_joined(p_room: String) -> void:
	_refresh_rooms()
	if p_room == _peer:
		_chat.update_occupants(session.muc_occupants(p_room))
		_chat.set_room_caps(session.muc_affiliation(p_room), session.muc_role(p_room))
	juice.haptic("tick")

func _on_muc_left(p_room: String, _reason: String) -> void:
	_refresh_rooms()
	if p_room == _peer:
		_peer = ""
		_show_roster = true
		_header_avatar.visible = true
		_update_mind_visibility()
		juice.toast("Saliste de la sala")

func _on_muc_subject(p_room: String, p_subject: String) -> void:
	if p_room == _peer:
		_chat.set_room_subject(p_subject)

func _on_muc_occupants_changed(p_room: String) -> void:
	if p_room == _peer:
		_chat.update_occupants(session.muc_occupants(p_room))
		_chat.set_room_caps(session.muc_affiliation(p_room), session.muc_role(p_room))

# El servidor rechazó el join (sala bloqueada, sólo miembros, nick en uso).
func _on_muc_error(p_room: String, p_condition: String) -> void:
	_refresh_rooms()
	if p_room == _peer:
		_peer = ""
		_show_roster = true
		_header_avatar.visible = true
		_update_mind_visibility()
	var msg = "No se pudo entrar a la sala"
	if p_condition == "item-not-found":
		msg = "La sala no existe o todavía está bloqueada"
	elif p_condition == "conflict":
		msg = "Ese nick ya está en uso en la sala"
	elif p_condition in ["not-allowed", "registration-required", "forbidden"]:
		msg = "La sala es sólo para miembros"
	juice.play("alert")
	juice.toast(msg, P.ERROR)

func _on_muc_invite(p_room: String, p_from: String, p_reason: String) -> void:
	_roster.add_invite(p_room, p_from, p_reason)
	juice.play("alert")
	juice.haptic("alert")
	juice.toast("%s te invita a %s" % [_display_name(p_from), p_room])

func _on_room_invite_accept(p_room: String) -> void:
	_roster.remove_invite(p_room)
	if session.state != SessionScript.State.CONNECTED:
		return
	session.join_room(p_room, session.bare().split("@")[0])
	_refresh_rooms()
	_on_peer_selected(p_room)

func _on_room_invite_ignore(p_room: String) -> void:
	_roster.remove_invite(p_room)

# --- Acciones de sala (invitar / ajustes / tema / destruir / moderar) ---

func _on_room_invite_requested() -> void:
	if _peer == "" or not session.is_room(_peer):
		return
	var contacts := []
	for bare in session.roster_model.bare_jids():
		var it = session.roster_model.get_item(bare)
		contacts.append({"jid": str(bare), "name": str(it.get("name", "")) if it != null else ""})
	_invite_dialog.open(contacts)

func _on_invite_submitted(p_jid: String, p_reason: String) -> void:
	var room = _peer
	if room == "" or not session.is_room(room):
		return
	# En salas sólo-miembros hay que afiliar antes de invitar; lo hacemos si
	# tenemos permiso (odiado el error de "no es miembro" al aceptar).
	if session.muc_affiliation(room) in ["owner", "admin"]:
		session.muc_set_affiliation(room, p_jid, "member")
	var rc = session.muc_invite(room, p_jid, p_reason)
	if rc == 0:
		juice.haptic("success")
		juice.toast("Invitación enviada a %s" % p_jid)
	else:
		juice.toast("No se pudo invitar", P.ERROR)

func _on_room_settings_requested() -> void:
	if _peer == "" or not session.is_room(_peer):
		return
	if session.muc_request_config(_peer) != 0:
		juice.toast("No se pudo pedir la configuración", P.ERROR)

func _on_muc_config_form(p_room: String, p_form: Dictionary) -> void:
	if p_room != _peer:
		return
	_room_settings.open_form("Ajustes de sala", p_form)
	_room_settings.popup_centered()

func _on_room_settings_submitted(p_fields: Array) -> void:
	if _peer == "" or not session.is_room(_peer):
		return
	if session.muc_submit_config(_peer, p_fields) == 0:
		juice.toast("Ajustes guardados")
	else:
		juice.toast("No se pudo guardar", P.ERROR)

func _on_room_subject_requested() -> void:
	if _peer == "" or not session.is_room(_peer):
		return
	_prompt_ctx = {"kind": "subject", "room": _peer}
	_prompt_dialog.open("Cambiar tema", session.room_subject(_peer), "Nuevo tema de la sala")

func _on_prompt_submitted(p_text: String) -> void:
	var ctx = _prompt_ctx
	_prompt_ctx = {}
	if str(ctx.get("kind", "")) == "subject":
		var room = str(ctx.get("room", ""))
		if room == "" or not session.is_room(room):
			return
		if session.muc_set_subject(room, p_text) == 0:
			_chat.set_room_subject(p_text)
			juice.toast("Tema actualizado")

func _on_room_destroy_requested() -> void:
	if _peer == "" or not session.is_room(_peer):
		return
	var room = _peer
	session.muc_destroy(room)
	_peer = ""
	_show_roster = true
	_header_avatar.visible = true
	_update_mind_visibility()
	_refresh_rooms()
	juice.toast("Sala destruida")

# Moderación sobre un ocupante: traduce la acción al método de sesión.
func _on_occupant_action(p_room: String, p_nick: String, p_jid: String, p_action: String) -> void:
	if not session.is_room(p_room):
		return
	var rc = 0
	match p_action:
		"member":
			rc = session.muc_set_affiliation(p_room, p_jid, "member")
		"unmember":
			rc = session.muc_set_affiliation(p_room, p_jid, "none")
		"admin":
			rc = session.muc_set_affiliation(p_room, p_jid, "admin")
		"unadmin":
			rc = session.muc_set_affiliation(p_room, p_jid, "none")
		"moderator":
			rc = session.muc_set_role(p_room, p_nick, "moderator")
		"unmoderator":
			rc = session.muc_set_role(p_room, p_nick, "participant")
		"kick":
			rc = session.muc_kick(p_room, p_nick)
		"ban":
			rc = session.muc_ban(p_room, p_jid)
	if rc == 0:
		juice.haptic("tick")
	else:
		juice.toast("La acción falló", P.ERROR)

func _on_message_submitted(p_bare: String, p_text: String) -> void:
	if session.is_room(p_bare):
		var rrc = session.send_groupchat(p_bare, p_text)
		_roster.touch(p_bare, _now_iso())
		if rrc == 0:
			juice.play("send")
			juice.haptic("tick")
		_chat.add_message({
			"from": session.bare(),
			"to": p_bare,
			"body": p_text,
			"direction": "out",
			"timestamp": _now_iso(),
			"id": session.last_sent_id if rrc == 0 else "",
			"commands": [],
			"quick_responses": [],
			"muc": true,
			"sender": session.room_nick(p_bare),
		})
		return
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
		# Fuera de primer plano el aviso va a la barra del sistema.
		if _notifier != null:
			_notifier.notify_message(peer, _display_name(peer), p_rec)
	if peer == _peer:
		_chat.add_message(p_rec)
		_maybe_fetch_media(peer, p_rec)
	elif p_rec.get("direction", "in") != "out" and not p_rec.get("is_mam", false) and str(p_rec.get("body", "")) != "":
		_unread[peer] = int(_unread.get(peer, 0)) + 1
		_roster.set_unread(peer, _unread[peer])

# Las imágenes se descargan solas para mostrar la miniatura; audio/archivos al
# pedirlos (tocar el reproductor o el chip).
func _maybe_fetch_media(peer: String, rec: Dictionary) -> void:
	var attach = rec.get("attach", {})
	if not (attach is Dictionary) or attach.empty():
		return
	# Los propios ya tienen copia local; no re-descargar el link recién subido.
	if str(rec.get("direction", "in")) == "out":
		return
	if str(attach.get("kind", "")) != "image":
		return
	var local = str(attach.get("local", ""))
	if local != "" and File.new().file_exists(local):
		return
	session.ensure_media(peer, rec)

func _on_text_copied(_text: String) -> void:
	juice.toast("Copiado")

func _on_attach_picked(peer: String, path: String) -> void:
	_send_attachment(peer, path, Media.mime_for_path(path), 0, "")

# --- Selector/cámara nativos (Android, singleton XatMedia) ---

func _setup_native_media() -> void:
	if not Engine.has_singleton("XatMedia"):
		return
	_native_media = Engine.get_singleton("XatMedia")
	_native_media.connect("media_picked", self, "_on_native_media_picked")
	_native_media.connect("media_cancelled", self, "_on_native_media_cancelled")
	_native_media.connect("media_error", self, "_on_native_media_error")

func _on_attach_requested(peer: String) -> void:
	if _native_media == null:
		_chat.open_gallery()
		return
	_pending_media_peer = peer
	_native_media.pickFile()

func _on_native_media_picked(path: String) -> void:
	if _pending_avatar:
		_pending_avatar = false
		if path != "":
			_apply_avatar(path)
		return
	var peer = _pending_media_peer
	_pending_media_peer = ""
	if peer == "" or path == "":
		return
	_send_attachment(peer, path, Media.mime_for_path(path), 0, "")

func _on_native_media_cancelled() -> void:
	_pending_media_peer = ""

func _on_native_media_error(reason: String) -> void:
	_pending_media_peer = ""
	juice.play("alert")
	var msg = "No se pudo obtener el archivo"
	if reason == "sin-camara":
		msg = "No hay app de cámara"
	elif reason == "sin-imagen":
		msg = "La cámara no devolvió imagen"
	elif reason == "sin-espacio":
		msg = "Sin espacio para guardar la foto"
	juice.toast(msg, P.ERROR)

func _on_camera_requested(peer: String) -> void:
	# Android: cámara y selector nativos (singleton XatMedia). Godot 3 no trae
	# API de webcam, así que se delega en la app de cámara del sistema.
	if _native_media != null:
		_pending_media_peer = peer
		if _native_media.hasCamera():
			_native_media.takePhoto()
		else:
			juice.toast("Sin cámara: elegí una foto de la galería")
			_native_media.pickImage()
		return
	# Sin backend de cámara (p. ej. Android sin plugin), caer a la galería.
	if CameraCapture.backend() == "":
		juice.toast("Sin cámara: elegí una foto de la galería")
		_chat.open_gallery()
		return
	var dest = "user://media/foto_%d.jpg" % OS.get_ticks_msec()
	var d = Directory.new()
	if not d.dir_exists("user://media/"):
		d.make_dir_recursive("user://media/")
	var reason = CameraCapture.capture(ProjectSettings.globalize_path(dest))
	if reason != "":
		juice.play("alert")
		juice.toast("Cámara no disponible (%s)" % reason, P.ERROR)
		return
	_send_attachment(peer, dest, "image/jpeg", 0, "")

func _on_voice_toggle(peer: String, start: bool) -> void:
	if start:
		if not _mic_permitted():
			OS.request_permissions()
			_chat.set_recording(false, 0)
			juice.toast("Concedé el permiso de micrófono y reintentá", P.ERROR)
			return
		_rec_start_ms = OS.get_ticks_msec()
		if _recorder.start():
			_rec_timer.start()
		else:
			_chat.set_recording(false, 0)
			juice.toast("No se pudo acceder al micrófono", P.ERROR)
	else:
		_rec_timer.stop()
		_chat.set_recording(false, 0)
		var r = _recorder.stop()
		if not r.empty():
			_send_attachment(peer, r["path"], "audio/wav", int(r["duration_ms"]), "")

func _mic_permitted() -> bool:
	if OS.get_name() != "Android":
		return true
	return OS.get_granted_permissions().has("android.permission.RECORD_AUDIO")

func _on_voice_cancel(_peer: String) -> void:
	_rec_timer.stop()
	_chat.set_recording(false, 0)
	_recorder.cancel()

func _tick_recording() -> void:
	var elapsed = OS.get_ticks_msec() - _rec_start_ms
	_chat.set_recording(true, elapsed, _recorder.level())
	if elapsed >= _max_record_ms():
		juice.toast("Nota de voz al límite del servidor", P.ERROR)
		_on_voice_toggle(_peer, false)

# Duración máxima de grabación para que el WAV PCM (estéreo 16 bits 44.1 kHz,
# 176400 B/s) no supere el max-file-size del servidor (XEP-0363). Sin dato se
# asume 10 MB, el límite típico.
func _max_record_ms() -> int:
	var limit = session.upload_max_bytes()
	if limit <= 0:
		limit = 10485760
	var secs = int(float(limit) * 0.9 / 176400.0)
	if secs < 5:
		secs = 5
	elif secs > 300:
		secs = 300
	return secs * 1000

func _send_attachment(peer: String, path: String, mime: String, duration_ms: int, caption: String) -> void:
	var size = Media.file_size(path)
	if size < 0:
		juice.play("alert")
		juice.toast("No se pudo leer el archivo", P.ERROR)
		return
	if size > Media.MAX_UPLOAD_SIZE:
		juice.play("alert")
		juice.toast("El archivo supera %s" % Media.format_size(Media.MAX_UPLOAD_SIZE), P.ERROR)
		return
	var rid = session.send_media_file(peer, path, mime, duration_ms, caption)
	if rid == "":
		juice.play("alert")
		juice.toast("No se pudo enviar el adjunto", P.ERROR)
		return
	_chat.add_message({
		"from": session.bare(),
		"to": peer,
		"body": caption if caption != "" else path.get_file(),
		"direction": "out",
		"timestamp": _now_iso(),
		"id": rid,
		"attach": {
			"url": "", "kind": Media.kind_for_mime(mime), "mime": mime,
			"name": path.get_file(), "size": size,
			"duration_ms": duration_ms, "state": "uploading", "local": path,
		},
	})
	_roster.touch(peer, _now_iso())

func _on_media_upload_state(bare: String, request_id: String, state: String, url: String) -> void:
	if bare == _peer:
		_chat.update_media_state(request_id, state, url)
	if state == "sent":
		juice.play("send")

func _on_media_ready(bare: String, message_id: String, path: String, kind: String) -> void:
	if bare != _peer:
		return
	_chat.set_media_local(message_id, path)
	var action = _media_pending.get(message_id, "")
	if action != "":
		_media_pending.erase(message_id)
		_perform_media(action, path, kind)

func _on_media_failed(bare: String, message_id: String, reason: String) -> void:
	_media_pending.erase(message_id)
	var desc = Media.describe_error(reason)
	if bare == _peer:
		_chat.update_media_state(message_id, "failed", "", desc)
	juice.toast(desc, P.ERROR)
	juice.play("alert")

func _on_media_action(peer: String, rec: Dictionary, action: String) -> void:
	var attach = rec.get("attach", {})
	if not (attach is Dictionary) or attach.empty():
		return
	var local = str(attach.get("local", ""))
	var kind = str(attach.get("kind", "file"))
	if local != "" and File.new().file_exists(local):
		_perform_media(action, local, kind)
		return
	var mid = str(rec.get("id", ""))
	if mid != "":
		_media_pending[mid] = action
		session.ensure_media(peer, rec)

func _perform_media(action: String, path: String, kind: String) -> void:
	if action == "open":
		if kind == "image":
			_lightbox.open(path)
		elif OS.get_name() in ["Android", "iOS"]:
			juice.toast("No se puede abrir este tipo de archivo acá", P.ERROR)
		else:
			OS.shell_open(ProjectSettings.globalize_path(path))
	elif action == "play":
		if _playing_path == path and _audio.playing:
			_audio.stop()
			_playing_path = ""
			return
		var stream = MediaUtil.load_audio(path)
		if stream == null:
			juice.toast("Formato de audio no soportado (%s)" % Media.extension_of(path).to_upper(), P.ERROR)
		else:
			_audio.stream = stream
			_audio.play()
			_playing_path = path

func _on_audio_finished() -> void:
	_playing_path = ""

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
		# Diferido: MAM llega durante el uso y un rebuild síncrono daría un salto.
		_chat.set_history_deferred(p_rows)
		# Descargar las miniaturas de imágenes históricas.
		for r in p_rows:
			var att = r.get("attach", {})
			if att is Dictionary and str(att.get("kind", "")) == "image" and str(att.get("local", "")) == "":
				session.ensure_media(p_bare, {"id": r.get("request_id", ""), "attach": att, "direction": "in"})

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

# --- Contactos y solicitudes de suscripción ---

func _on_add_contact_requested() -> void:
	if session.state != SessionScript.State.CONNECTED:
		juice.toast("Conectate antes de añadir contactos", P.ERROR)
		return
	_add_contact.open()

func _on_add_contact_submitted(p_jid: String, p_name: String) -> void:
	var rc = session.add_contact(p_jid, p_name)
	if rc == 0:
		juice.toast("Solicitud enviada a %s" % p_jid)
		juice.haptic("tick")
	else:
		juice.play("alert")
		juice.toast("No se pudo añadir el contacto", P.ERROR)

func _on_subscription_request(p_bare: String, p_status: String) -> void:
	_roster.add_request(p_bare, p_status)
	juice.play("alert")
	juice.haptic("alert")
	juice.toast("%s quiere agregarte" % p_bare)

func _on_subscription_accept(p_bare: String) -> void:
	session.approve_subscription(p_bare)
	juice.toast("Contacto %s aceptado" % p_bare)
	juice.haptic("success")

func _on_subscription_deny(p_bare: String) -> void:
	session.deny_subscription(p_bare)
	juice.toast("Solicitud de %s rechazada" % p_bare)

# --- Foto de perfil (XEP-0084) ---

func _on_avatar_requested() -> void:
	if session.state != SessionScript.State.CONNECTED:
		juice.toast("Conectate para cambiar la foto", P.ERROR)
		return
	if _native_media != null:
		_pending_avatar = true
		_native_media.pickFile()
		return
	if FilePicker.has_native():
		if _avatar_picker == null:
			_avatar_picker = FilePicker.new()
			_avatar_picker.name = "AvatarPicker"
			add_child(_avatar_picker)
			_avatar_picker.connect("picked", self, "_on_avatar_picked")
		_avatar_picker.open("Elegir foto de perfil", ["Imágenes | *.png *.jpg *.jpeg *.webp *.bmp *.heic"])
		return
	if _avatar_file_dialog == null:
		_avatar_file_dialog = FileDialog.new()
		_avatar_file_dialog.mode = FileDialog.MODE_OPEN_FILE
		_avatar_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_avatar_file_dialog.resizable = true
		_avatar_file_dialog.rect_min_size = Vector2(560, 400)
		_avatar_file_dialog.add_filter("*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.heic ; Imágenes")
		_avatar_file_dialog.connect("file_selected", self, "_on_avatar_filedialog")
		add_child(_avatar_file_dialog)
	_avatar_file_dialog.popup_centered_ratio(0.7)

func _on_avatar_filedialog(p_path: String) -> void:
	_apply_avatar(p_path)

func _on_avatar_picked(p_path: String) -> void:
	_apply_avatar(p_path)

func _apply_avatar(p_path: String) -> void:
	if p_path == "":
		return
	var rc = session.publish_avatar(p_path)
	if rc == 0:
		juice.toast("Foto de perfil actualizada")
		juice.haptic("success")
	else:
		juice.play("alert")
		juice.toast("No se pudo actualizar la foto", P.ERROR)

# Pegar una imagen del portapapeles (escritorio) como adjunto. Ctrl+Shift+V.
func _on_paste_image() -> void:
	if _peer == "":
		return
	if _clipboard == null:
		juice.toast("Requiere wl-clipboard (Wayland) o xclip (X11)", P.ERROR)
		return
	_clipboard.request()

func _on_clipboard_pasted(p_path: String) -> void:
	if p_path == "":
		juice.toast("No hay imagen en el portapapeles")
		return
	if _peer == "":
		return
	_send_attachment(_peer, p_path, "image/png", 0, "")

# XEP-0357: registra el token de push del dispositivo con el servicio del
# servidor (para avisos con la app cerrada). El servicio se elige por SO
# (`xat/push_service_android` = FCM, `xat/push_service_ios` = APNs; con
# `xat/push_service` como fallback común). Sin token nativo aún, se reintenta al
# reconectar.
func _register_push() -> void:
	var service = _push_service_for_os()
	if service == "":
		return
	# Android: Firebase debe inicializarse con la config de la app (del
	# google-services.json) antes de poder pedir el token FCM.
	if OS.get_name() == "Android" and _notifier != null:
		_notifier.configure_firebase(_psetting("xat/firebase_api_key"), _psetting("xat/firebase_app_id"),
				_psetting("xat/firebase_project_id"), _psetting("xat/firebase_sender_id"))
	var token = _notifier.device_token()
	if token == "":
		return
	# Filtro del servidor: no pushear mensajes de desconocidos (los agentes son
	# contactos del roster). Es el principal anti-ruido del lado del gateway.
	session.enable_push(service, token, {"ignore_unknown": true})

func _psetting(p_key: String) -> String:
	return str(ProjectSettings.get_setting(p_key)) if ProjectSettings.has_setting(p_key) else ""

func _push_service_for_os() -> String:
	var key = Push.setting_key(OS.get_name())
	var service = str(ProjectSettings.get_setting(key)) if ProjectSettings.has_setting(key) else ""
	if service == "" and ProjectSettings.has_setting("xat/push_service"):
		service = str(ProjectSettings.get_setting("xat/push_service"))
	return service

func _on_push_registration_changed(p_registered: bool, p_error: String) -> void:
	if p_registered:
		return
	if p_error != "":
		juice.toast("Push no disponible (%s)" % p_error, P.ERROR)

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
	if OS.get_environment("XAT_LANDSCAPE") == "1":
		return rect_size.x > rect_size.y
	return OS.get_name() in ["Android", "iOS"] and rect_size.x > rect_size.y

# Sidebar de navegación/acciones (sólo móvil landscape), en el borde DERECHO:
# título + navegación (Contactos/Chat/Agente) + acciones de la vista + ajustes.
# Consolida acá todos los botones que en portrait viven en las esquinas del
# roster (añadir/sala, sonido/animación/vibración) para no dejar botones chicos
# dispersos.
func _build_sidebar() -> void:
	_sidebar = PanelContainer.new()
	_sidebar.rect_min_size = Vector2(96, 0)
	_sidebar.visible = false
	var sb = XatTheme.box(P.BG1, 0, 0, 0)
	sb.border_width_left = 1
	sb.border_color = P.LINE
	_sidebar.add_stylebox_override("panel", sb)
	var sc = ScrollContainer.new()
	sc.scroll_horizontal_enabled = false
	_sidebar.add_child(sc)
	var sv = VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_constant_override("separation", 6)
	sc.add_child(sv)
	var tm = MarginContainer.new()
	tm.add_constant_override("margin_left", 6)
	tm.add_constant_override("margin_right", 6)
	tm.add_constant_override("margin_top", 10)
	tm.add_constant_override("margin_bottom", 4)
	sv.add_child(tm)
	_sidebar_title = Label.new()
	_sidebar_title.text = "—"
	_sidebar_title.align = Label.ALIGN_CENTER
	_sidebar_title.rect_min_size = Vector2(0, 20)
	_sidebar_title.clip_text = true
	_sidebar_title.add_color_override("font_color", P.TEXT)
	_sidebar_title.add_font_override("font", XatTheme.font(P.FONT_MEDIUM, P.FONT_SIZE))
	tm.add_child(_sidebar_title)
	# Arriba: acceso al perfil/cuenta y a "acerca de".
	var top = HBoxContainer.new()
	top.alignment = BoxContainer.ALIGN_CENTER
	top.add_constant_override("separation", 6)
	sv.add_child(top)
	_sb_profile = _sidebar_icon_action("person", "Cambiar foto de perfil")
	_sb_profile.connect("pressed", self, "_on_sidebar_profile")
	top.add_child(_sb_profile)
	_sb_about = _sidebar_icon_action("info", "Acerca de · privacidad")
	_sb_about.connect("pressed", self, "_on_sidebar_about")
	top.add_child(_sb_about)
	# Identidad del peer/sala (avatar + orbe del agente) que en landscape se mueve
	# acá desde la cabecera del chat, para no perder una franja de alto.
	_sidebar_identity = HBoxContainer.new()
	_sidebar_identity.alignment = BoxContainer.ALIGN_CENTER
	_sidebar_identity.add_constant_override("separation", 4)
	sv.add_child(_sidebar_identity)
	# Sin pestañas de navegación: se cambia de conversación eligiendo un JID/sala
	# en el roster. El sidebar sólo tiene acciones y ajustes.
	sv.add_child(_sidebar_sep())
	_sb_add = _sidebar_action("add", "Añadir contacto por JID")
	_sb_add.connect("pressed", self, "_on_sidebar_add")
	sv.add_child(_sb_add)
	_sb_room = _sidebar_action("room", "Unirse a una sala (MUC)")
	_sb_room.connect("pressed", self, "_on_sidebar_room")
	sv.add_child(_sb_room)
	_sb_occ = _sidebar_action("occupants", "Ver ocupantes de la sala")
	_sb_occ.connect("pressed", self, "_on_sidebar_occ")
	sv.add_child(_sb_occ)
	_sb_act = _sidebar_action("actions", "Acciones de la sala")
	_sb_act.connect("pressed", self, "_on_sidebar_act")
	sv.add_child(_sb_act)
	_sb_leave = _sidebar_action("leave", "Salir de la sala")
	_sb_leave.connect("pressed", self, "_on_sidebar_leave")
	sv.add_child(_sb_leave)
	# Ajustes: sonido y vibración como toggles que se colorean según su estado.
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(spacer)
	sv.add_child(_sidebar_sep())
	var toggles = HBoxContainer.new()
	toggles.alignment = BoxContainer.ALIGN_CENTER
	toggles.add_constant_override("separation", 6)
	sv.add_child(toggles)
	_sb_sound = _sidebar_icon_toggle("sound", "Sonido", "sound_enabled")
	toggles.add_child(_sb_sound)
	_sb_haptic = _sidebar_icon_toggle("vibrate", "Vibración", "haptics_enabled")
	toggles.add_child(_sb_haptic)
	_init_sidebar_settings()
	_split.add_child(_sidebar)

func _sidebar_sep() -> HSeparator:
	return HSeparator.new()

func _sidebar_action(p_icon: String, p_tip: String) -> Button:
	var b = Button.new()
	b.icon = load("res://icons/%s.png" % p_icon)
	b.hint_tooltip = p_tip
	b.focus_mode = Control.FOCUS_NONE
	b.rect_min_size = Vector2(84, 48)
	for st in ["normal", "hover", "pressed", "focus"]:
		var bg = P.BG2.lightened(0.12) if st == "hover" else P.BG2.darkened(0.1)
		b.add_stylebox_override(st, XatTheme.box(bg, 10, 4, 6))
	return b

func _sidebar_icon_action(p_glyph: String, p_tip: String) -> IconButton:
	var b = IconButton.new()
	b.setup(p_glyph, 44, P.TEXT_DIM, p_tip)
	for st in ["normal", "focus"]:
		b.add_stylebox_override(st, XatTheme.box(P.BG2, 10, 4, 4))
	b.add_stylebox_override("hover", XatTheme.box(P.BG2.lightened(0.12), 10, 4, 4))
	b.add_stylebox_override("pressed", XatTheme.box(P.BG2.darkened(0.15), 10, 4, 4))
	b.connect("mouse_entered", self, "_on_icon_hover", [b, true])
	b.connect("mouse_exited", self, "_on_icon_hover", [b, false])
	return b

func _sidebar_icon_toggle(p_glyph: String, p_tip: String, p_key: String) -> IconButton:
	var b = IconButton.new()
	b.setup(p_glyph, 46, P.TEXT_DIM, p_tip)
	b.toggle_mode = true
	# Fondo tenue cuando está encendido + glifo en acento: se distingue del apagado.
	b.add_stylebox_override("normal", XatTheme.box(P.BG2, 10, 4, 4))
	b.add_stylebox_override("focus", XatTheme.box(P.BG2, 10, 4, 4))
	b.add_stylebox_override("hover", XatTheme.box(P.BG2.lightened(0.12), 10, 4, 4))
	b.add_stylebox_override("pressed", XatTheme.box(P.USER.darkened(0.55), 10, 4, 4))
	var on = juice == null or bool(juice.settings.get(p_key, true))
	b.pressed = on
	b.set_icon_color(P.USER if on else P.TEXT_DIM)
	b.connect("toggled", self, "_on_icon_toggle", [b, p_key])
	return b

func _on_icon_hover(p_b, p_enter: bool) -> void:
	if p_b.toggle_mode and p_b.pressed:
		return
	p_b.set_icon_color(P.TEXT if p_enter else P.TEXT_DIM)

func _on_icon_toggle(p_on: bool, p_b, p_key: String) -> void:
	if juice != null:
		juice.set_setting(p_key, p_on)
	# Color = estado: encendido se destaca, apagado queda tenue.
	p_b.set_icon_color(P.USER if p_on else P.TEXT_DIM)

func _init_sidebar_settings() -> void:
	if juice == null:
		return
	for pair in [[_sb_sound, "sound_enabled"], [_sb_haptic, "haptics_enabled"]]:
		var on = bool(juice.settings.get(pair[1], true))
		pair[0].pressed = on
		pair[0].set_icon_color(P.USER if on else P.TEXT_DIM)

func _on_sidebar_profile() -> void:
	# Misma acción que el botón de perfil del roster: cambiar la foto (XEP-0084).
	_on_avatar_requested()

func _on_sidebar_about() -> void:
	OS.shell_open(XatXmpp.PRIVACY_URL)

func _on_sidebar_add() -> void:
	_on_add_contact_requested()

func _on_sidebar_room() -> void:
	_on_join_room_requested()

func _on_sidebar_occ() -> void:
	_chat.toggle_occupants()

func _on_sidebar_act() -> void:
	_chat.popup_room_menu()

func _on_sidebar_leave() -> void:
	_on_room_leave_requested()

# Refresca el sidebar: título = peer/sala; acciones de roster vs. de sala.
func _refresh_sidebar() -> void:
	if _sidebar == null or not _sidebar.visible:
		return
	var roster = _peer == "" or _show_roster
	var in_room = _peer != "" and session.is_room(_peer) and not roster
	_sidebar_title.text = _peer.split("@")[0] if _peer != "" else "xat"
	_sb_add.visible = true
	_sb_room.visible = true
	_sb_occ.visible = in_room
	_sb_act.visible = in_room
	_sb_leave.visible = in_room

# Columnas del roster en landscape: más ancho → más columnas (2–4).
func _landscape_columns() -> int:
	if not _is_mobile_landscape():
		return 1
	return int(clamp(rect_size.x / 260.0, 2.0, 4.0))

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
	var landscape = _is_mobile_landscape()
	if _sidebar != null:
		_sidebar.visible = landscape
	if p_single:
		var roster = _peer == "" or _show_roster
		_roster.visible = roster and not p_mind
		_chat.visible = not roster and not p_mind
	else:
		_roster.visible = true
		_chat.visible = true
	_roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL if p_single else 0
	_mind.size_flags_horizontal = Control.SIZE_EXPAND_FILL if p_single else 0
	# En landscape la navegación no tiene pestañas: el botón atrás del header
	# vuelve al roster, y el título vive en el sidebar (cabecera compacta).
	_chat.set_nav_visible(p_single and _chat.visible, not landscape)
	# En landscape no hay franja de cabecera: la identidad (avatar/orbe) pasa al
	# sidebar y el alto se gana para los mensajes.
	_chat.set_header_visible(not landscape)
	_layout_identity(landscape)
	# Los botones chicos del roster y de la cabecera del chat pasan al sidebar.
	_roster.set_chrome_visible(not landscape)
	_chat.set_header_actions_visible(not landscape)
	if _roster.has_method("set_columns"):
		_roster.set_columns(_landscape_columns())
	_refresh_sidebar()

# Mueve avatar/orbe entre la cabecera del chat y el sidebar según orientación.
func _layout_identity(p_sidebar: bool) -> void:
	if _sidebar_identity == null or _header_avatar == null or _header_orb == null:
		return
	var target = _sidebar_identity if p_sidebar else _chat.header_slot
	for c in [_header_avatar, _header_orb]:
		if c.get_parent() != target:
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			target.add_child(c)

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
		if _lightbox.visible:
			_lightbox.close()
		elif _mind_pinned:
			_on_mind_back()
		elif _single_pane() and _chat.visible:
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
# También calcula el inset inferior (barra de gestos) para el composer.
func _update_safe_area() -> void:
	if not (OS.get_name() in ["Android", "iOS"]):
		if _chat != null:
			_chat.set_bottom_inset(0)
		return
	var safe = OS.get_window_safe_area()
	var win = OS.window_size
	if win.x <= 0.0 or win.y <= 0.0 or rect_size.y <= 0.0:
		return
	var ratio = rect_size.y / win.y
	if safe.position.y > 0.0:
		_split.margin_top = safe.position.y * ratio
	# Inset inferior (barra de gestos), salvo con el teclado virtual visible: el
	# teclado ya eleva el split vía _follow_keyboard.
	var inset = 0
	if OS.get_virtual_keyboard_height() <= 0:
		var bottom_gap = win.y - (safe.position.y + safe.size.y)
		inset = int(max(0.0, bottom_gap * ratio))
	if _chat != null:
		_chat.set_bottom_inset(inset)

func _follow_keyboard() -> void:
	var kb = OS.get_virtual_keyboard_height()
	var ratio = get_viewport().get_visible_rect().size.y / max(1.0, OS.window_size.y)
	_split.margin_bottom = -kb * ratio
	if _chat != null and kb > 0:
		_chat.set_bottom_inset(0)

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
		if p_event.scancode == KEY_V and p_event.shift:
			_on_paste_image()
			get_tree().set_input_as_handled()
		elif p_event.scancode in [KEY_EQUAL, KEY_KP_ADD]:
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

# Nombre visible de un contacto: el del roster (si lo hay) o la parte local.
func _display_name(p_bare: String) -> String:
	var item = session.roster_model.get_item(p_bare)
	if item != null and str(item.get("name", "")) != "":
		return str(item["name"])
	return p_bare.split("@")[0]

func _now_iso() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"
