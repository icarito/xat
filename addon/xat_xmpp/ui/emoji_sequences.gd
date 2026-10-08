extends Reference

# This recognizes supported Unicode emoji sequences. It is intentionally not a
# complete UAX #29 grapheme segmenter (notably, it does not implement GB9c).
const VS15 = 0xFE0E
const VS16 = 0xFE0F
const ZWJ = 0x200D
const KEYCAP = 0x20E3
const RI_FIRST = 0x1F1E6
const RI_LAST = 0x1F1FF
const MODIFIER_FIRST = 0x1F3FB
const MODIFIER_LAST = 0x1F3FF
const TAG_FIRST = 0xE0020
const TAG_LAST = 0xE007F

# Returns a reusable lookup. `supported` can be the provider's canonical and
# alias sequence list; callers should compile it once, not once per message.
static func compile(supported: Array, properties: Dictionary = {}) -> Dictionary:
	var starts = {}
	for sequence in supported:
		if typeof(sequence) != TYPE_STRING or sequence == "":
			continue
		var cp = sequence.ord_at(0)
		if not starts.has(cp):
			starts[cp] = {}
		starts[cp][sequence] = true
	return {"starts": starts, "grapheme_break": properties.get("grapheme_break", []),
		"extended_pictographic": properties.get("extended_pictographic", []),
		"emoji": properties.get("emoji", [])}

# Compatibility wrapper for the original fixture-oriented API.
static func tokenize(text: String, supported: Array) -> Array:
	return tokenize_indexed(text, compile(supported))

static func tokenize_indexed(text: String, lookup: Dictionary) -> Array:
	var runs = []
	var text_start = 0
	var i = 0
	var starts = lookup.get("starts", {})
	while i < text.length():
		var first = _codepoint(text, i)
		var candidate_end = -1
		if _is_regional(first):
			candidate_end = _regional_cluster_end(text, i, lookup)
		elif _is_candidate_start(first, starts, lookup):
			candidate_end = _cluster_end(text, i, lookup)
		if candidate_end > i:
			var candidate = text.substr(i, candidate_end - i)
			var first_map = starts.get(first, {})
			if first_map.has(candidate) and not _contains_codepoint(candidate, VS15):
				if i > text_start:
					runs.append(_run("text", text.substr(text_start, i - text_start), text_start, i))
				runs.append(_run("emoji", candidate, i, candidate_end))
				i = candidate_end
				text_start = i
				continue
		# Keep an unsupported candidate intact so a supported prefix cannot consume it.
		if candidate_end > i:
			i = candidate_end
		else:
			i += 1
	if text_start < text.length():
		runs.append(_run("text", text.substr(text_start), text_start, text.length()))
	return runs

static func _run(kind: String, value: String, start: int, end: int) -> Dictionary:
	return {"kind": kind, "text": value, "start": start, "end": end}

static func _codepoint(value: String, index: int) -> int:
	return value.ord_at(index)

static func _contains_codepoint(value: String, wanted: int) -> bool:
	for i in range(value.length()):
		if _codepoint(value, i) == wanted:
			return true
	return false

static func _is_regional(cp: int) -> bool:
	return cp >= RI_FIRST and cp <= RI_LAST

static func _regional_pair_end(value: String, start: int) -> int:
	if start + 1 < value.length() and _is_regional(_codepoint(value, start + 1)):
		return start + 2
	return start + 1

static func _regional_cluster_end(value: String, start: int, lookup: Dictionary) -> int:
	return _cluster_tail_end(value, _regional_pair_end(value, start), lookup)

static func _is_candidate_start(cp: int, starts: Dictionary, lookup: Dictionary) -> bool:
	if starts.has(cp):
		return true
	return _has_property(lookup.get("emoji", []), cp) or _has_property(lookup.get("extended_pictographic", []), cp)

static func _cluster_end(value: String, start: int, lookup: Dictionary) -> int:
	return _cluster_tail_end(value, start + 1, lookup)

static func _cluster_tail_end(value: String, index: int, lookup: Dictionary) -> int:
	var i = _consume_extenders(value, index, lookup)
	while i < value.length() and _codepoint(value, i) == ZWJ:
		i += 1
		if i >= value.length():
			break
		# Consume the joined scalar even when it is unknown: otherwise a supported
		# pictograph before an unsupported ZWJ tail would be replaced as a prefix.
		i += 1
		i = _consume_extenders(value, i, lookup)
	return i

static func _consume_extenders(value: String, index: int, lookup: Dictionary) -> int:
	var i = index
	while i < value.length():
		var cp = _codepoint(value, i)
		if _is_builtin_extender(cp) or _has_grapheme_class(lookup.get("grapheme_break", []), cp, "Extend") or _has_grapheme_class(lookup.get("grapheme_break", []), cp, "SpacingMark"):
			i += 1
		else:
			break
	return i

static func _is_builtin_extender(cp: int) -> bool:
	return cp == VS15 or cp == VS16 or cp == KEYCAP or (cp >= MODIFIER_FIRST and cp <= MODIFIER_LAST) or (cp >= TAG_FIRST and cp <= TAG_LAST)

# Property tables are sorted inclusive [start, end] or [start, end, value] rows.
static func _has_property(ranges: Array, cp: int) -> bool:
	return _find_range(ranges, cp, "")

static func _has_grapheme_class(ranges: Array, cp: int, wanted: String) -> bool:
	return _find_range(ranges, cp, wanted)

static func _find_range(ranges: Array, cp: int, wanted: String) -> bool:
	var low = 0
	var high = ranges.size() - 1
	while low <= high:
		var mid = int((low + high) / 2)
		var row = ranges[mid]
		if cp < int(row[0]):
			high = mid - 1
		elif cp > int(row[1]):
			low = mid + 1
		else:
			return wanted == "" or (row.size() > 2 and str(row[2]) == wanted)
	return false
