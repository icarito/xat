extends SceneTree

# C3 (JOE-82): helpers puros de Inicio/Salas. La humanización de la invitación
# (X2.4) y la frescura de la flota (X2.5) se prueban sin instanciar el panel.

var _fail := 0

func _init():
	var Roster = load("res://addons/xat_xmpp/ui/roster_panel.gd")

	# --- X2.4: humanize_invite ---
	check(Roster.humanize_invite("ana@h/x", "sala@conference.h", "") == "ana te invita a #sala", "localpart + sala, sin recurso")
	check(Roster.humanize_invite("ana@h/x", "sala@conference.h", "Ana Ríos") == "Ana Ríos te invita a #sala", "usa el nombre del roster")
	check(Roster.humanize_invite("  Ana  ", "sala@conference.h", "  ") == "Ana te invita a #sala", "nombre en blanco cae al nick")
	check(Roster.humanize_invite("", "sala@conference.h", "") == "Alguien te invita a #sala", "sin remitente")
	check(Roster.humanize_invite("ana@h/x", "Sala@Conf.H") == "ana te invita a #Sala", "localpart preserva mayúsculas")
	check(Roster.humanize_invite("ana@h", "sala@conference.h/nick", "") == "ana te invita a #sala", "sala sin recurso")
	check(Roster.humanize_invite("CARLOS@h/telefono", "sala@conference.h", "carlos") == "carlos te invita a #sala", "el recurso nunca aparece")
	check(Roster.humanize_invite("ana@h/x", "sala@conference.h", "Ana").find("/") < 0, "sin recurso en la etiqueta")

	# --- jid_bare / jid_nick / room_localpart ---
	check(Roster.jid_bare("ana@h/res") == "ana@h", "jid_bare quita recurso")
	check(Roster.jid_bare("ana@h") == "ana@h", "jid_bare sin recurso")
	check(Roster.jid_bare("") == "", "jid_bare vacío")
	check(Roster.jid_nick("ana@h/res") == "ana", "jid_nick quita recurso/dominio")
	check(Roster.jid_nick("solo") == "solo", "jid_nick sin @")
	check(Roster.room_localpart("sala@conference.h") == "sala", "room_localpart")

	# --- X2.5: ago_label / fleet_freshness ---
	check(Roster.ago_label(0) == "hace 0 s", "0 s")
	check(Roster.ago_label(12) == "hace 12 s", "12 s")
	check(Roster.ago_label(59) == "hace 59 s", "59 s")
	check(Roster.ago_label(60) == "hace 1 min", "60 s -> 1 min")
	check(Roster.ago_label(3599) == "hace 59 min", "59 min")
	check(Roster.ago_label(3600) == "hace 1 h", "1 h")
	check(Roster.ago_label(90000) == "hace 1 d", "1 d")
	check(Roster.ago_label(-7) == "hace 0 s", "negativo no inventa")

	var now := 1000000000
	var iso = Time.get_datetime_string_from_unix_time(now - 12, true) + "Z"
	check(Roster.fleet_freshness(iso, now) == "hace 12 s", "frescura 12 s")
	check(Roster.fleet_freshness("", now) == "", "sin hora = sin frescura")
	check(Roster.fleet_freshness("no-es-fecha", now) == "", "hora inválida = sin frescura")

	# --- clock_time ---
	check(Roster.clock_time("2026-10-13T03:07:00Z") == "03:07", "hora corta")
	check(Roster.clock_time("") == "", "hora corta vacía")

	if _fail == 0:
		print("INVITE_LABEL_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
