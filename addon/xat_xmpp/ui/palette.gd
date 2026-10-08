extends Reference

# Tokens visuales de xat (ver docs/ui.md). Fuente única de colores y medidas;
# los widgets nunca hardcodean colores.

const BG0 := Color("0d1016")      # fondo de ventana
const BG1 := Color("151a23")      # paneles
const BG2 := Color("1d2430")      # cards / burbuja del agente
const LINE := Color("2a3342")     # bordes sutiles
const TEXT := Color("e6e9ef")
const TEXT_DIM := Color("8b93a7")

const USER := Color("6a4cf0")     # burbuja propia
const AGENT_EDGE := Color("4fd1ff") # borde/halo del agente

# Estados del agente (orbe, chips, cards).
const IDLE := Color("4f8cff")
const PROCESSING := Color("4fd1ff")
const TOOL := Color("a78bff")
const PENDING := Color("ffb547")
const OK := Color("4ade80")
const ERROR := Color("ff5c7a")
const ASLEEP := Color("5a6273")

const RADIUS := 16
const RADIUS_SMALL := 6  # esquina "cola" en la última burbuja del grupo
const GAP := 6
const GROUP_GAP := 14

const FONT_REGULAR := "res://fonts/NotoSans-Regular.ttf"
const FONT_MEDIUM := "res://fonts/NotoSans-Medium.ttf"
const FONT_BOLD := "res://fonts/NotoSans-Bold.ttf"
const FONT_MONO := "res://fonts/NotoSansMono-Regular.ttf"
const FONT_FALLBACK := "res://fonts/DejaVuSans.ttf" # símbolos (✔ ✓ → …) que Noto Sans no trae
const FONT_SIZE := 15

# activity de telemetría/hook -> color de estado.
static func activity_color(p_activity: String) -> Color:
	match p_activity:
		"processing", "busy":
			return PROCESSING
		"pending":
			return PENDING
		"paused":
			return ASLEEP
		"available":
			return IDLE
	return ASLEEP

# Fracción de contexto -> verde/ámbar/rojo.
static func context_color(p_frac: float) -> Color:
	if p_frac >= 0.85:
		return ERROR
	if p_frac >= 0.6:
		return PENDING
	return OK
