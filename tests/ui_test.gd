extends SceneTree

# Fase 3: la UI se construye y se conecta a la sesión. Se instancia el main
# headless y se ejercitan los paneles directamente (sin red).

var _fail := 0
var _occ_actions := []
var _room_signals := {}
var _dlg := {}

func _on_occ_action(p_room, p_nick, p_jid, p_action) -> void:
	_occ_actions.append([p_room, p_nick, p_jid, p_action])

func _on_room_signal(p_kind: String) -> void:
	_room_signals[p_kind] = true

func _on_dlg_submit(p_key, p_a, p_b = null) -> void:
	_dlg[p_key] = [p_a, p_b] if p_b != null else p_a

func _on_invite_submit(p_jid, p_reason) -> void:
	_dlg["invite"] = [p_jid, p_reason]

func _on_prompt_submit(p_text) -> void:
	_dlg["prompt"] = p_text

func _init():
	var Main = load("res://main.gd")
	var m = Main.new()
	get_root().add_child(m)

	check(m.session != null, "sesión creada")
	check(m._account != null and m._roster != null and m._chat != null, "paneles creados")
	check(m._split != null and not m._split.visible, "vista de cuenta al inicio")

	# Validación de cuenta (sin conectar).
	m._account._jid.text = "agente@h"
	m._account._pass.text = "secreto"
	m._account._host.text = "h"
	m._account._port.text = "5222"
	var cfg = m._account.config()
	check(cfg["jid"] == "agente@h" and cfg["pass"] == "secreto" and cfg["port"] == 5222, "config de cuenta")

	# Roster.
	m._roster.set_peers(["a@h", "b@h"])
	m._roster.set_online("a@h", true)
	check(m._roster._peers.size() == 2, "roster con dos peers")
	m._roster.touch("b@h", "2026-10-08T10:00:00Z")
	check(m._roster._sorted()[0] == "b@h" and m._roster._box.get_child(0).get_meta("bare") == "b@h", "roster ordenado por actividad")

	# Contactos: botón de alta y validación del diálogo.
	check(m._roster.has_signal("add_contact_requested"), "roster expone add_contact_requested")
	m._add_contact._jid.text = "no-es-jid"
	m._add_contact._validate("")
	check(m._add_contact._ok_btn.disabled, "diálogo: JID inválido deshabilita añadir")
	m._add_contact._jid.text = "nuevo@h"
	m._add_contact._name.text = "Nuevo"
	m._add_contact._validate("")
	check(not m._add_contact._ok_btn.disabled, "diálogo: JID válido habilita añadir")

	# Solicitudes de suscripción: banda con aceptar/rechazar.
	m._roster.add_request("pide@h", "hola")
	check(m._roster.has_request("pide@h") and m._roster._req_box.visible, "solicitud visible en el roster")
	check(m._roster._req_box.get_child_count() == 1, "una tarjeta de solicitud")
	m._roster.remove_request("pide@h")
	check(not m._roster._req_box.visible, "banda oculta sin solicitudes")

	# Chat: mensaje con markdown y botones de acción.
	m._chat.set_peer("a@h")
	m._chat.add_message({"from": "a@h", "body": "hola **mundo**", "direction": "in", "timestamp": "2026-01-01T10:00:00Z", "id": "m1", "commands": [], "quick_responses": []})
	check(m._chat._messages.size() == 1, "mensaje agregado")
	m._chat.set_actions({
		"commands": [{"jid": "bot@h/res", "node": "cmd:abc:0", "name": "Allow"}],
		"quick_responses": [{"value": "si", "label": "Sí"}],
	})
	check(m._chat._actions.get_child_count() == 2, "dos botones de acción")

	# Plegado de corrección en el render.
	m._chat.add_message({"from": "a@h", "body": "v1", "direction": "in", "timestamp": "2026-01-01T10:01:00Z", "id": "orig", "commands": [], "quick_responses": []})
	check(m._chat._messages.size() == 2, "segundo mensaje")
	m._chat.apply_correction({"from": "a@h", "body": "v2", "replace_id": "orig", "direction": "in", "timestamp": "", "id": "e1"})
	check(m._chat._messages.size() == 2 and m._chat._messages[1]["body"] == "v2", "corrección plegada sin nueva fila")

	# Agrupación: dos "in" seguidos -> sólo la última es group-last.
	check(m._chat._bubbles.size() == 2 and not m._chat._bubbles[0]._last and m._chat._bubbles[1]._last, "sólo la última del grupo lleva cola")
	m._chat.add_message({"from": "", "body": "yo", "direction": "out", "timestamp": "2026-01-01T10:02:00Z", "id": "o1"})
	check(m._chat._bubbles[1]._last and m._chat._bubbles[2]._last, "cambio de dirección abre grupo")
	check(m._chat._bubbles[1]._last and m._chat._bubbles[0]._last == false, "primer grupo intacto")
	check(m._chat._bubbles[1].rec.get("edited", false), "corrección marcada editado")
	m._chat.mark_delivered("o1")
	check(m._chat._messages[2].get("delivered", false) and m._chat._bubbles[2]._ticks.rect_min_size.x > 12, "mark_delivered pone ✓✓")

	# Separador por fecha: 2026-01-01 (primer día) y 2026-01-02.
	var pills = 0
	for ch in m._chat._list.get_children():
		if not ch is m._chat.Bubble:
			pills += 1
	m._chat.add_message({"from": "a@h", "body": "otro día", "direction": "in", "timestamp": "2026-01-02T09:00:00Z", "id": "d2"})
	var pills2 = 0
	for ch in m._chat._list.get_children():
		if not ch is m._chat.Bubble:
			pills2 += 1
	check(pills == 1 and pills2 == 2 and m._chat._last_day == "2026-01-02", "separador al cambiar de día")
	check(m._chat.day_label("2026-10-07", "2026-10-07") == "Hoy" and m._chat.day_label("2026-10-06", "2026-10-07") == "Ayer" and m._chat.day_label("2026-10-05", "2026-10-07") == "lun 5 oct", "etiquetas Hoy/Ayer/fecha")
	check(m._chat.near_bottom(820, 1000, 100) and not m._chat.near_bottom(700, 1000, 100) and m._chat.near_bottom(0, 50, 100), "near_bottom helper")
	# Marcador de no leídos: se quita al enviar.
	m._chat.mark_unread_from(-1)
	check(m._chat._unread_node != null and m._chat._unread_idx == m._chat._messages.size() - 1, "marcador Nuevos")
	m._chat._input.text = "hola"
	m._chat._on_send()
	check(m._chat._unread_node == null and m._chat._unread_idx == -1, "marcador se quita al enviar")
	m._chat.mark_unread_from(0)
	m._chat._on_scrolled(1000000.0)
	check(m._chat._unread_node == null, "marcador se quita al llegar al final")

	# Historial del store (vacío) no rompe.
	m._chat.set_history([])
	check(m._chat._messages.empty(), "set_history limpia")

	# Render diferido: el modelo queda listo al instante y las burbujas van por
	# tandas (no bloquea el frame que cambia de panel).
	m._chat.set_history_deferred([
		{"body": "d1", "ts": "2026-01-03T10:00:00Z", "direction": "in", "request_id": "z1", "quick": [], "commands": []},
		{"body": "d2", "ts": "2026-01-03T10:01:00Z", "direction": "in", "request_id": "z2", "quick": [], "commands": []},
	])
	check(m._chat._messages.size() == 2, "set_history_deferred: modelo listo al instante")

	# Salas (MUC): sección en el roster, unread e invitaciones.
	m._roster.set_rooms(["sala@conference.h"])
	check(m._roster._rooms_header.visible and m._roster._rooms_box.get_child_count() == 1, "roster: sección Salas")
	check(m._roster._rooms_box.get_child(0).get_meta("bare") == "sala@conference.h", "roster: fila de sala")
	m._roster.set_unread("sala@conference.h", 2)
	check(str(m._roster._find_row("sala@conference.h").get_meta("status").text).find("nuevo") >= 0, "roster: unread en sala")
	m._roster.add_invite("otra@conference.h", "bot@h", "vení")
	check(m._roster._req_box.visible and m._roster._invites.has("otra@conference.h"), "roster: invitación visible")
	m._roster.remove_invite("otra@conference.h")
	check(not m._roster._req_box.visible, "roster: banda oculta sin invitaciones")

	# Chat en modo sala: ocupantes, chip de remitente y @mención.
	m._chat.set_room("sala@conference.h", "yo", [{"nick": "ana"}, {"nick": "yo"}])
	check(m._chat._room == "sala@conference.h" and m._chat._occ_btn.visible and m._chat._leave_btn.visible, "chat: modo sala")
	check(m._chat._occ_list.get_child_count() == 2, "chat: lista de ocupantes")
	m._chat.add_message({"from": "sala@conference.h/ana", "body": "hola", "direction": "in", "timestamp": "2026-01-04T10:00:00Z", "id": "r1", "commands": [], "quick_responses": []})
	check(m._chat._bubbles[0]._sender_btn.visible and m._chat._bubbles[0]._sender_btn.text == "ana", "chat: chip de remitente")
	m._chat._input.text = ""
	m._chat._insert_mention("ana")
	check(m._chat._input.text == "@ana ", "chat: @mención insertada")
	# Sin cards de aprobación/quick en salas.
	m._chat.add_message({"from": "sala@conference.h/ana", "body": "q", "direction": "in", "timestamp": "2026-01-04T10:01:00Z", "id": "r2", "commands": [{"jid": "x", "node": "n", "name": "A"}], "quick_responses": [{"value": "si"}]})
	check(m._chat._card == null, "chat: sin cards en sala")
	m._chat.set_peer("a@h")
	check(m._chat._room == "" and not m._chat._leave_btn.visible, "chat: vuelve a 1:1")

	# Moderación de sala: menú de sala y de ocupante según capacidades.
	m._chat.connect("occupant_action", self, "_on_occ_action")
	m._chat.connect("room_settings_requested", self, "_on_room_signal", ["settings"])
	m._chat.connect("room_destroy_requested", self, "_on_room_signal", ["destroy"])
	m._chat.set_room("sala@conference.h", "yo", [
		{"nick": "ana", "jid": "ana@h", "affiliation": "member", "role": "participant"},
		{"nick": "yo", "jid": "me@h", "affiliation": "owner", "role": "moderator"},
	], "owner", "moderator")
	check(m._chat._can_admin() and m._chat._can_moderate(), "chat: somos owner/moderator")
	check(m._chat._room_menu_btn.visible, "chat: botón de menú de sala")
	# ana tiene menú ⋯, yo (self) no.
	check(m._chat._occ_list.get_child(0).get_child_count() == 2, "chat: ocupante ajeno con menú ⋯")
	check(m._chat._occ_list.get_child(1).get_child_count() == 1, "chat: yo sin menú")
	m._chat._open_room_menu()
	check(m._chat._room_menu.get_item_count() >= 4, "chat: menú de sala (invitar/tema/ajustes/destruir)")
	m._chat._on_room_menu(20)
	check(_room_signals.has("settings"), "chat: pide ajustes")
	m._chat._on_room_menu(21)
	check(_room_signals.has("destroy"), "chat: pide destruir")
	# Menú de ocupante: ofrece acciones y emite occupant_action.
	m._chat._open_occupant_menu("ana", "ana@h", {"affiliation": "member", "role": "participant"})
	check(m._chat._occ_action_menu.get_item_count() >= 5, "chat: acciones de ocupante")
	m._chat._on_occ_action(7) # expulsar
	check(_occ_actions.size() == 1 and _occ_actions[0][3] == "kick", "chat: acción expulsar")
	# Un simple miembro no modera.
	m._chat.set_room_caps("member", "participant")
	check(not m._chat._can_admin() and not m._chat._can_moderate(), "chat: miembro sin moderación")
	m._chat.set_peer("a@h")

	# Diálogos: invitar contacto y prompt de texto.
	m._invite_dialog.connect("submitted", self, "_on_invite_submit")
	m._invite_dialog.open([{"jid": "ana@h", "name": "Ana"}, {"jid": "bob@h", "name": ""}])
	m._invite_dialog._search.text = "bob"
	m._invite_dialog._filter("bob")
	check(m._invite_dialog._list.get_item_count() == 1, "invitar: filtro de contactos")
	m._invite_dialog._list.select(0)
	m._invite_dialog._reason.text = "vení"
	m._invite_dialog._on_confirmed()
	check(_dlg.has("invite") and _dlg["invite"][0] == "bob@h" and _dlg["invite"][1] == "vení", "invitar: submitted")
	m._prompt_dialog.connect("submitted", self, "_on_prompt_submit")
	m._prompt_dialog.open("Cambiar tema", "viejo")
	m._prompt_dialog._edit.text = "nuevo tema"
	m._prompt_dialog._on_confirmed()
	check(_dlg.has("prompt") and _dlg["prompt"] == "nuevo tema", "prompt: submitted")

	# Ajustes de sala (CommandDialog): list-multi recoge todos los marcados.
	var FormsMod = load("res://addons/xat_xmpp/xmpp/forms.gd")
	var StanzaMod = load("res://addons/xat_xmpp/xmpp/stanza.gd")
	var room_form = FormsMod.parse(StanzaMod.parse('<x xmlns="jabber:x:data" type="form"><field var="FORM_TYPE" type="hidden"><value>http://jabber.org/protocol/muc#roomconfig</value></field><field var="muc#roomconfig_membersonly" type="boolean"><value>0</value></field><field var="which" type="list-multi"><value>a</value><value>c</value><option label="A"><value>a</value></option><option label="B"><value>b</value></option><option label="C"><value>c</value></option></field></x>'))
	m._room_settings.open_form("Ajustes", room_form)
	var cols = m._room_settings.collect()
	check(cols[1]["values"] == ["0"], "ajustes: boolean")
	check(cols[2]["values"] == ["a", "c"], "ajustes: list-multi conserva selección")

	# Sidebar (landscape): existe con botones grandes; en desktop no se muestra.
	check(m._sidebar != null and m._sb_add.rect_min_size.y >= 40, "sidebar: acciones presentes")
	check(m._sb_add != null and m._sb_room != null and m._sb_leave != null, "sidebar: acciones de vista")
	check(m._sb_sound != null and m._sb_about != null, "sidebar: ajustes")
	# El roster oculta sus botones propios cuando el sidebar manda.
	m._roster.set_chrome_visible(false)
	check(not m._roster._add_btn.visible and not m._roster._foot.visible, "roster: chrome oculto en landscape")
	m._roster.set_chrome_visible(true)
	check(m._roster._add_btn.visible, "roster: chrome visible en portrait")
	check(m._landscape_columns() == 1, "sidebar: desktop sin columnas")

	# Roster multicolumna (landscape) con scroll lateral.
	m._roster.set_columns(2)
	check(m._roster._grid_scroll.visible and not m._roster._scroll.visible, "roster: modo grilla")
	check(m._roster._grid.get_child_count() == 2, "roster: dos columnas")
	m._roster.set_columns(1)
	check(m._roster._scroll.visible and not m._roster._grid_scroll.visible, "roster: vuelve a lista")

	# Cabecera compacta del chat: oculta título/back en landscape.
	m._chat.set_nav_visible(false, false)
	check(not m._chat._title.visible and not m._chat.back_button.visible, "chat: cabecera compacta")
	m._chat.set_nav_visible(true, true)
	check(m._chat._title.visible, "chat: título visible")

	# Selección parcial de texto en burbujas: la API existe y todo-el-mensaje copia.
	m._chat.set_room("sala@conference.h", "yo", [])
	m._chat.add_message({"from": "sala@conference.h/ana", "body": "texto seleccionable", "direction": "in", "timestamp": "2026-01-04T11:00:00Z", "id": "sel1", "commands": [], "quick_responses": []})
	var bub = m._chat._bubbles[0]
	bub.begin_selection()
	check(bub.selected_text().find("seleccionable") >= 0, "bubble: selección de texto")
	# La barra no debe ser hija directa del PanelContainer (se estiraría fullscreen).
	check(m._chat._sel_bar.get_parent() != m._chat and not (m._chat._sel_bar.get_parent() is Container), "selección: barra en capa overlay")
	bub.end_selection()
	m._chat.set_peer("a@h")

	# Ventana de burbujas: con límite chico, agregar tras reconstruir no desincroniza.
	m._chat.set_peer("w@h")
	for i in range(30):
		m._chat.add_message({"from": "w@h", "body": "m%d" % i, "direction": "in", "timestamp": "2026-02-01T10:%02d:00Z" % i, "id": "w%d" % i, "commands": [], "quick_responses": []})
	m._chat._limit = 10
	m._chat._rebuild()
	m._chat.add_message({"from": "w@h", "body": "nuevo", "direction": "in", "timestamp": "2026-02-01T11:00:00Z", "id": "wn", "commands": [], "quick_responses": []})
	check(m._chat._bubbles.size() == m._chat._messages.size() - m._chat._first, "ventana de burbujas alineada")
	check(m._chat._bubbles.size() <= 10, "ventana recortada")
	m._chat.set_peer("a@h")

	# Diálogo de sala: el nombre se completa con el dominio; no pide nick; valida.
	m._join_room.open("conference.h")
	m._join_room._name.text = "general"
	check(m._join_room._full() == "general@conference.h", "sala: JID = nombre + dominio")
	m._join_room._validate()
	check(not m._join_room._ok_btn.disabled, "sala: nombre válido")
	m._join_room._name.text = "general@otro.dominio"
	check(m._join_room._full() == "general@otro.dominio", "sala: JID completo respetado")
	m._join_room._name.text = "con espacio"
	m._join_room._validate()
	check(m._join_room._ok_btn.disabled, "sala: rechaza espacios")

	# Push (XEP-0357): el servicio se elige por SO, con fallback común.
	ProjectSettings.set_setting("xat/push_service", "")
	ProjectSettings.set_setting("xat/push_service_android", "fcm-push.h")
	ProjectSettings.set_setting("xat/push_service_ios", "apns-push.h")
	check(m._push_service_for_os() == "fcm-push.h", "push: no-iOS resuelve el servicio Android")
	ProjectSettings.set_setting("xat/push_service_android", "")
	ProjectSettings.set_setting("xat/push_service", "push.h")
	check(m._push_service_for_os() == "push.h", "push: fallback a push_service")

	m.free()
	if _fail == 0:
		print("UI_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
