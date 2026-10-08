extends SceneTree

# SFX: los 6 efectos de UI generados por tools/gen_sfx.py existen y son WAV
# mono válidos. Sin editor no hay import de res:// WAV, así que se leen crudos
# con File y se verifica longitud + header RIFF/WAVE.

var _fail := 0

func _init():
	var names = ["send", "receive", "tool_start", "tool_done", "approve", "alert"]
	for n in names:
		var path = "res://sfx/%s.wav" % n
		var f = File.new()
		var err = f.open(path, File.READ)
		check(err == OK, "%s abre" % n)
		if err == OK:
			var size = f.get_len()
			check(size > 1000, "%s > 1000 bytes" % n)
			var head = f.get_buffer(12)
			var is_riff = head.size() >= 12 \
				and head[0] == 0x52 and head[1] == 0x49 and head[2] == 0x46 and head[3] == 0x46
			var is_wave = head.size() >= 12 \
				and head[8] == 0x57 and head[9] == 0x41 and head[10] == 0x56 and head[11] == 0x45
			check(is_riff and is_wave, "%s header RIFF/WAVE" % n)
			f.close()

	if _fail == 0:
		print("SFX_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
