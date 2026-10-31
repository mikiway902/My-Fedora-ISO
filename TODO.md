# TODO: классическая сборка (без атомарности)

Состояние на 2026-10-31. Атомарная сборка сохранена, рядом добавлен классический
netinstall-ISO на базе Fedora Everything.

## Готово

- Общие списки пакетов `build_files/packages.sh` для атомарной и классической сборки.
- Атомарные образы `driftwm` и `gnome` собираются после рефакторинга, `bootc container lint` проходит.
- opencode CLI (`/usr/bin/opencode`), DeepSeek Harness (`dsh`) и конфиг без запросов
  разрешений (`/etc/skel/.config/opencode/opencode.json`) проверены в контейнере.
- Расширение VS Code `sst-dev.opencode` добавлено в `vscode-extensions`.
- RuDesktop убран из всех образов.
- Kickstart-файлы генерируются из актуального `packages.sh` и проходят `ksvalidator`
  (проверено в контейнере `quay.io/fedora/fedora:44`).
- Проверено, что в netinst включены онлайн-репозитории Fedora (`fedora`, `updates`)
  с GPG-ключами, и что списки пакетов разрешаются (gnome — 1844 пакета, driftwm — 1121).
- Проверено, что RPM Fusion, `code`, `unrar`, COPR `quickshell`/`swayosd` и
  `swap ffmpeg-free ffmpeg` разрешаются.
- `mkksiso` запускается rootful с `--privileged`; при локальном запуске скрипт сам
  вызывает `sudo podman`.
- `just check` и shellcheck проходят; атомарные `gnome` и `driftwm` собраны локально.
- `system_files` в классическом `%post` распаковываются с `--no-same-owner`, чтобы
  файлы в `/` принадлежали root, а не пользователю, собиравшему ISO.
- README прочитан целиком, противоречий между атомарной и классической сборкой нет.

## Осталось

1. Запушить изменения и прогнать в GitHub Actions workflow **Build classic ISO**
   для `gnome` и `driftwm`: локально нет ни `gh`, ни токена, ни rootful-доступа
   без пароля, поэтому полная сборка ISO не проверена.
2. Загрузить собранный классический ISO в VM и проверить:
   - интерактивную разметку диска (dual-boot с Windows);
   - создание пользователя через `initial-setup`/`gnome-initial-setup`;
   - установку vendor RPM, opencode, DSH;
   - работу `quickshell`/`swayosd` в driftwm;
   - отсутствие запросов разрешений у opencode;
   - появление расширения opencode в VS Code после первого входа.
3. Решить судьбу этого TODO: удалить или оставить как заметку.
