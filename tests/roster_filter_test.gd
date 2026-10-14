extends SceneTree

# Filtro segmentado del roster (Todos/Agentes/Contactos/Salas) y guard
# drag-vs-tap: un arrastre no debe abrir el chat, un toque sí.

var _fail := 0
var _selected := []
var _r

func _on_peer_selected(p_bare: String) -> void:
	_selected.append(p_bare)

func _init():
	var RosterPanel = load("res://addons/xat_xmpp/ui/roster_panel.gd")
	_r = RosterPanel.new()
	get_root().add_child(_r)
	_r.connect("peer_selected", self, "_on_peer_selected")

	_r.set_peers(["ag@h", "per@h"])
	_r.set_online("per@h", true)
	_r.set_agent_state("ag@h", {"activity": "available"})
	_r._flush()
	_r.set_rooms(["sala@conference.h"])

	# Sin preview (todavía no hay último mensaje) no debe aparecer el chevron.
	var ag_row0 = _r._box.get_node_or_null("row_ag_h")
	check(ag_row0 != null and _find_chevron(ag_row0) == null, "sin preview => sin chevron")

	check(_row_bares(_r._box) == ["ag@h", "per@h"], "lista completa con Todos")

	_r._set_filter(1)
	check(_row_bares(_r._box) == ["ag@h"], "filtro Agentes deja sólo agentes")
	_r._set_filter(2)
	check(_row_bares(_r._box) == ["per@h"], "filtro Contactos deja sólo personas")
	_r._set_filter(0)
	check(_row_bares(_r._box) == ["ag@h", "per@h"], "Todos vuelve a mostrar ambos")

	check(_r._tab_rooms.text.find("Salas (1)") >= 0, "etiqueta Salas con conteo")
	check(_r._tab_contacts.text.find("Contactos (1)") >= 0, "etiqueta Contactos con conteo")

	_r._set_filter(3)
	check(_r._rooms_scroll.visible and not _r._scroll.visible, "filtro Salas muestra la vista de salas")
	check(_r._tab == 1 and _r._rooms_box.get_child_count() == 1, "página Salas con su fila")
	_r._set_filter(0)
	check(_r._scroll.visible and not _r._rooms_scroll.visible, "filtro de contactos vuelve a la lista")

	# Card de agente: compacta por defecto (sin preview), recorta su contenido y
	# un chevron despliega el preview por agente.
	_r.set_last_message("ag@h", "ag@h", "hola mundo", "2026-10-14T10:00:00Z")
	_r._flush()
	check(_row_height(_r, "ag@h") >= 56 and _row_height(_r, "ag@h") <= 72, "card de agente compacta por defecto")
	var ag_row = _r._box.get_node_or_null("row_ag_h")
	check(ag_row.rect_clip_content, "la card recorta su contenido (no desborda)")
	var stb = ag_row.get_stylebox("normal")
	check(stb.content_margin_top == 8 and stb.content_margin_left == 12, "card con padding interno")
	check(not _has_label_text(ag_row, "hola mundo"), "preview colapsado por defecto")
	check(_find_chevron(ag_row) != null, "chevron de disclosure presente")
	# Responsive: `inner` se estira (sin ancho mínimo fijo) => el chevron entra
	# siempre. Glow cyan SÓLO en la stylebox "pressed" (fila seleccionada).
	var inner_node = _find_named(ag_row, "inner")
	check(inner_node != null and inner_node.rect_min_size.x == 0.0, "inner responsive (sin ancho mínimo)")
	check(inner_node != null and inner_node.size_flags_horizontal == Control.SIZE_EXPAND_FILL, "inner se estira al ancho disponible")
	var normal_box = ag_row.get_stylebox("normal")
	check(normal_box.border_width_top == 1 and normal_box.border_color.a > 0.99, "card no seleccionada: borde neutro fino (sin cyan)")
	var sel_box = ag_row.get_stylebox("pressed")
	check(sel_box.border_width_top == 2 and sel_box.border_color.a > 0.4 and sel_box.border_color.a < 0.7, "seleccionado: glow cyan suave")
	check(sel_box.shadow_size >= 2 and sel_box.shadow_color.a > 0.1, "seleccionado: halo tenue")
	_r._on_preview_toggle("ag@h")
	check(_row_height(_r, "ag@h") > 64, "card expandida crece por el preview")
	check(_has_label_text(_r._box.get_node_or_null("row_ag_h"), "hola mundo"), "preview visible al expandir")
	# Tocar el chevron no abre el chat (no propaga a `_on_row`).
	_selected.clear()
	_r._on_preview_toggle("ag@h") # colapsa
	_r._on_row("ag@h")
	check(_selected.empty(), "el toggle del chevron no abre el chat")
	_r._on_preview_toggle("ag@h") # expande
	_r._on_preview_toggle("ag@h") # colapsa
	check(not bool(_r._expanded.get("ag@h", true)), "estado de expansión por agente vuelve a colapsado")

	# Preview honesto: placeholder OMEMO legible o vacío; sin datos = sin preview.
	check(_r.preview_body("Mensaje cifrado con OMEMO: xat todavía no puede leerlo.") == "mensaje cifrado", "placeholder OMEMO legible")
	check(_r.preview_body("") == "", "sin cuerpo = sin preview")
	check(_r.preview_body("  hola  ") == "hola", "preview recorta espacios")

	# Guard drag-vs-tap vía eventos reales: touch con arrastre no abre; toque sí.
	_selected.clear()
	_r._set_filter(0)
	var t = InputEventScreenTouch.new()
	t.position = Vector2(100, 200)
	t.pressed = true
	_r._input(t)
	var d = InputEventScreenDrag.new()
	d.position = Vector2(100, 240)
	d.relative = Vector2(0, 40)
	_r._input(d)
	check(_r._pointer_moved, "arrastre touch marca moved")
	_r._on_row("per@h")
	check(_selected.empty(), "tap tras arrastre no abre el chat")
	var up = InputEventScreenTouch.new()
	up.position = Vector2(100, 240)
	up.pressed = false
	_r._input(up)

	_selected.clear()
	var t2 = InputEventScreenTouch.new()
	t2.position = Vector2(100, 200)
	t2.pressed = true
	_r._input(t2)
	var d2 = InputEventScreenDrag.new()
	d2.position = Vector2(103, 202)
	d2.relative = Vector2(3, 2)
	_r._input(d2)
	check(not _r._pointer_moved, "movimiento bajo el umbral sigue siendo tap")
	_r._on_row("per@h")
	check(_selected == ["per@h"], "tap liviano abre el chat")
	var up2 = InputEventScreenTouch.new()
	up2.position = Vector2(103, 202)
	up2.pressed = false
	_r._input(up2)

	# Mouse: botón izquierdo con arrastre también suprime.
	_selected.clear()
	var mb = InputEventMouseButton.new()
	mb.button_index = BUTTON_LEFT
	mb.pressed = true
	mb.position = Vector2(50, 50)
	_r._input(mb)
	var mm = InputEventMouseMotion.new()
	mm.position = Vector2(90, 50)
	mm.relative = Vector2(40, 0)
	mm.button_mask = BUTTON_LEFT
	_r._input(mm)
	check(_r._pointer_moved, "arrastre de mouse marca moved")
	_r._on_row("per@h")
	check(_selected.empty(), "click arrastrado de mouse no abre el chat")
	var mup = InputEventMouseButton.new()
	mup.button_index = BUTTON_LEFT
	mup.pressed = false
	mup.position = Vector2(90, 50)
	_r._input(mup)

	# Swipe horizontal cambia de filtro (sólo en lista simple).
	_r._set_filter(0)
	var s = InputEventScreenTouch.new()
	s.position = Vector2(250, 200)
	s.pressed = true
	_r._input(s)
	var sd = InputEventScreenDrag.new()
	sd.position = Vector2(140, 200)
	sd.relative = Vector2(-110, 0)
	_r._input(sd)
	check(_r._filter == 1, "swipe izquierda avanza el filtro")
	_r._cycle_filter(1)
	_r._cycle_filter(1)
	check(_r._filter == 3, "el filtro llega a Salas")
	_r._cycle_filter(1)
	check(_r._filter == 0, "el filtro se envuelve a Todos")

	_r.free()
	if _fail == 0:
		print("ROSTER_FILTER_CHECK_OK")
	quit()

func _row_bares(p_box) -> Array:
	var out := []
	for c in p_box.get_children():
		out.append(str(c.get_meta("bare")))
	return out

func _row_height(p_r, p_bare: String) -> int:
	var row = p_r._box.get_node_or_null(p_r._row_name(p_bare))
	return int(row.rect_min_size.y) if row != null else -1

func _has_label_text(p_node, p_text: String) -> bool:
	if p_node is Label and p_node.text == p_text:
		return true
	for c in p_node.get_children():
		if _has_label_text(c, p_text):
			return true
	return false

func _find_chevron(p_node):
	if p_node is Button and str(p_node.name).begins_with("chev_"):
		return p_node
	for c in p_node.get_children():
		var r = _find_chevron(c)
		if r != null:
			return r
	return null

func _find_named(p_node, p_name: String):
	if p_node is Node and p_node.name == p_name:
		return p_node
	for c in p_node.get_children():
		var r = _find_named(c, p_name)
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
