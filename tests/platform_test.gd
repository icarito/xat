extends SceneTree

# Helper de plataforma: en Godot 3 el nombre de Linux varía según el platform
# del binario ("X11" stock, "Unix" frt sin parchear, "Linux" Godot 4/frt).

var _fail := 0

func _init():
	var Platform = load("res://addons/xat_xmpp/xmpp/platform.gd")
	check(Platform.is_linux("Linux"), "Linux -> linux")
	check(Platform.is_linux("X11"), "X11 -> linux")
	check(Platform.is_linux("Unix"), "Unix -> linux")
	check(not Platform.is_linux("macOS"), "macOS no es linux")
	check(not Platform.is_linux("Android"), "Android no es linux")
	check(Platform.is_mac("macOS") and Platform.is_mac("OSX"), "macOS/OSX -> mac")
	check(Platform.is_windows("Windows") and Platform.is_windows("UWP"), "Windows/UWP -> windows")
	check(Platform.is_android("Android") and not Platform.is_android("X11"), "android")
	check(Platform.is_ios("iOS") and not Platform.is_ios("Android"), "ios")
	check(Platform.is_mobile("Android") and Platform.is_mobile("iOS"), "mobile Android/iOS")
	check(not Platform.is_mobile("X11"), "desktop no es mobile")
	check(Platform.is_desktop("X11") and Platform.is_desktop("Windows") and Platform.is_desktop("macOS"), "desktop")
	check(not Platform.is_desktop("Android"), "Android no es desktop")
	# Defaults (sin argumento) en el runner Linux.
	check(Platform.is_linux(), "default is_linux en el runner")
	check(Platform.is_desktop() and not Platform.is_mobile(), "default desktop")
	if _fail == 0:
		print("PLATFORM_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
