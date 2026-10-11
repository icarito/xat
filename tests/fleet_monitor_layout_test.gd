extends SceneTree

# Fleet monitor: en portrait (angosto) no debe desbordar a lo ancho; en escritorio
# usa la disposición ancha. Verifica el modo y el ancho mínimo combinado.

var _fail := 0

func _init():
	var Monitor = load("res://fleet_monitor.gd")
	var m = Monitor.new()
	get_root().add_child(m)

	# Portrait móvil.
	m.rect_size = Vector2(390, 844)
	m._on_resized()
	m.show_snapshot(_sample())
	check(m._compact, "portrait 390px: modo compacto")
	var pw = m._layout.get_combined_minimum_size().x
	check(pw <= 390.0, "portrait: sin desborde horizontal (min=%d)" % int(pw))
	check(m._scroll is ScrollContainer and not m._scroll.scroll_horizontal_enabled, "vista envuelta en scroll vertical")

	# Escritorio ancho.
	m.rect_size = Vector2(1200, 800)
	m._on_resized()
	m.show_snapshot(_sample())
	check(not m._compact, "1200px: modo ancho")
	var ww = m._layout.get_combined_minimum_size().x
	check(ww <= 1200.0, "ancho: entra en viewport (min=%d)" % int(ww))

	# Rotación vuelta a portrait.
	m.rect_size = Vector2(360, 800)
	m._on_resized()
	check(m._compact, "rotación de vuelta: compacto")
	check(m._layout.get_combined_minimum_size().x <= 360.0, "rotación: sin desborde")

	m.free()
	if _fail == 0:
		print("FLEET_LAYOUT_CHECK_OK")
	quit()

func _sample() -> Dictionary:
	return {
		"generated_at": "2026-10-11T00:00:00Z",
		"entities": [
			{"id": "gw-1", "team": "Gateway", "entity-kind": "gateway", "lifecycle": "active", "health": "ready", "jid": "gw@h.org", "brain-url": "https://h.org/brain/gw/"},
			{"id": "svc-1", "team": "API muy largo de nombre", "entity-kind": "service", "lifecycle": "active", "health": "degraded"},
			{"id": "agent-1", "team": "Mateo", "entity-kind": "agent", "lifecycle": "hibernated", "health": "hibernated"},
		],
		"operations": [
			{"instance": "deploy-api", "fields": {"queue_depth": "3", "progress": "42%"}},
		],
		"cost": [{"value": "12.50", "currency": "USD", "instance": "gw-1"}],
	}

func check(p_ok: bool, p_label: String) -> void:
	if p_ok:
		print("ok %s" % p_label)
	else:
		_fail += 1
		print("FAIL %s" % p_label)
		OS.exit_code = 1
