# TODO: My-Fedora-ISO

Полный чек-лист большого ТЗ лежит в [TASKS/megatask.md](TASKS/megatask.md).
Здесь — краткое состояние.

## Готово

- Atomic и Classic, каждый с GNOME и DriftWM; общие списки пакетов, отдельные
  механизмы установки/обновления.
- Пакеты разложены по категориям BASE / HARDWARE / POWER / GNOME / DRIFTWM /
  DEVELOPMENT / MULTIMEDIA / OPTIONAL; дубликаты запрещены тестом.
- TuneD-профили `my-fedora-p14s-*` и маппинг tuned-ppd; Boost в Power Saver не
  отключается, Wi-Fi/USB autosuspend не форсируются.
- Пороги заряда: сервис + `my-fedora-battery` + конфиг, пресеты 75/80, 40/80,
  95/100, повторное применение после сна, безопасный fallback без sysfs.
- `thinkpad-diagnostics`, `my-fedora-power-profile`, `Super+Shift+P` в DriftWM.
- Версии сторонних программ закреплены, SHA256 проверяется.
- Classic `%post` не падает из-за недоступности RPM Fusion/COPR/GitHub/npm.
- Atomic ISO: проверка DNS и retry с понятной ошибкой при недоступности GHCR.
- `just test`, `just validate`, `just check-packages`, `just sbom`; workflow
  Validate; SBOM и build metadata в CI; еженедельная Classic-сборка и теги.
- README описывает четыре варианта, питание, диагностику, rollback и ограничения.
- Локально: Atomic driftwm/gnome собираются, `bootc container lint` проходит
  (с предупреждениями от пакетов), `just check`, `just test`, `just validate`,
  `just check-packages` проходят.

## Осталось (требует push/железа/rootful podman)

1. Запушить и прогнать GitHub Actions: Validate, Atomic images, Classic ISO.
2. Собрать Atomic ISO (`just build-iso`) и Classic ISO; проверить установку в VM.
3. На P14s Gen 2 AMD проверить: сон/s2idle, Wi-Fi/BT после сна, отпечаток,
   пороги заряда на этой прошивке, яркость, подсветку клавиатуры, автономность.
4. Проверить обновление и откат Atomic (`bootc upgrade` / `bootc rollback`).
5. Проверить Dual Boot и ручную разметку на реальном диске.
6. Решить, включать ли сканирование уязвимостей (grype/trivy) в CI.
