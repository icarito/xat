extends SceneTree

# Ciclo de vida del nodo nativo: abrir/cerrar dos veces (contexto y sm_state
# persistentes entre reconexiones) no debe crashear ni filtrar. Se usa un host
# local sin servicio para que falle rápido, sin depender de la red.

var _fail := 0

func _init():
	var conn = ClassDB.instance("XmppConnection")
	check(conn != null, "instancia")

	# Sin red real: puerto cerrado en loopback => falla al conectar.
	check(conn.open("probe@localhost", "x", "127.0.0.1", 1, "") == 0, "open 1")
	conn.close()
	check(not conn.is_open(), "cerrado tras 1")

	check(conn.open("probe@localhost", "x", "127.0.0.1", 1, "") == 0, "open 2 (reconexión)")
	conn.close()
	check(not conn.is_open(), "cerrado tras 2")

	# Cambio de cuenta: descarta el sm_state viejo sin crashear.
	check(conn.open("otro@localhost", "x", "127.0.0.1", 1, "") == 0, "open otra cuenta")
	conn.close()

	conn.free()
	if _fail == 0:
		print("NATIVE_LIFECYCLE_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
