extends SceneTree

# Mide frames dibujados en 3 s de una escena: -s tools/fps_probe.gd -- <res://scene> (último arg).
# Imprime "FPS_DRAWN <n>". Uso en docs/ui.md (presupuesto).

func _init():
	var a = OS.get_cmdline_args()
	get_root().add_child(load(a[a.size() - 1]).instance())
	yield(create_timer(1.0), "timeout") # asentar (transiciones iniciales)
	var f0 = Engine.get_frames_drawn()
	yield(create_timer(3.0), "timeout")
	print("FPS_DRAWN ", int(round((Engine.get_frames_drawn() - f0) / 3.0)))
	quit()
