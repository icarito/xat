extends SceneTree

func _init():
	var failures := []
	_check_class("XmppConnection", failures)
	_check_class("SQLiteBinding", failures)
	_check_class("SQLiteQuery", failures)

	var label = RichTextLabel.new()
	if not label.has_method("add_inline_image"):
		failures.append("RichTextLabel.add_inline_image is missing; rebuild the fork with tools/patches/z_emoji_inline_source.patch")
	label.free()

	if failures.empty():
		print("RUNTIME_PREFLIGHT_OK")
	else:
		for failure in failures:
			printerr("RUNTIME_PREFLIGHT_FAIL: " + failure)
		OS.exit_code = 1
	quit()

func _check_class(class_id: String, failures: Array) -> void:
	if not ClassDB.class_exists(class_id):
		failures.append("ClassDB class %s is missing; use a fork release built with modules/xmpp" % class_id)
