extends SceneTree

# Verifica que el binario del fork y el proyecto app/ cargan headless, y que el
# addon se resuelve vía res://addons/xat_xmpp.

func _init():
	var Jid = load("res://addons/xat_xmpp/xmpp/jid.gd")
	var j = Jid.new()
	j.parse("agente@hablar.fuentelibre.org/xat-dev")
	check(j.node == "agente", "node")
	check(j.domain == "hablar.fuentelibre.org", "domain")
	check(j.resource == "xat-dev", "resource")
	check(j.bare == "agente@hablar.fuentelibre.org", "bare")
	check(j.full == "agente@hablar.fuentelibre.org/xat-dev", "full")
	check(j.is_valid(), "valid")
	check(not j.is_bare(), "no bare")

	# La app y el addon compilan/cargan en el binario del fork.
	check(load("res://main.gd") != null, "main.gd compila")
	check(load("res://addons/xat_xmpp/xat_xmpp.gd") != null, "xat_xmpp.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/transport.gd") != null, "transport.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/presence.gd") != null, "presence.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/roster.gd") != null, "roster.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/message.gd") != null, "message.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/mam.gd") != null, "mam.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/corrections.gd") != null, "corrections.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/store.gd") != null, "store.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/session.gd") != null, "session.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/media.gd") != null, "media.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/http_transfer.gd") != null, "http_transfer.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/recorder.gd") != null, "recorder.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/camera.gd") != null, "camera.gd compila")
	check(load("res://addons/xat_xmpp/ui/media_util.gd") != null, "media_util.gd compila")
	check(load("res://addons/xat_xmpp/ui/media_lightbox.gd") != null, "media_lightbox.gd compila")

	# Decodificadores de audio: el build trae stb_vorbis (OGG Vorbis) y minimp3.
	check(ClassDB.class_exists("AudioStreamOGGVorbis"), "decodificador OGG (stb_vorbis)")
	check(ClassDB.class_exists("AudioStreamMP3"), "decodificador MP3 (minimp3)")
	var MU = load("res://addons/xat_xmpp/ui/media_util.gd")
	check(MU.is_playable("a.wav") and MU.is_playable("a.ogg") and MU.is_playable("b.mp3"), "media_util: formatos reproducibles")
	check(not MU.is_playable("voz.opus"), "media_util: opus sin decodificador")
	check(load("res://addons/xat_xmpp/xmpp/forms.gd") != null, "forms.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/commands.gd") != null, "commands.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/caps.gd") != null, "caps.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/pep.gd") != null, "pep.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/markdown.gd") != null, "markdown.gd compila")
	check(load("res://addons/xat_xmpp/ui/account_panel.gd") != null, "account_panel.gd compila")
	check(load("res://addons/xat_xmpp/ui/roster_panel.gd") != null, "roster_panel.gd compila")
	check(load("res://addons/xat_xmpp/ui/chat_panel.gd") != null, "chat_panel.gd compila")
	check(load("res://addons/xat_xmpp/ui/command_dialog.gd") != null, "command_dialog.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/actions.gd") != null, "actions.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/retention.gd") != null, "retention.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/normalize.gd") != null, "normalize.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/credentials.gd") != null, "credentials.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/subscription.gd") != null, "subscription.gd compila")
	check(load("res://addons/xat_xmpp/xmpp/push.gd") != null, "push.gd compila")
	check(load("res://addons/xat_xmpp/ui/add_contact_dialog.gd") != null, "add_contact_dialog.gd compila")
	check(load("res://addons/xat_xmpp/ui/notifier.gd") != null, "notifier.gd compila")
	var transport_script = load("res://addons/xat_xmpp/xmpp/transport.gd")
	var transport = transport_script.new()
	check(transport.available(), "transport ve el modulo nativo")
	transport.free()

	print("SMOKE_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		print("FAIL %s" % label)
		OS.exit_code = 1
