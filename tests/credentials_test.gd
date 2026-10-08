extends SceneTree

# Persistencia de cuenta: round-trip JSON, permisos 0600 y override por env.

var _fail := 0

func _init():
	var Cred = load("res://addons/xat_xmpp/xmpp/credentials.gd")
	var c = Cred.new()

	check(Cred.env_var_for("agente@hablar.fuentelibre.org") == "XAT_AGENTE_HABLAR_FUENTELIBRE_ORG_PASSWORD", "env var")

	var path = "user://account_test.json"
	var f = File.new()
	if f.file_exists(path):
		Directory.new().remove(path)

	var cfg = {"jid": "agente@hablar.fuentelibre.org", "host": "hablar.fuentelibre.org", "port": 5222, "cafile": "/etc/ssl/certs/ca-certificates.crt", "password": "del-archivo"}
	check(c.save(path, cfg), "save")
	check(f.file_exists(path), "archivo creado")
	var loaded = c.load_config(path)
	check(loaded["jid"] == cfg["jid"] and loaded["password"] == "del-archivo", "round-trip")

	# Sin env: usa la del archivo.
	check(Cred.resolve_password(cfg["jid"], "del-archivo") == "del-archivo", "sin override")
	# Con env: gana el entorno.
	var var_name = Cred.env_var_for(cfg["jid"])
	OS.set_environment(var_name, "del-entorno")
	check(Cred.resolve_password(cfg["jid"], "del-archivo") == "del-entorno", "override por env")
	var with_env = c.load_with_env(path)
	check(with_env["password"] == "del-entorno", "load_with_env aplica override")
	OS.set_environment(var_name, "")

	Directory.new().remove(path)
	if _fail == 0:
		print("CREDENTIALS_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
