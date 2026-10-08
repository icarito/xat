extends Reference

# Guardas de retención / replay (XEP-0203 y política MAM). Puro, testeable.
# Porta `isStaleDelayedStanza` de openclaw-xmpp/src/protocol.ts y las ventanas
# de la referencia Android.

const STALE_DELAY_MS := 5 * 60 * 1000
const REPLAY_MAX_AGE_MS := 10 * 60 * 1000
const CONNECT_GRACE_MS := 15 * 1000
const FRESH_INSTALL_CATCHUP_MS := 2 * 60 * 1000
const PENDING_ACTION_MAX_AGE_MS := 15 * 60 * 1000
const OVERLAP_MS := 7 * 24 * 60 * 60 * 1000
const MAM_PAGE_SIZE := 50
const MAX_MAM_PAGES := 40
const MAM_SHADOW_DEDUPE_MS := 30 * 1000

# Epoch ms de un stamp ISO-8601 UTC "YYYY-MM-DDTHH:MM:SSZ". -1 si inválido.
# Se calcula a mano (algoritmo days_from_civil) para no depender de OS.
static func parse_stamp_ms(p_iso: String) -> int:
	if p_iso.length() < 19:
		return -1
	if p_iso[4] != "-" or p_iso[7] != "-" or p_iso[10] != "T" or p_iso[13] != ":" or p_iso[16] != ":":
		return -1
	var year = p_iso.substr(0, 4)
	var month = p_iso.substr(5, 2)
	var day = p_iso.substr(8, 2)
	var hour = p_iso.substr(11, 2)
	var minute = p_iso.substr(14, 2)
	var second = p_iso.substr(17, 2)
	for p in [year, month, day, hour, minute, second]:
		if not p.is_valid_integer():
			return -1
	var days = days_from_civil(int(year), int(month), int(day))
	var secs = days * 86400 + int(hour) * 3600 + int(minute) * 60 + int(second)
	return secs * 1000

# days_from_civil (Howard Hinnant), epoch 1970-01-01 = 0.
static func days_from_civil(p_y: int, p_m: int, p_d: int) -> int:
	var y = p_y
	if p_m <= 2:
		y -= 1
	var era = y / 400
	if y < 0:
		era = (y - 399) / 400
	var yoe = y - era * 400
	var mp = p_m - 3
	if p_m <= 2:
		mp = p_m + 9
	var doy = (153 * mp + 2) / 5 + p_d - 1
	var doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468

# Un <delay> de más de 5 min no debe tratarse como input fresco.
static func is_stale_delayed(p_stamp_iso: String, p_now_ms: int) -> bool:
	if p_stamp_iso == "":
		return false
	var delayed = parse_stamp_ms(p_stamp_iso)
	if delayed < 0:
		return false
	return p_now_ms - delayed > STALE_DELAY_MS

# Replay-level guard (notificaciones): sólo si supera 10 min.
static func is_replay(p_stamp_iso: String, p_now_ms: int) -> bool:
	if p_stamp_iso == "":
		return false
	var t = parse_stamp_ms(p_stamp_iso)
	if t < 0:
		return false
	return p_now_ms - t > REPLAY_MAX_AGE_MS

# Dentro de la gracia post-conexión (no notificar).
static func within_connect_grace(p_connect_ms: int, p_now_ms: int) -> bool:
	return p_now_ms - p_connect_ms <= CONNECT_GRACE_MS
