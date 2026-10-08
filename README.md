# xat

Cliente XMPP nativo en **Godot 3.6** (fork `godot3-box3d`) para chatear con los
agentes de **OpenClaw** vía el gateway Prosody (`hablar.fuentelibre.org`).
Reemplaza la parte XMPP de `gtk-llm-chat` y a `gtk-llm-chat-android`.

- `addon/xat_xmpp/` — GDScript: transporte, stanza, sesión, XEPs, historial.
- `app/` — proyecto Godot (UI Control).
- `tools/` — build del fork con `modules/xmpp`, runner headless, harness de dev.
- `docs/architecture.md` — diseño y tabla de XEPs.
- `tests/` — tests SceneTree (parsers/modelos puros).

El módulo nativo (`libstrophe` + mbedTLS + SQLite) vive en el overlay del fork:
`godot-box3d-3/modules/xmpp/`.

## Build

```sh
tools/build.sh          # -> bin/godot-xat
```

## Tests

```sh
tools/run_tests.sh                    # todos los tests/*_test.gd
tools/run_tests.sh tests/jid_test.gd  # uno puntual
```

## Correr la app

```sh
bin/godot-xat --path app
# o dentro de la sesión gdtk
```
