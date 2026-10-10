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
