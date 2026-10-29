# Скрипты

GDScript, `snake_case.gd`, табы. По мере реализации создаём подпапки:
`player/`, `apartment/`, `terminal/`, `surveillance/`, `threats/`, `ui/`, `data/`.
Соответствующие сцены размещаем в `scenes/<подсистема>/`.

`main.gd` управляет режимами WALKING → ENTERING → COMPUTER → LEAVING и мышью.
`player/player.gd` отвечает за движение, обзор и луч взаимодействия.
Геометрия квартиры хранится в обычной `.tscn`, без runtime-генерации.
Связи между компонентами — ссылки и сигналы, без обязательных Autoload-менеджеров.
