extends SceneTree

# Comparación de versiones del updater (GitHub Releases).

var _fail := 0

func _init():
	var Updater = load("res://addons/xat_xmpp/xmpp/updater.gd")
	var u = Updater.new()
	get_root().add_child(u)
	check(u._is_newer("0.2.0", "0.1.5"), "0.2.0 > 0.1.5")
	check(u._is_newer("0.1.10", "0.1.9"), "0.1.10 > 0.1.9 (numérico, no lexicográfico)")
	check(u._is_newer("1.0.0", "0.9.9"), "1.0.0 > 0.9.9")
	check(not u._is_newer("0.1.5", "0.1.5"), "igual no es más nueva")
	check(not u._is_newer("0.1.4", "0.1.5"), "menor no es más nueva")
	check(u._is_newer("0.1.5.1", "0.1.5"), "más partes cuenta")
	check(not u._is_newer("0.0.0", ""), "vacío no es mayor")
	# Clasificación y selección de assets por plataforma.
	check(u._asset_kind("xat-0.1.9-debug.apk") == "android", "apk -> android")
	check(u._asset_kind("xat-0.1.9.ipa") == "ios", "ipa -> ios")
	check(u._asset_kind("xat-0.1.9-macos.zip") == "macos", "macos.zip -> macos")
	check(u._asset_kind("xat-0.1.9-linux.x86_64") == "linux", "linux.x86_64 -> linux")
	check(u._asset_kind("xat-0.1.9-windows.zip") == "windows", "windows.zip -> windows")
	check(u._asset_kind("notas.txt") == "", "desconocido -> vacío")
	var assets = [
		{"name": "xat-0.1.9-debug.apk", "browser_download_url": "a", "size": 1},
		{"name": "xat-0.1.9-linux.x86_64", "browser_download_url": "l", "size": 2},
		{"name": "xat-0.1.9.ipa", "browser_download_url": "i", "size": 3},
	]
	var linux = u._platform_asset(assets, "Linux")
	check(linux.get("name", "") == "xat-0.1.9-linux.x86_64" and linux.get("kind", "") == "linux", "Linux elige el binario linux")
	# En Godot 3 el release Linux del template stock reporta "X11" y el platform
	# frt "Unix": ambos deben resolver al binario linux.
	check(u._platform_asset(assets, "X11").get("name", "") == "xat-0.1.9-linux.x86_64", "X11 elige el binario linux")
	check(u._platform_asset(assets, "Unix").get("name", "") == "xat-0.1.9-linux.x86_64", "Unix elige el binario linux")
	check(linux.get("size", 0) == 2, "Linux toma el tamaño del asset")
	check(u._platform_asset(assets, "Android").get("name", "") == "xat-0.1.9-debug.apk", "Android elige el APK")
	check(u._platform_asset(assets, "iOS").get("name", "") == "xat-0.1.9.ipa", "iOS elige el IPA")
	check(u._platform_asset(assets, "Windows").empty(), "sin asset para Windows -> vacío")
	# Reemplazo atómico del binario (usado por la auto-actualización en Linux).
	var dir = "user://updater_test"
	var dd = Directory.new()
	dd.make_dir_recursive(dir)
	var gsrc = ProjectSettings.globalize_path(dir + "/src.bin")
	var gdst = ProjectSettings.globalize_path(dir + "/dst.bin")
	_write_file(gsrc, "nuevo")
	_write_file(gdst, "viejo")
	check(u._replace_binary(gsrc, gdst), "replace copia y renombra")
	check(_read_file(gdst) == "nuevo", "el destino quedó reemplazado")
	check(not _file_exists(gdst.get_base_dir() + "/.dst.bin.new"), "no deja staging")
	check(not u._replace_binary(ProjectSettings.globalize_path(dir + "/nope"), gdst), "origen inexistente falla")
	dd.remove(gdst)
	dd.remove(gsrc)
	dd.remove(dir)
	u.queue_free()
	if _fail == 0:
		print("UPDATER_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1

func _write_file(p_path: String, p_text: String) -> void:
	var f = File.new()
	f.open(p_path, File.WRITE)
	f.store_string(p_text)
	f.close()

func _read_file(p_path: String) -> String:
	var f = File.new()
	if f.open(p_path, File.READ) != OK:
		return ""
	var t = f.get_as_text()
	f.close()
	return t

func _file_exists(p_path: String) -> bool:
	return File.new().file_exists(p_path)
