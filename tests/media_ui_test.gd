extends SceneTree

# Render de media en la burbuja: miniatura/placeholder, reproductor de audio,
# estado "subiendo" y que el texto plano no monte widgets de media. No descarga
# nada (sin copia local), así que es puro layout.

var _fail := 0

func _init():
	var Bubble = load("res://addons/xat_xmpp/ui/bubble.gd")
	var root = get_root()

	var b = Bubble.new()
	b.set_record({"body": "https://up.x/f.jpg", "direction": "in", "timestamp": "2026-01-01T00:00:00Z", "attach": {"url": "https://up.x/f.jpg", "kind": "image", "name": "f.jpg", "state": "remote"}}, true, false, 0, false)
	root.add_child(b)
	check(b._media_host.get_child_count() >= 1, "imagen sin copia: placeholder")
	check(not b._label.visible, "imagen sin pie oculta el label")

	var b2 = Bubble.new()
	b2.set_record({"body": "https://up.x/v.wav", "direction": "out", "timestamp": "2026-01-01T00:00:00Z", "attach": {"url": "https://up.x/v.wav", "kind": "audio", "name": "v.wav", "size": 1200, "duration_ms": 3000, "state": "remote"}}, true, false, 0, false)
	root.add_child(b2)
	check(b2._media_host.get_child_count() >= 1, "audio: reproductor")

	var b3 = Bubble.new()
	b3.set_record({"body": "foto.jpg", "direction": "out", "attach": {"url": "", "kind": "image", "name": "foto.jpg", "state": "uploading"}}, true, false, 0, false)
	root.add_child(b3)
	check(b3._media_host.get_child_count() == 1, "subiendo: etiqueta")

	var b4 = Bubble.new()
	b4.set_record({"body": "hola", "direction": "in"}, true, false, 0, false)
	root.add_child(b4)
	check(b4._media_host.get_child_count() == 0, "texto plano sin media")
	check(b4._label.visible, "texto plano muestra el label")

	var cap = Bubble.new()
	cap.set_record({"body": "mirá\nhttps://up.x/f.jpg", "direction": "in", "timestamp": "2026-01-01T00:00:00Z", "attach": {"url": "https://up.x/f.jpg", "kind": "image", "name": "f.jpg", "state": "remote"}}, true, false, 0, false)
	root.add_child(cap)
	check(cap._label.visible and cap._label.bbcode_text.find("mirá") >= 0, "pie de foto visible")

	# Carga real de imagen: se genera un PNG y se valida textura/miniatura.
	var MediaUtil = load("res://addons/xat_xmpp/ui/media_util.gd")
	var img = Image.new()
	img.create(8, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0, 1))
	var png = "user://media_ui_test.png"
	img.save_png(png)
	check(MediaUtil.load_thumbnail(png, 100) != null, "load_thumbnail png")
	check(MediaUtil.load_texture(png) != null, "load_texture png")
	check(MediaUtil.image_size(png) == Vector2(8, 4), "image_size")
	check(MediaUtil.load_texture("user://no_existe.png") == null, "load_texture ausente = null")
	Directory.new().remove(png)

	b.queue_free()
	b2.queue_free()
	b3.queue_free()
	b4.queue_free()
	cap.queue_free()
	if _fail == 0:
		print("MEDIA_UI_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
