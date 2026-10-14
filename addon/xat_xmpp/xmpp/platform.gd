extends Reference

# Detección de plataforma de escritorio/móvil.
#
# En Godot 3 el nombre de Linux depende del platform del binario:
#   - "X11"   template Linux/X11 stock (el release de xat para Linux).
#   - "Unix"  platform frt (build de dev del fork, previo a parchearlo).
#   - "Linux" Godot 4 y el frt ya parcheado.
# Comparar OS.get_name() contra el string fijo "Linux" dejaba inertes en Linux
# cosas que sí existen: updater, cámara, portapapeles, file picker y permisos
# 0600 de credenciales. Usar estas helpers en vez de comparar el nombre a mano.
#
# El parámetro opcional p_name (por defecto OS.get_name()) permite testear el
# mapeo sin depender de la plataforma del runner.

static func name() -> String:
	return OS.get_name()

static func _n(p_name: String) -> String:
	return p_name if p_name != "" else OS.get_name()

static func is_linux(p_name: String = "") -> bool:
	return _n(p_name) in ["Linux", "X11", "Unix"]

static func is_mac(p_name: String = "") -> bool:
	return _n(p_name) in ["macOS", "OSX"]

static func is_windows(p_name: String = "") -> bool:
	return _n(p_name) in ["Windows", "UWP"]

static func is_android(p_name: String = "") -> bool:
	return _n(p_name) == "Android"

static func is_ios(p_name: String = "") -> bool:
	return _n(p_name) == "iOS"

static func is_mobile(p_name: String = "") -> bool:
	return is_android(p_name) or is_ios(p_name)

static func is_desktop(p_name: String = "") -> bool:
	return is_linux(p_name) or is_mac(p_name) or is_windows(p_name)
