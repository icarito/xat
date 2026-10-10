#!/bin/sh
# Opt-in Joe Work fleet view; the default Xat launcher remains generic.
set -eu

XAT_JOEWORK_MONITORING_JID=operator@hablar.fuentelibre.org
XAT_JOEWORK_MONITORING_NODE=joework/monitoring/owner
export XAT_JOEWORK_MONITORING_JID XAT_JOEWORK_MONITORING_NODE

exec "$(dirname "$0")/run.sh" "$@"
