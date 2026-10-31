class_name DoorAudio
extends RefCounted
## Small cached, deterministic sound placeholders; replace via AudioStream slots.

static var _rattle: AudioStreamWAV
static var _latch: AudioStreamWAV


static func rattle() -> AudioStreamWAV:
	if _rattle == null:
		_rattle = _make_sound(true)
	return _rattle


static func latch() -> AudioStreamWAV:
	if _latch == null:
		_latch = _make_sound(false)
	return _latch


static func _make_sound(metallic: bool) -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	data.resize(int(rate * 0.28))
	for index: int in data.size():
		var t := float(index) / rate
		var pulse := fmod(t, 0.075) if metallic else t
		var envelope := exp(-pulse * (85.0 if metallic else 38.0)) * (1.0 - t / 0.28)
		var tone := sin(TAU * t * (1170.0 if metallic else 115.0))
		var noise := sin(float(index) * 78.233) * sin(float(index) * 12.9898)
		data[index] = clampi(int(128.0 + (tone * 0.45 + noise * 0.55) * envelope * 110.0), 0, 255)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream
