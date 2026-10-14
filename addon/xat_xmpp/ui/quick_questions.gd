extends Reference

# Preguntas rápidas del agente (REQ-X2.3 / REQ-X4.4). Helper PURO: defaults +
# lectura de user://xat_settings.json. Lo consumen dos lugares:
#   * la fila de chips sobre el composer del chat (C5), y
#   * la tarjeta de agente del roster (X2.3, tanda 2).
# Sin nodos ni señales: sólo strings, para poder testearlo headless.

const SETTINGS_PATH := "user://xat_settings.json"
const SETTINGS_KEY := "quick_questions"
const MAX_QUESTIONS := 4
const STATUS_VALUE := "/status"

const DEFAULT_QUESTIONS := [
	"¿Cómo está la flota?",
	"¿Qué proyectos están activos?",
	"Resume el estado de operator",
	"¿Qué quedó pendiente?",
]

# Copia de las preguntas por defecto (para no exponer la constante mutable).
static func defaults() -> Array:
	return DEFAULT_QUESTIONS.duplicate()

# Lee las preguntas persistidas; si faltan o son inválidas cae a `defaults()`.
static func load_questions(p_path: String = SETTINGS_PATH) -> Array:
	return from_settings(read_settings(p_path))

# Variante pura y testeable: resuelve la lista desde un diccionario de settings
# ya cargado. Sin la clave, devuelve los defaults.
static func from_settings(p_settings) -> Array:
	if not (p_settings is Dictionary) or not (p_settings as Dictionary).has(SETTINGS_KEY):
		return defaults()
	return sanitize((p_settings as Dictionary)[SETTINGS_KEY])

# Normaliza cualquier entrada a <= MAX_QUESTIONS strings no vacíos y sin repetir.
static func sanitize(p_items) -> Array:
	var out := []
	if not (p_items is Array):
		return out
	for it in p_items:
		var q = str(it).strip_edges()
		if q == "" or q in out:
			continue
		out.append(q)
		if out.size() >= MAX_QUESTIONS:
			break
	return out

# Preguntas + `/status` (el comando de estado es siempre el último chip).
static func chips(p_settings) -> Array:
	var out = from_settings(p_settings)
	if not (STATUS_VALUE in out):
		out.append(STATUS_VALUE)
	return out

# Atajo de conveniencia para consumidores que no quieren leer el archivo.
static func load_chips(p_path: String = SETTINGS_PATH) -> Array:
	return chips(read_settings(p_path))

# Lee user://xat_settings.json y devuelve el diccionario (o {} si no existe).
static func read_settings(p_path: String = SETTINGS_PATH) -> Dictionary:
	var f = File.new()
	if not f.file_exists(p_path):
		return {}
	if f.open(p_path, File.READ) != OK:
		return {}
	var txt = f.get_as_text()
	f.close()
	var parsed = JSON.parse(txt)
	if parsed.error != OK or not (parsed.result is Dictionary):
		return {}
	return parsed.result
