extends SceneTree

# Recorte de avatar: mapeo vista->imagen (ajuste "contain") y process_rect
# (recorte cuadrado por rectángulo elegido).

var _fail := 0

func _init():
	var Avatar = load("res://addons/xat_xmpp/xmpp/avatar.gd")

	# map_view_rect: imagen 200x100 en una vista 100x100 -> escala 0.5, centrada
	# vertical (off.y = 25). Un cuadrado en (0,25)-(50,75) mapea a (0,0)-(100,100).
	var r = Avatar.map_view_rect(Rect2(Vector2(0, 25), Vector2(50, 50)), Vector2(100, 100), Vector2(200, 100))
	check(round(r.position.x) == 0 and round(r.position.y) == 0 and round(r.size.x) == 100 and round(r.size.y) == 100, "map_view_rect contain")

	# Vista vacía -> rect vacío (sin crash).
	check(Avatar.map_view_rect(Rect2(), Vector2(0, 0), Vector2(10, 10)) == Rect2(), "map_view_rect vista vacía")

	# process_rect: recorta un cuadrado del tamaño pedido y devuelve bytes/id.
	var img = Image.new()
	img.create(100, 80, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.4, 0.6))
	var src = "user://avatar_crop_test.png"
	check(img.save_png(src) == OK, "guardar imagen de prueba")
	var a = Avatar.process_rect(src, Rect2(10, 10, 40, 40))
	check(not a.empty() and int(a["width"]) == 40 and int(a["height"]) == 40, "process_rect recorta cuadrado 40")
	check(str(a["id"]) != "" and a["bytes"].size() > 0, "process_rect devuelve id y bytes")
	check(str(a["mime"]) == "image/png" or str(a["mime"]) == "image/jpeg", "process_rect mime válido")

	# Rect que se sale de los bordes: se limita (no falla) y queda cuadrado.
	var b = Avatar.process_rect(src, Rect2(90, 70, 40, 40))
	check(not b.empty() and int(b["width"]) == 40 and int(b["height"]) == 40, "process_rect limita a bordes")

	var d = Directory.new()
	d.remove(src)
	if _fail == 0:
		print("AVATAR_CROP_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
