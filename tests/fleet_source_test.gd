extends SceneTree

const Main = preload("res://main.gd")
const Juice = preload("res://addons/xat_xmpp/ui/juice.gd")

var _failed := false

func _init() -> void:
	check(Juice.new().settings["fleet_monitor_jid"] == "" and Juice.new().settings["fleet_monitor_node"] == "", "el cliente no trae una fuente de flota preconfigurada")
	var main = Main.new()
	get_root().add_child(main)
	main.juice.settings_path = "user://fleet_source_test.json"
	main.juice.settings["fleet_monitor_jid"] = ""
	main.juice.settings["fleet_monitor_node"] = "joework/monitoring/owner"
	var button_found = false
	for child in main._chat.header_slot.get_children():
		if child is Button and child.text == "Fleet":
			button_found = true
	check(button_found, "Fleet está disponible en el cliente normal")
	main._open_fleet_monitor()
	check(main._fleet_source_dialog.visible, "sin fuente abre configuración dentro de Xat")
	main._fleet_source_dialog.hide()
	main._fleet_source_dialog._jid.text = "operator@example.org/resource"
	main._fleet_source_dialog._node.text = "joework/monitoring/owner"
	main._fleet_source_dialog._on_confirmed()
	check(main._fleet_monitoring_jid() == "operator@example.org" and main._fleet_monitor.visible, "guardar abre la vista con el publicador configurado")
	var reloaded = Juice.new()
	reloaded.settings_path = main.juice.settings_path
	reloaded.load_settings()
	check(reloaded.settings["fleet_monitor_jid"] == "operator@example.org" and reloaded.settings["fleet_monitor_node"] == "joework/monitoring/owner", "fuente XEP-0060 persiste entre sesiones")
	Directory.new().remove(main.juice.settings_path)
	OS.exit_code = 1 if _failed else 0
	quit()

func check(p_ok: bool, p_message: String) -> void:
	if p_ok:
		print("ok ", p_message)
	else:
		_failed = true
		print("FAIL ", p_message)
