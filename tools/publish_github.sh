#!/bin/sh
# Ejecutar en el host: publica con la cuenta solicitada sin cambiar el login global.
set -eu
XAT="$(cd "$(dirname "$0")/.." && pwd)"
export GH_HOST=github.com
GH_TOKEN="$(gh auth token --hostname github.com --user icarito)"
export GH_TOKEN
[ "$(gh api user --jq .login)" = icarito ] || {
  echo 'La autenticación no corresponde a icarito.' >&2; exit 1;
}

SOURCE="$XAT"
if [ "$(git -C "$XAT" rev-parse --show-toplevel 2>/dev/null || true)" != "$XAT" ]; then
  test -s "$XAT/bin/xat-source.bundle" || {
    echo 'No hay metadata Git ni bundle portátil.' >&2; exit 1;
  }
  PUBLISH_WORK="$(mktemp -d /tmp/xat-publish.XXXXXX)"
  git clone "$XAT/bin/xat-source.bundle" "$PUBLISH_WORK/source"
  SOURCE="$PUBLISH_WORK/source"
else
  git -C "$SOURCE" add .github .gitignore AGENTS.md README.md addon app docs tests tools
  if ! git -C "$SOURCE" diff --cached --quiet; then
    git -C "$SOURCE" commit -m 'Add Unicode emoji, expressive startup and Android CI preflight'
  fi
fi

if ! gh repo view icarito/xat --json name >/dev/null 2>&1; then
  gh repo create icarito/xat --private --description 'Godot 3 XMPP client with Slug text and Unicode emoji'
fi
# HTTPS con gh como helper usa GH_TOKEN; no depende de la identidad de la llave SSH.
git -C "$SOURCE" -c credential.helper= -c 'credential.helper=!gh auth git-credential' \
  push https://github.com/icarito/xat.git HEAD:main
echo 'Publicado: https://github.com/icarito/xat'
echo 'El build Android se dispara en main; requiere un pin de motor con XMPP y emojis.'
