# xat — contrato de UI

Objetivo: un chat **hermoso, útil y diegético** para entender al agente con el
que hablamos (estado, contexto, tools, aprobaciones), con juice de juego pero
conservador en recursos. Godot 3.6, UI por código (Control), sin escenas salvo
`app/dev/*`.

## Honestidad

- Sólo mostramos estado **real** del protocolo. XMPP no trae razonamiento ni
  tokens en streaming: "la mente" = telemetría + hooks + chat states + comandos.
  Nunca simular pensamientos ni progreso inventado.
- Animación siempre ligada a un evento con significado (llegó un mensaje,
  cambió `activity`, se aprobó algo). Nada se mueve "porque sí" salvo la
  respiración lenta del orbe.

## Fuentes de datos (session.gd)

| Señal | Origen | Uso |
|---|---|---|
| `agent_state_changed(bare, state)` | PEP telemetría `urn:openclaw:telemetry:0` y hooks | orbe, panel mente, roster |
| `agent_hook(bare, hook)` | PEP `urn:openclaw:hooks:{activity,approval,progress}:0` (JSON `contractVersion:1`) | cards de tool/aprobación |
| `chat_state_received` | XEP-0085 | shimmer "pensando" |
| `delivery_received` | XEP-0184 | ✓✓ en burbuja propia |
| `message_corrected` | XEP-0308 | re-render burbuja + marca "editado" |
| `actions_received` | 0050/0439 en mensaje | chips / approval card |

`state` (de `agent_state.gd`): `activity`, `availability`, `context{used,max}`,
`tokens{input,output,total,requests}`, `cost{usd}`, `session_cost{usd}`,
`day_cost{usd}`, `model`, `tool`, `session_status`, `progress{state,detail}`,
`approvals{approvalId -> hook}`. Telemetría se republica sólo ante cambio o
delta de contexto ≥500 tokens: no asumir frecuencia.

## Lenguaje visual

Colores y medidas sólo desde `addon/xat_xmpp/ui/palette.gd`. Tema oscuro.
Tipografía Noto Sans (OFL, `app/fonts/`).

Orbe (por `activity`): `available` respiración lenta azul · `processing`/`busy`
giro + brillo cian · `tool` no vacío → satélite violeta orbitando + nombre ·
`pending` ámbar pulsante · `paused`/sin telemetría gris dormido · desconectado
desaturado. Anillo = `context.used/max` con `palette.context_color`.

Burbujas: agrupadas por remitente consecutivo; esquina "cola" (radio chico)
sólo en la última del grupo; hora por grupo. Propias a la derecha (USER),
agente a la izquierda (BG2 + borde AGENT_EDGE tenue).

## Presupuesto de recursos

- `low_processor_mode` está activo: la app sólo redibuja cuando algo lo pide.
  **Todo lo animado por `RichTextEffect` o `TIME` de shader se congela** si
  nadie pide redibujo. Regla: animar con Tween/Timer acotado (o pedir
  `update()` desde un Timer sólo mientras la animación está visible). Ejemplo
  del bug: el reveal como RichTextEffect dejaba burbujas vacías.
- Animación de entrada/reveal sólo para mensajes **vivos** (no MAM ni
  `delayed`), reveal con tope 0.6 s.
- Orbes: viewport en `UPDATE_DISABLED` + `UPDATE_ONCE` por tick sobre una
  rejilla global compartida (1/15 s). Tasas: activo 15 ticks/s (compacto 7.5),
  `available` 5, dormido/pausado/desconectado 1 frame y stop, sin foco tope 3.
  Medido offscreen con `tools/fps_probe.gd`: activo ~30 fps dibujados,
  available ~10, pausado 0 (antes: ~120 continuo).
- Bloom real sólo en GLES3; el halo de canvas se usa en ambos drivers.

## Juice

Sonido (`app/sfx/*.wav`, generados por `tools/gen_sfx.py`, cargados a mano sin
import), partículas, pop/shake y háptica (`juice.gd`). Sólo ante eventos con
significado: envío, recepción viva, inicio/fin de tool, aprobación pendiente,
decisión, error de auth. Háptica: vibrador en móvil, rumble de gamepad en
escritorio. Tres toggles persistidos en `user://xat_settings.json` (sonido,
animación, vibración) al pie del roster.
