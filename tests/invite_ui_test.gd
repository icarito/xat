extends SceneTree

# E2E: una invitación entrante debe EMITIRSE y RENDERIZARSE en el roster
# (banda de solicitudes, arriba de las pestañas), con Unirse / Ignorar
# funcionando. Cubre el flujo session.muc_invite -> main -> roster.

var _fail := 0

func _init():
	var Main = load("res://main.gd")
	var m = Main.new()
	get_root().add_child(m)
	m._account.visible = false
	m._split.visible = true
	for i in range(4):
		yield(self, "idle_frame")

	# Llega por la señal de sesión (como en producción).
	m.session.emit_signal("muc_invite", "sala@conference.h", "ana@h", "vení")
	yield(self, "idle_frame")
	check(m._roster._invites.has("sala@conference.h"), "invitación registrada en el roster")
	check(m._roster._req_box.visible, "banda de invitaciones visible")
	check(m._roster._req_box.get_child_count() == 1, "una fila de invitación renderizada")
	check(m._roster._req_box.is_visible_in_tree(), "fila visible en el árbol")

	# Visible también con la pestaña Salas activa (la banda va fuera de tabs).
	m._roster._set_tab(1)
	yield(self, "idle_frame")
	check(m._roster._req_box.is_visible_in_tree(), "banda visible también en pestaña Salas")
	m._roster._set_tab(0)

	# La fila tiene los botones Unirse / Ignorar.
	var accept = _find_button(m._roster._req_box, "Unirse")
	var ignore = _find_button(m._roster._req_box, "Ignorar")
	check(accept != null and ignore != null, "fila con botones Unirse/Ignorar")

	# Ignorar quita la invitación y oculta la banda.
	if ignore != null:
		ignore.emit_signal("pressed")
	yield(self, "idle_frame")
	check(not m._roster._invites.has("sala@conference.h"), "Ignorar quita la invitación")
	check(not m._roster._req_box.visible, "banda se oculta sin invitaciones")

	# Otra invitación: Unirse emite room_invite_accept y limpia.
	m.session.emit_signal("muc_invite", "sala2@conference.h", "bob@h", "")
	yield(self, "idle_frame")
	accept = _find_button(m._roster._req_box, "Unirse")
	check(accept != null, "segunda invitación renderizada")
	if accept != null:
		accept.emit_signal("pressed")
	yield(self, "idle_frame")
	check(not m._roster._invites.has("sala2@conference.h"), "Unirse limpia la invitación pendiente")

	m.free()
	if _fail == 0:
		print("INVITE_UI_CHECK_OK")
	quit()

func _find_button(p_node, p_text: String):
	if p_node is Button and p_node.text == p_text:
		return p_node
	for c in p_node.get_children():
		var r = _find_button(c, p_text)
		if r != null:
			return r
	return null

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
