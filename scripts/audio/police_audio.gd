class_name PoliceAudio
extends RefCounted
## Temporary radio burst, NOT synthesized speech. Optional voice clips replace it.
static var _radio: AudioStreamWAV


static func radio() -> AudioStreamWAV:
	if _radio == null:
		var rate := 22050
		var data := PackedByteArray()
		data.resize(int(rate * 0.65))
		for index: int in data.size():
			var t := float(index) / rate
			var envelope := minf(t * 80.0, 1.0) * minf((0.65 - t) * 30.0, 1.0)
			var noise := sin(index * 78.233) * sin(index * 12.9898)
			var carrier := sin(TAU * 880.0 * t) if t < 0.08 or t > 0.55 else noise
			data[index] = clampi(int(128.0 + carrier * envelope * 80.0), 0, 255)
		_radio = AudioStreamWAV.new()
		_radio.format = AudioStreamWAV.FORMAT_8_BITS
		_radio.mix_rate = rate
		_radio.data = data
	return _radio
