extends SceneTree

# Retención/replay: parseo ISO, stale delay (5 min) y ventanas.

var _fail := 0

func _init():
	var R = load("res://addons/xat_xmpp/xmpp/retention.gd")

	check(R.parse_stamp_ms("1970-01-01T00:00:00Z") == 0, "epoch 0")
	check(R.parse_stamp_ms("1970-01-02T00:00:00Z") == 86400000, "un día")
	check(R.parse_stamp_ms("2026-03-03T04:03:03Z") - R.parse_stamp_ms("2026-03-03T03:03:03Z") == 3600000, "una hora")
	check(R.parse_stamp_ms("basura") == -1, "inválido")
	check(R.parse_stamp_ms("2026-13-01T00:00:00Z") != -1, "mes 13 parsea estructuralmente")

	var base = R.parse_stamp_ms("2026-06-01T12:00:00Z")
	var stamp = "2026-06-01T12:00:00Z"
	# +6 min => stale (umbral 5).
	check(R.is_stale_delayed(stamp, base + 6 * 60 * 1000), "6 min es stale")
	check(not R.is_stale_delayed(stamp, base + 4 * 60 * 1000), "4 min no es stale")
	check(not R.is_stale_delayed("", base), "sin stamp no es stale")

	# replay: umbral 10 min.
	check(R.is_replay(stamp, base + 11 * 60 * 1000), "11 min es replay")
	check(not R.is_replay(stamp, base + 5 * 60 * 1000), "5 min no es replay")

	# gracia post-conexión 15 s.
	check(R.within_connect_grace(base, base + 10000), "10 s dentro de gracia")
	check(not R.within_connect_grace(base, base + 20000), "20 s fuera de gracia")

	# Constantes de política.
	check(R.OVERLAP_MS == 7 * 24 * 60 * 60 * 1000, "overlap 7 días")
	check(R.MAM_PAGE_SIZE == 50 and R.MAX_MAM_PAGES == 40, "paginación MAM")

	if _fail == 0:
		print("RETENTION_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
