extends SceneTree

# Burbujas: las URLs (Markdown y sueltas) se vuelven enlaces clickeables.

var _fail := 0

func _init():
	var Bubble = load("res://addons/xat_xmpp/ui/bubble.gd")
	var b = Bubble.new()
	get_root().add_child(b)
	b.set_record({"body": "mirá https://x.y/z y [docs](https://a.b/c)", "direction": "in", "ts": "2026-01-01T00:00:00Z", "request_id": "r1", "quick": [], "commands": []}, true, true, 8, false)
	check(b._label.is_connected("meta_clicked", b, "_on_meta_clicked"), "meta_clicked conectado (link clickeable)")
	check(b._label.bbcode_text.find("[url=https://x.y/z]https://x.y/z[/url]") >= 0, "URL suelta autolink en la burbuja")
	check(b._label.bbcode_text.find("[url=https://a.b/c]docs[/url]") >= 0, "link Markdown en la burbuja")
	check(b._label.meta_underlined, "subrayado de enlaces")
	b.free()
	if _fail == 0:
		print("BUBBLE_LINK_CHECK_OK")
	quit()

func check(p_ok: bool, p_label: String) -> void:
	if p_ok:
		print("ok %s" % p_label)
	else:
		_fail += 1
		print("FAIL %s" % p_label)
		OS.exit_code = 1
