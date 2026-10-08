extends Reference

# Timestamps XMPP (ISO UTC, "…Z") -> hora local "YYYY-MM-DDTHH:MM:SS" para
# mostrar horas y agrupar por día como los ve el usuario.

static func local_iso(p_iso: String) -> String:
	if p_iso.length() < 19:
		return p_iso
	var unix = Time.get_unix_time_from_datetime_string(p_iso.substr(0, 19))
	var bias = int(Time.get_time_zone_from_system().get("bias", 0))
	return Time.get_datetime_string_from_unix_time(unix + bias * 60)
