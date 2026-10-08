# AGENTS.md — xat

Fuente de verdad: el plan
`~/.local/share/kilo/plans/1791336573639-xat-godot3-xmpp-client-plan.md` y
`docs/architecture.md` (traducción). Ante conflicto, manda el plan.

## Reglas del proyecto

- **Godot 3 GDScript**, no sintaxis Godot 4. El motor es el fork `godot3-box3d`.
- Usar el binario del fork, no `/usr/bin/godot` (puede ser Godot 4).
- Preferir helpers puros `extends Reference` para parsers/modelos.
- Tests de modelos: `extends SceneTree`, `load("res://...").new()`, `check()`,
  `OS.exit_code`, `quit()`. Correr con `tools/run_tests.sh`.
- El módulo nativo vive en el overlay `godot-box3d-3/modules/xmpp/`. Arreglos
  al motor están permitidos (lo mantenemos nosotros) y se prefieren a hacks en
  GDScript: en `platform/frt` se editan en `godot-gdtk-slug` y se guardan como
  parche nuevo en `godot-box3d-3/patches/frt/z…_nombre.patch` (sólo el hunk).
- No commitear ni deployar sin pedido explícito.

## Build y tests

```sh
tools/build.sh                         # compila el fork + modules/xmpp -> bin/godot-xat
tools/run_tests.sh                     # todos los tests headless
tools/run_tests.sh tests/<test>.gd     # uno puntual
GODOT=<binario> tools/run_tests.sh     # forzar otro binario 3.6
```

El runner usa `--no-window --path app -s <test>`. El binario frt puede crashear al
**salir** con todos los checks `ok`: mirar `ok`/`FAIL`, no sólo el rc.

## Cargar en la app

El addon se expone como `res://addons/xat_xmpp/...` vía el symlink `app/addons ->
../addon`. Nunca crear un `.gd` con `class_name` que choque con una clase nativa
(p. ej. `XmppConnection`); usar `preload`/`const` en su lugar.

## Frontera nativa

`XmppConnection` corre `xmpp_run` en un hilo propio y emite al hilo principal.
Nunca llamar al nodo nativo desde el hilo de libstrophe. SQLite no se toca desde
ese hilo.
