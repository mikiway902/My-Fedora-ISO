# Master task: My-Fedora-ISO modernization

Чек-лист по большому ТЗ от 2026-10-31. Отмечать `[x]` только после реальной
проверки; всё, что требует физического ThinkPad P14s Gen 2 AMD, остаётся `[ ]`
до теста на железе.

## 1. Аудит

- [x] README, Containerfile, Justfile, image-template.env
- [x] build_files/packages.sh, build.sh, classic-post.sh, generate-kickstarts.sh
- [x] disk_config/, system_files/, .github/workflows/, setup.sh
- [x] Карта архитектуры и список проблем (см. отчёт в конце сессии)

## 2. Atomic / Classic

- [x] Atomic: bootc, Universal Blue base-main (driftwm) и silverblue-main (gnome)
- [x] Classic: Anaconda + Fedora Everything, без bootc и без GHCR
- [x] Общие списки пакетов, но отдельные механизмы установки/обновления
- [x] Разделение GNOME и DriftWM конфигураций
- [x] Независимая сборка каждого из четырёх вариантов (`just build-atomic-*`,
      `just build-classic-*`, `just build-all`, `just build-all-isos`)

## 3. Пакеты

- [x] Категории BASE / HARDWARE / POWER / GNOME / DRIFTWM / DEVELOPMENT /
      MULTIMEDIA / OPTIONAL
- [x] Один пакет — одна категория (проверяется тестом)
- [x] Нет TLP / auto-cpufreq / второго power-profiles-daemon
- [x] Все существующие приложения сохранены
- [x] Версии сторонних программ закреплены, SHA256 проверяется
- [ ] Проверить обновление закреплённых версий (ручное действие при релизе)

## 4. ThinkPad P14s Gen 2 AMD

- [x] TuneD: три профиля (balanced, powersave, performance) + battery-вариант
- [x] tuned-ppd остаётся единственным демоном, EPP через штатный TuneD
- [x] Не добавляются параметры ядра `amd_pstate=active` и старые workaround
- [x] Пороги заряда 75/80, 40/80, 95/100 через `my-fedora-battery`
- [x] Настройки сохраняются в `/etc/my-fedora/battery.conf`, переживают ребут
- [x] Повторное применение порогов после resume (systemd unit)
- [x] Нет глобального USB autosuspend и принудительного Wi-Fi powersave
- [x] `thinkpad-diagnostics` (CPU, battery, thermal, sleep, network, storage)
- [ ] Проверить на реальном железе: s2idle/S0ix, Wi-Fi/BT после сна, пороги,
      SMART, температуры, автономность

## 5. GNOME

- [x] Silverblue, GDM, штатные настройки сохранены
- [x] Caffeine / Dash to Dock / AppIndicator / Tweaks без лишнего
- [x] Порог заряда в GNOME — штатный UPower (Preserve Battery Health), наш
      сервис для GNOME не включается
- [x] Сон от батареи оставлен штатным, на AC отключён (gschema)
- [ ] Проверить на реальном GNOME

## 6. DriftWM

- [x] greetd/tuigreet, Wayland, xwayland-satellite, порталы, PipeWire
- [x] swayidle/swaylock/brightnessctl/polkit/NetworkManager/Bluetooth
- [x] Управление профилем питания: `my-fedora-power-profile` + `Super+Shift+P`
- [x] Крышка: на AC не спит, от батареи спит (50-lid-ac.conf)
- [ ] Проверить на реальном DriftWM

## 7. Общее железо

- [x] fwupd, fprintd, upower, thinkpad_acpi (ядро), NetworkManager, BlueZ
- [x] Отпечаток для login/sudo/polkit, пароль как fallback
- [x] BIOS через LVFS вручную (`fwupdmgr`), без автоматической установки
- [ ] Проверить сканер отпечатков и подсветку клавиатуры на железе

## 8. Btrfs

- [x] Atomic: схема bootc не меняется
- [x] Classic: интерактивная разметка Anaconda, btrfs по умолчанию
- [x] Snapper/Btrfs Assistant не конфликтуют с bootc (в Atomic не настраиваются)
- [ ] Проверить установку и Dual Boot на реальном ISO

## 9. ISO / Anaconda

- [x] Classic ISO: SHA256 исходного Fedora Everything ISO проверяется по официальному CHECKSUM
- [x] Classic kickstart: без bootc, пакеты из репозиториев Fedora
- [x] Classic %post: третьи стороны best-effort, сеть не роняет установку
- [x] Classic: пункт Windows в GRUB через `/etc/grub.d/40_custom` (Atomic — через bootupd/custom.cfg)
- [x] Atomic ISO: retry + понятное сообщение при недоступности GHCR
- [x] Ручная разметка и создание пользователя через initial-setup
- [ ] Проверить чистую установку, Dual Boot, существующий EFI на железе

## 10. Безопасность

- [x] SHA256 для opencode, PdfCraft, Happ; версии закреплены, driftwm закреплён (`v0.21.0`)
- [x] Нет `curl | sh` от root; скрипты из репозитория
- [x] Секреты только через GitHub Secrets
- [x] ShellCheck, bash -n, actionlint, ksvalidator, systemd-analyze, TOML,
      hadolint в `just validate`
- [x] SBOM (SPDX) для Atomic-образов
- [ ] Сканирование уязвимостей grype/trivy (не включено в CI: нет проверенного
      источника БД в текущем окружении)

## 11. CI/CD

- [x] Четыре независимых варианта сборки
- [x] validate workflow (исходники, kickstarts, unit-файлы)
- [x] Atomic images: push/schedule/manual/tag, SBOM
- [x] Atomic ISOs и Classic ISOs: manual, Classic ещё и по расписанию/тегу
- [x] Артефакты только после проверки ISO
- [x] build metadata и SHA256SUMS
- [ ] Проверить workflows в GitHub Actions (нужен push)

## 12. Документация

- [x] README: четыре варианта, установка, Dual Boot, обновления, откат
- [x] README: профили питания, пороги заряда, диагностика, сборка, CI
- [x] Ограничения и непроверенные функции отмечены

## 13. Финальная проверка

- [x] `just check`, `just test`, `just validate` локально
- [ ] Собрать все четыре варианта (Atomic — локально можно, Classic ISO —
      нужен rootful podman/пароль)
- [ ] Прогнать GitHub Actions
- [ ] Проверить на физическом ThinkPad P14s Gen 2 AMD

## Правила

- Не переписывать проект с нуля.
- Не удалять функции без объяснения (удалён только tmpfiles-порог, заменён
  сервисом + CLI + конфигом).
- Не добавлять непроверенные параметры ядра.
- Не смешивать GNOME и DriftWM.
- Не заявлять о пройденных тестах, которых не было.
