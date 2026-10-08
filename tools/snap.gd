extends SceneTree

# Captura PNG de una escena tras N frames (revisión visual).
# Uso: tools/snap.sh res://dev/orb_lab.tscn out.png [frames] [WxH]
# Args tras `--`: <scene> <out.png> [frames=60]. Tamaño: --resolution (snap.sh).
# SNAP_ARGS extra al binario, ej. SNAP_ARGS="--video-driver GLES2".

func _init():
	var args = OS.get_cmdline_args()
	var i = args.find("--")
	var a = Array(args).slice(i + 1, args.size() - 1) if i >= 0 else []
	if a.size() < 2:
		print("uso: -- <scene> <out.png> [frames]")
		quit(2)
		return
	var frames = int(a[2]) if a.size() > 2 else 60
	get_root().add_child(load(a[0]).instance())
	for _f in range(frames):
		yield(self, "idle_frame")
	var img = get_root().get_texture().get_data()
	img.flip_y()
	print("SNAP %s -> %s" % [a[1], img.save_png(a[1])])
	quit()
