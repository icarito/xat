extends "res://main.gd"

var autoconnect_attempted := false

# The parent schedules this hook for stored credentials. The fixture records it
# instead of calling the session or touching the network.
func _autoconnect():
	autoconnect_attempted = true
