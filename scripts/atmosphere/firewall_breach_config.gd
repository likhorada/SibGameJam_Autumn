class_name FirewallBreachConfig
extends Resource

const PORT_NUMBERS := [21, 22, 25, 53, 80, 443, 3306, 3389, 8080]

@export_range(1.0, 19.0) var duration_seconds: float = 15.0
@export_range(0, 9) var initial_open_ports: int = 6
@export_range(0.15, 5.0) var early_interval_min: float = 1.0
@export_range(0.15, 5.0) var early_interval_max: float = 2.0
@export_range(0.15, 5.0) var late_interval_min: float = 0.7
@export_range(0.15, 5.0) var late_interval_max: float = 1.2
@export_range(0.1, 2.0) var block_grace_seconds: float = 0.7
