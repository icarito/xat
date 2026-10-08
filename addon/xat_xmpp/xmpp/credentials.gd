extends Reference

# Persistencia de la cuenta. Guarda la config en un JSON con permisos 0600 y
# resuelve la contraseña con override por variable de entorno (la contraseña
# del archivo es el último recurso). Puro salvo por el chmod/archivo.

const DEFAULT_PATH := "user://account.json"

# Variable de entorno para el override de contraseña de un bare JID.
# ej. agente@hablar.fuentelibre.org -> XAT_AGENTE_HABLAR_FUENTELIBRE_ORG_PASSWORD
static func env_var_for(p_bare: String) -> String:
	var s = p_bare.to_upper()
	s = s.replace("@", "_").replace(".", "_").replace("-", "_").replace("/", "_")
	return "XAT_" + s + "_PASSWORD"

static func resolve_password(p_bare: String, p_stored: String) -> String:
	var from_env = OS.get_environment(env_var_for(p_bare))
	if from_env != "":
		return from_env
	return p_stored

func save(p_path: String, p_config: Dictionary) -> bool:
	var f := File.new()
	if f.open(p_path, File.WRITE) != OK:
		return false
	f.store_string(to_json(p_config))
	f.close()
	# Permisos 0600 (contiene la contraseña). Best-effort en Linux.
	OS.execute("chmod", ["600", ProjectSettings.globalize_path(p_path)])
	return true

func load_config(p_path: String) -> Dictionary:
	var f := File.new()
	if not f.file_exists(p_path):
		return {}
	if f.open(p_path, File.READ) != OK:
		return {}
	var text = f.get_as_text()
	f.close()
	var parsed = parse_json(text)
	if parsed is Dictionary:
		return parsed
	return {}

# Carga y aplica el override de entorno sobre la contraseña.
func load_with_env(p_path: String) -> Dictionary:
	var cfg = load_config(p_path)
	if cfg.has("jid"):
		# La app guarda "pass" (account_panel.config()); "password" por compat.
		cfg["password"] = resolve_password(str(cfg["jid"]), str(cfg.get("pass", cfg.get("password", ""))))
	return cfg
