extends Reference

# Códec IMA-ADPCM (4:1) para notas de voz. Godot 3 no trae encoder comprimido;
# este módulo codifica/decodifica en GDScript puro, así que graba y reproduce
# igual en Android y escritorio sin tocar el motor.
#
# Formato de salida: WAV con audio format 0x11 (IMA ADPCM), bloque de N samples.
# La decodificación es la inversa exacta, de modo que el round-trip es testeable.

# Tabla estándar IMA.
const STEP_TABLE := [
	7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
	50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230,
	253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963,
	1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327,
	3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487,
	12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767]
const INDEX_TABLE := [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]

# Codifica un sample int16 y devuelve el nibble (0..15) y actualiza el estado.
static func _encode_sample(p_sample: int, p_index: int, p_predicted: int) -> Array:
	var diff = p_sample - p_predicted
	var sig = 0
	if diff < 0:
		sig = 8
		diff = -diff
	var step = STEP_TABLE[p_index]
	var delta = 0
	var vpdiff = step >> 3
	if diff >= step:
		delta = 4
		diff -= step
		vpdiff += step
	if diff >= step >> 1:
		delta |= 2
		diff -= step >> 1
		vpdiff += step >> 1
	if diff >= step >> 2:
		delta |= 1
		vpdiff += step >> 2
	if sig != 0:
		p_predicted -= vpdiff
	else:
		p_predicted += vpdiff
	p_predicted = int(clamp(p_predicted, -32768, 32767))
	p_index += INDEX_TABLE[delta + sig]
	p_index = int(clamp(p_index, 0, 88))
	return [delta | sig, p_index, p_predicted]

# Decodifica un nibble IMA y actualiza el estado.
static func _decode_sample(p_nibble: int, p_index: int, p_predicted: int) -> Array:
	var step = STEP_TABLE[p_index]
	var sig = p_nibble & 8
	var delta = p_nibble & 7
	var vpdiff = step >> 3
	if delta & 4:
		vpdiff += step
	if delta & 2:
		vpdiff += step >> 1
	if delta & 1:
		vpdiff += step >> 2
	if sig != 0:
		p_predicted -= vpdiff
	else:
		p_predicted += vpdiff
	p_predicted = int(clamp(p_predicted, -32768, 32767))
	p_index += INDEX_TABLE[p_nibble]
	p_index = int(clamp(p_index, 0, 88))
	return [p_predicted, p_index]

# --- API pública ---

# Codifica un buffer PCM16 LE (mono o interleaved) a IMA-ADPCM por bloques.
# Layout por bloque: [predictor i16 LE][index u8][0] + nibbles (2 por byte, low
# primero), un bloque por canal de forma independiente. Para voz usamos mono.
# Devuelve {data, block_align, samples_per_block, channels, sample_rate, total_samples}.
static func encode(p_pcm: PoolByteArray, p_channels: int, p_sample_rate: int, p_block_samples: int = 2048) -> Dictionary:
	var samples := _to_ints(p_pcm)
	var frames = samples.size() / p_channels
	var samples_per_block = max(8, int(p_block_samples / p_channels) * p_channels)
	var out := PoolByteArray()
	var frame := 0
	var total_samples := 0
	while frame < frames:
		var block_frames = min(samples_per_block / p_channels, frames - frame)
		if block_frames <= 0:
			break
		var idx := []
		var pred := []
		for ch in range(p_channels):
			var s0 = samples[frame * p_channels + ch]
			idx.append(0)
			pred.append(s0)
			var u = s0 if s0 >= 0 else s0 + 65536
			out.append(u & 0xFF)
			out.append((u >> 8) & 0xFF)
			out.append(0)
			out.append(0)
		var nibbles := []
		for ch in range(p_channels):
			nibbles.append([])
		for f in range(block_frames):
			for ch in range(p_channels):
				var s = samples[(frame + f) * p_channels + ch]
				var r = _encode_sample(s, idx[ch], pred[ch])
				nibbles[ch].append(r[0])
				idx[ch] = r[1]
				pred[ch] = r[2]
		# Empaqueta los nibbles interleaved por frame (L,R,L,R...): dos por byte.
		var flat := []
		for f in range(block_frames):
			for ch in range(p_channels):
				flat.append(nibbles[ch][f])
		var k := 0
		while k < flat.size():
			var lo = flat[k]
			var hi = flat[k + 1] if k + 1 < flat.size() else 0
			out.append((hi << 4) | lo)
			k += 2
		total_samples += block_frames * p_channels
		frame += block_frames
	var nibble_bytes_per_block = int(ceil(samples_per_block / 2.0))
	return {
		"data": out,
		"block_align": p_channels * 4 + nibble_bytes_per_block,
		"samples_per_block": samples_per_block,
		"channels": p_channels,
		"sample_rate": p_sample_rate,
		"total_samples": total_samples,
	}

# Decodifica IMA-ADPCM (formato del encoder de arriba) a PCM16 LE interleaved.
static func decode(p_data: PoolByteArray, p_channels: int, p_samples_per_block: int) -> PoolByteArray:
	var out := PoolByteArray()
	var header = p_channels * 4
	# Nibbles por bloque (todos los canales interleaved).
	var frames_per_block = int(p_samples_per_block / p_channels)
	var nibble_bytes = int(ceil(frames_per_block * p_channels / 2.0))
	var pos := 0
	var total = p_data.size()
	while pos + header < total:
		var idx := []
		var pred := []
		for ch in range(p_channels):
			if pos + ch * 4 + 3 >= total:
				return out
			var h = pos + ch * 4
			var s0 = p_data[h] | (p_data[h + 1] << 8)
			if s0 >= 32768:
				s0 -= 65536
			pred.append(s0)
			idx.append(p_data[h + 2])
		var p = pos + header
		# Último bloque puede estar incompleto: lee hasta el fin del buffer.
		var avail = min(nibble_bytes, total - p)
		if avail <= 0:
			break
		# Desempaqueta a nibbles interleaved.
		var flat := []
		for b in range(avail):
			var byte = p_data[p + b]
			flat.append(byte & 0x0F)
			flat.append((byte >> 4) & 0x0F)
		var block_frames = int(floor(flat.size() / float(p_channels)))
		# Decodifica por frame, interleaved por canal.
		for f in range(block_frames):
			for ch in range(p_channels):
				var ni = f * p_channels + ch
				if ni >= flat.size():
					break
				var r = _decode_sample(flat[ni], idx[ch], pred[ch])
				pred[ch] = r[0]
				idx[ch] = r[1]
				var s = pred[ch]
				var u = s if s >= 0 else s + 65536
				out.append(u & 0xFF)
				out.append((u >> 8) & 0xFF)
		pos += header + avail
	return out

# PCM16 LE -> Array[int].
static func _to_ints(p_pcm: PoolByteArray) -> Array:
	var out := []
	var i := 0
	var n = p_pcm.size() / 2
	while i < n:
		var v = p_pcm[i * 2] | (p_pcm[i * 2 + 1] << 8)
		if v >= 32768:
			v -= 65536
		out.append(v)
		i += 1
	return out