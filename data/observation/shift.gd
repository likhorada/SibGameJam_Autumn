extends RefCounted
## Positions, durations and evidence IDs; presentation lives in observation_location.gd.
const DRINKS := ["OBS_TEA", "OBS_COFFEE", "OBS_WINE", "OBS_SODA"]
const PATHS := ["OBS_ALLEY", "OBS_AVENUE", "OBS_PARK"]
const OFFICE := [
	{"point": Vector3(0, 0, 1), "seconds": 2.0},
	{"point": Vector3(4, 0, 1), "seconds": 5.0},
	{"point": Vector3(4, 0, -6), "seconds": 7.0},
]
const SHOP := [
	{"point": Vector3(-4, 0, 1), "seconds": 8.0},
	{"point": Vector3(-4, 0, 1), "seconds": 12.0},
	{"point": Vector3(3, 0, 0), "seconds": 10.0, "event": "take"},
	{"point": Vector3(3, 0, 0), "seconds": 6.0},
	{"point": Vector3(0, 0, 3), "seconds": 8.0, "event": "checkout"},
	{"point": Vector3(0, 0, 3), "seconds": 12.0},
	{"point": Vector3(0, 0, 7), "seconds": 6.0},
]
const STREET_ENTRY := [
	{"point": Vector3(0, 0, 0), "seconds": 12.0, "event": "branch"},
]
const EXITS := [Vector3(-12, 0, -5), Vector3(0, 0, -16), Vector3(12, 0, -5)]
