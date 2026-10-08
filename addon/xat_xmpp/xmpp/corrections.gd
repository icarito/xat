extends Reference

# Plegado de XEP-0308 (correcciones de mensaje). Helper puro, testeable headless.
#
# Una corrección es un <message> con <replace id='ID-ORIGINAL'/>. Las ediciones
# sucesivas referencian SIEMPRE el id original, así que la cadena entera colapsa
# en una sola fila/burbuja, conservando el timestamp y la dirección del ancla.
#
# Este archivo plegа una página (live o MAM). `store` es opcional: si se pasa un
# objeto con `update_by_request_id(bare_jid, request_id, body) -> bool`, cuando
# devuelve true la corrección se considera aplicada a una fila ya persistida y
# se descarta del resultado (no se duplica).

# Item esperado (Dictionary):
#   { bare_jid, body, direction ("in"/"out"), ts, mam_id, quick, commands,
#     request_id, replace_id }
static func fold_page(p_page: Array, p_store = null) -> Array:
	var output := []
	var position_by_request := {}
	for raw in p_page:
		var item = raw
		var replace_id = str(item.get("replace_id", ""))
		var direction = str(item.get("direction", ""))

		if replace_id != "" and direction == "in":
			if position_by_request.has(replace_id):
				var pos = position_by_request[replace_id]
				var prev = output[pos]
				var merged = item.duplicate()
				merged["direction"] = prev.get("direction", "in")
				merged["ts"] = prev.get("ts", "")
				merged["mam_id"] = prev.get("mam_id", "")
				merged["request_id"] = prev.get("request_id", replace_id)
				output[pos] = merged
				continue
			if p_store != null and p_store.update_by_request_id(str(item.get("bare_jid", "")), replace_id, str(item.get("body", ""))):
				continue
			# Objetivo desconocido (se abrió a mitad del turno): anclar bajo el id
			# original para que las ediciones siguientes colapsen acá.
			item = item.duplicate()
			item["request_id"] = replace_id

		var rid = str(item.get("request_id", ""))
		if rid != "" and direction == "in":
			position_by_request[rid] = output.size()
		output.append(item)
	return output
