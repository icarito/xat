extends Control

# Splash visual standalone: no account loading or session/network activity.

const StartupSplash = preload("res://addons/xat_xmpp/ui/startup_splash.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")

func _ready():
	theme = XatTheme.build()
	var splash = StartupSplash.new()
	splash.timeout_seconds = 120.0
	splash.connect("canceled", self, "_on_canceled", [splash])
	add_child(splash)
	splash.start()

func _on_canceled(p_splash) -> void:
	p_splash.queue_free()
