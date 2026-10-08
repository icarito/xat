#!/bin/sh
# Extensión inline de xat sobre el fork Slug. No resetea ni descarta edits locales.
# Uso: tools/apply_emoji_patch.sh <checkout-del-motor>
set -eu

XAT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="${1:?falta checkout del motor}"
EMOJI_PATCH="$XAT/tools/patches/z_emoji_inline_source.patch"

if patch --force --silent --fuzz=0 --reverse --dry-run -d "$ENGINE" -p1 < "$EMOJI_PATCH" >/dev/null 2>&1; then
	echo "xat: extensión de emoji inline ya aplicada"
elif patch --batch --silent --fuzz=0 --forward --dry-run -d "$ENGINE" -p1 < "$EMOJI_PATCH" >/dev/null 2>&1; then
	patch --batch --silent --fuzz=0 --forward --no-backup-if-mismatch -d "$ENGINE" -p1 < "$EMOJI_PATCH"
	echo "xat: extensión de emoji inline aplicada"
else
	echo "xat: el parche de emoji no coincide con este motor; revisar sin descartar cambios locales" >&2
	exit 1
fi
