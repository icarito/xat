extends SceneTree

# Assets crudos en PCK: el runtime tools=no no depende de .import ni del editor.
const EmojiInline = preload("res://addons/xat_xmpp/ui/emoji_inline.gd")
var _fail := 0

func _init() -> void:
	var file := File.new()
	file.open("res://emoji/manifest.json", File.READ)
	var manifest = JSON.parse(file.get_as_text()).result
	file.close()
	manifest["packed_fixture"] = true
	file.open("/tmp/xat-emoji-packed-manifest.json", File.WRITE)
	file.store_string(JSON.print(manifest))
	file.close()
	var pack := PCKPacker.new()
	check(pack.pck_start("/tmp/xat-emoji-assets.pck") == OK, "create emoji asset pack")
	check(pack.add_file("res://emoji/manifest.json", "/tmp/xat-emoji-packed-manifest.json") == OK, "pack sequence manifest")
	for page in manifest.get("pages", []):
		var page_path: String = page["path"]
		check(pack.add_file(page_path, ProjectSettings.globalize_path(page_path)) == OK, "pack atlas page " + page_path.get_file())
	var properties_path: String = manifest.get("properties", "res://emoji/properties.json")
	check(pack.add_file(properties_path, ProjectSettings.globalize_path(properties_path)) == OK, "pack Unicode properties")
	for license_path in ["res://emoji/LICENSE.txt", "res://emoji/UNICODE-LICENSE.txt"]:
		check(pack.add_file(license_path, ProjectSettings.globalize_path(license_path)) == OK, "pack license " + license_path.get_file())
	check(pack.flush() == OK and ProjectSettings.load_resource_pack("/tmp/xat-emoji-assets.pck"), "mount emoji asset pack")
	file.open("res://emoji/manifest.json", File.READ)
	check(JSON.parse(file.get_as_text()).result.get("packed_fixture", false), "read manifest from mounted pack")
	file.close()
	var script = load(EmojiInline.SCRIPT_PATH)
	if script.has_meta(EmojiInline.CACHE_KEY):
		script.remove_meta(EmojiInline.CACHE_KEY)
	var provider = EmojiInline.new()
	check(provider.available() and provider._state["sequences"].size() == 5225, "runtime loads full canonical and alias catalog from pack")
	check(provider._state["pages"].empty(), "packed provider starts without loading atlas pages")
	var first_sequence: String = provider._state["sequences"][0]
	check(not provider.replacement(first_sequence, 0).empty() and provider._state["pages"].size() == 1, "packed provider loads a page on first rendered emoji")
	var all_pages_ok := true
	for page_index in range(manifest["pages"].size()):
		for entry in manifest["entries"]:
			if int(entry["page"]) == page_index:
				all_pages_ok = all_pages_ok and not provider.replacement(entry["sequence"], 0).empty()
				break
	check(all_pages_ok and provider._state["pages"].size() == 16, "all packed pages render representative sequences")
	check(provider._state["manifest"].get("packed_fixture", false), "provider reads mounted manifest marker")
	if _fail == 0:
		print("EMOJI_PACK_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
