extends Reference
class_name XatXmpp

# Raíz del addon xat_xmpp. Sólo concentra metadatos y las rutas de carga de los
# subsistemas; el protocolo real vive en los módulos de xat_xmpp/ (transporte,
# stanza, sesión, XEPs, historial). Testeable headless con `extends SceneTree`.

const VERSION := "0.1.0-plan"

const Jid := preload("res://addons/xat_xmpp/xmpp/jid.gd")
const Stanza := preload("res://addons/xat_xmpp/xmpp/stanza.gd")
