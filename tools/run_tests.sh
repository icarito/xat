#!/bin/sh
# Corre todos los tests SceneTree de tests/*_test.gd headless y resume ok/FAIL.
#
# Uso:
#   tools/run_tests.sh                  # todos
#   tools/run_tests.sh tests/jid_test.gd  # uno puntual
#
# El binario ideal es bin/godot-xat (trae modules/xmpp). Para tests de GDScript
# puro (parsers/modelos, sin nodo nativo) se puede usar cualquier binario 3.6
# tools=yes: pasalo por GDTK_GODOT o `GODOT=...`.
#
# Sin `set -e`: varios chequeos del loop (grep, comparaciones) devuelven no-cero
# de forma esperada; el resultado final lo fija `bad`.

XAT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$XAT" || exit 1

if [ -x "$XAT/bin/godot-xat" ]; then
	BIN="${GODOT:-$XAT/bin/godot-xat}"
else
	BIN="${GODOT:-${GDTK_GODOT:-/home/icarito/Proyectos/godot3-box3d/godot-dev/bin/godot.frt.opt.tools.x86_64.gdtk}}"
fi

TESTS="$*"
[ -n "$TESTS" ] || TESTS="tests/*_test.gd"

bad=0
for t in $TESTS; do
	[ -f "$t" ] || continue
	# Aislado de la sesión viva (no heredar WAYLAND_DISPLAY del shell gdtk) y
	# sin audio. El binario frt puede crashear al salir con todos los checks ok:
	# mirar ok/FAIL, no sólo el rc.
	out=$(env -u WAYLAND_DISPLAY -u DISPLAY SDL_VIDEODRIVER=offscreen AUDIODRIVER=Dummy \
		timeout 60 "$BIN" --no-window --path app -s "$PWD/$t" 2>&1); rc=$?
	ok=$(printf '%s\n' "$out" | grep -c '^ok' || true)
	fail=$(printf '%s\n' "$out" | grep -c '^FAIL' || true)
	# Errores de script/conexión que no marcan ok/FAIL pero invalidan el test.
	errs=$(printf '%s\n' "$out" | grep -cE 'SCRIPT ERROR|Parse Error|Attempt to connect nonexistent|nonexistent|Condition "tk_rb' || true)
	st=OK
	# El binario frt crashea al SALIR con todos los checks ok ("free(): invalid
	# pointer", rc 134/139): eso no es fallo del test. Mirar ok/FAIL, como en gdtk.
	if [ "$rc" -eq 124 ] && [ "$fail" -eq 0 ] && [ "$ok" -gt 0 ]; then
		st=CUELGA
		bad=1
	elif [ "$fail" -gt 0 ] || [ "$ok" -eq 0 ] || [ "$errs" -gt 0 ]; then
		st=MAL
		bad=1
	elif [ "$rc" -ne 0 ]; then
		st="OK(crash salida $rc)"
	fi
	printf '%-45s ok=%-3s FAIL=%-2s err=%-2s rc=%-3s %s\n' "$t" "$ok" "$fail" "$errs" "$rc" "$st"
	if [ "$st" = "MAL" ] || [ "$st" = "CUELGA" ]; then
		printf '%s\n' "$out" | sed 's/^/    /'
	fi
done
exit $bad
