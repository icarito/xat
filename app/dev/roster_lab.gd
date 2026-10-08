extends Control

# Lab visual del roster: agentes con mini-orbe + humanos con inicial.

const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")
const RosterPanel = preload("res://addons/xat_xmpp/ui/roster_panel.gd")

func _ready() -> void:
	theme = XatTheme.build()
	var r = RosterPanel.new()
	r.anchor_bottom = 1.0
	r.rect_min_size = Vector2(260, 0)
	add_child(r)
	var peers = ["kangurito@hablar.fuentelibre.org", "lazaro@hablar.fuentelibre.org", "mateo@hablar.fuentelibre.org", "ana@hablar.fuentelibre.org", "beto@hablar.fuentelibre.org"]
	r.set_peers(peers)
	for p in peers.slice(0, 3):
		r.set_online(p, true)
	r.set_online("ana@hablar.fuentelibre.org", true)
	r.set_agent_state(peers[0], {"activity": "processing", "tool": "exec", "context": {"used": 80000, "max": 131072}})
	r.set_agent_state(peers[1], {"activity": "available", "context": {"used": 12000, "max": 131072}})
	r.set_agent_state(peers[2], {"activity": "pending", "context": {"used": 120000, "max": 131072}})
	# Avatares generados (degradé) para una persona y un agente.
	for p in [peers[1], peers[3]]:
		var img = Image.new()
		img.create(64, 64, false, Image.FORMAT_RGBA8)
		img.lock()
		for y in range(64):
			for x in range(64):
				img.set_pixel(x, y, Color.from_hsv(float(p.hash() % 360) / 360.0 + y / 400.0, 0.6, 0.6 + x / 200.0))
		img.unlock()
		var tex = ImageTexture.new()
		tex.create_from_image(img)
		r.set_avatar(p, tex)
	# Actividad: ana habló último, luego mateo.
	r.touch("ana@hablar.fuentelibre.org", "2026-10-08T10:00:00Z")
	r.touch("mateo@hablar.fuentelibre.org", "2026-10-08T09:00:00Z")
	r.select(peers[0])
