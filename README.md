# My-Fedora-ISO

Два своих образа Fedora Atomic для ThinkPad P14s Gen 2 AMD (Ryzen 7 PRO 5850U, Radeon Vega 8) с одинаковым набором программ. Работают рядом с Windows. Основа: шаблон [ublue-os/image-template](https://github.com/ublue-os/image-template). Проверено по источникам 2026-10-29.

| Образ | Оболочка | Основа |
|---|---|---|
| `ghcr.io/mikiway902/my-fedora-iso-driftwm` | [driftwm](https://github.com/malbiruk/driftwm), вход через greetd + tuigreet | `ublue-os/base-main:44` (Fedora без DE) |
| `ghcr.io/mikiway902/my-fedora-iso-gnome` | GNOME, вход через GDM | `ublue-os/silverblue-main:44` (Silverblue) |

В обеих основах уже есть кодеки и полная Mesa из negativo17. Freeworld Mesa из RPM Fusion **не** ставится: она конфликтует с negativo17, а H.264/HEVC и так работают.

## Как устроено

| Файл | Что в нём |
|---|---|
| [Containerfile](Containerfile) | Этапы `driftwm` и `gnome`, нужный выбирается через `--target`. driftwm собирается из последнего релиза, закрепить версию можно через `DRIFTWM_VERSION` |
| [build_files/build.sh](build_files/build.sh) | Списки пакетов: `SESSION` (только driftwm), `LAPTOP` (железо), `APPS` (программы из репозиториев), `VENDOR_RPMS` (RPM разработчиков). Всё, кроме `SESSION`, общее |
| [system_files/usr/share/my-fedora/](system_files/usr/share/my-fedora) | Списки `flatpaks`, `vscode-extensions`, пункт Windows для GRUB |
| [system_files/](system_files) | Копируется в `/`: greetd, профиль kanshi, лимит заряда, уведомление о прошивках (всё это только для driftwm, в образе GNOME удаляется или не включается), репозиторий VS Code, сервисы установки |
| [disk_config/iso-driftwm.toml](disk_config/iso-driftwm.toml), [iso-gnome.toml](disk_config/iso-gnome.toml) | Установщик Anaconda для каждого образа. Модуль Users включён: в driftwm нет мастера первого запуска, поэтому пользователя создаёт установщик |
| [Justfile](Justfile) | Переменная `VARIANT` (`driftwm` по умолчанию или `gnome`) задаёт этап, имя образа и ISO |

## Программы

| Программа | Откуда | Обновления |
|---|---|---|
| Firefox, Git, qBittorrent, mpv, Nautilus, File Roller + 7zip + unrar, grim/slurp/swappy (скриншоты) | Fedora | С образом |
| VS Code | Репозиторий Microsoft | С образом |
| Расширение Claude Code для VS Code | Marketplace, при первом входе пользователя | Само, через VS Code |
| `docker` / `docker compose` (поверх rootless Podman) | Fedora: `podman-docker`, `podman-compose` | С образом |
| PdfCraft, Happ, opencode desktop | Последний релиз на GitHub на момент сборки | С образом |
| RuDesktop | Последняя версия с rudesktop.ru (сборка для РЕД ОС) | С образом |
| Discord, Telegram, Moonlight, OnlyOffice, Podman Desktop, Bazaar (магазин Flatpak), Flatseal (права Flatpak) | Flathub, при первой загрузке | Сами, таймер Flatpak |

Программу из списков `flatpaks` или `vscode-extensions` можно добавить в любой момент: после обновления системы она установится сама. Если пользователь удалил программу, обратно она не ставится.

Образы пересобираются каждый день в 06:05 по Москве, при каждом push и вручную (Actions → Run workflow). GitHub отключает расписание, если в репо 60 дней не было коммитов. Тогда его нужно включить заново на вкладке Actions.

## Сборка

### Через GitHub (рекомендую)

1. Запушьте репо на GitHub как `mikiway902/My-Fedora-ISO`. Если имя другое, поправьте `REPO_ORGANIZATION` в [image-template.env](image-template.env) и адреса в `disk_config/iso-*.toml`.
2. Создайте ключ подписи, без него сборка падает:
   ```bash
   COSIGN_PASSWORD="" cosign generate-key-pair
   ```
   ```bash
   gh secret set SIGNING_SECRET < cosign.key
   ```
   Закоммитьте `cosign.pub`. `cosign.key` не коммитьте никогда, он уже в `.gitignore`.
3. Push в `main` запускает `build.yml`, и он собирает оба образа параллельно. Сделайте оба пакета публичными в настройках GHCR.
4. Actions → **Build disk images** → Run workflow. В Artifacts появятся `driftwm-anaconda-iso` и `gnome-anaconda-iso`.

### Локально (Linux с podman и just)

```bash
VARIANT=gnome just build && VARIANT=gnome just build-iso
```

Без `VARIANT` собирается driftwm. ISO будет в `output/bootiso/install.iso`. Проверить в VM можно так: `just run-vm-iso`.

### Обновления после установки

Система тянет новые сборки из GHCR сама (`bootc upgrade`). Поменяли `build.sh`, сделали push, перезагрузились, и изменения на месте. Откат: `sudo bootc rollback`.

## Переключение driftwm ⇄ GNOME

ISO нужен только для первой установки. Дальше можно переключаться в любую сторону:

```bash
sudo bootc switch ghcr.io/mikiway902/my-fedora-iso-gnome:latest
```

```bash
sudo bootc switch ghcr.io/mikiway902/my-fedora-iso-driftwm:latest
```

После команды перезагрузитесь. Домашняя папка, Flatpak-приложения и настройки в `/etc` сохраняются, меняется только сама система. Если что-то не так, `sudo bootc rollback` вернёт предыдущий образ, или выберите его в меню GRUB.

## Windows + Fedora на одном ноутбуке

Подходит любой порядок. Проще ставить сначала Windows. Если Fedora уже стоит, смотрите [вариант Б](#вариант-б-сначала-fedora-потом-windows).

### Вариант А: сначала Windows, потом Fedora

**В Windows**
1. Сохраните ключ восстановления BitLocker ([aka.ms/myrecoverykey](https://aka.ms/myrecoverykey) или «Управление BitLocker»). При первом запуске Windows через GRUB он может понадобиться.
2. Отключите быстрый запуск: Панель управления → Электропитание → Действия кнопок питания. Иначе Windows держит диск «полуспящим», и Linux может повредить её файлы.
3. Освободите место: «Управление дисками» → C: → Сжать том, минимум 100–150 ГБ. Новый раздел не создавайте, оставьте место неразмеченным.
4. Время. Windows хранит часы в местном времени, Linux в UTC, из-за этого после переключения часы сбиваются. Переведите Windows на UTC (командная строка от администратора):
   ```
   reg add "HKLM\System\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /d 1 /t REG_DWORD /f
   ```

**Установка Fedora**
1. Secure Boot оставьте **включённым**, он нужен Windows 11. Загрузитесь с флешки: F12 на логотипе Lenovo → USB.
2. В Anaconda: Место установки → диск → «Освободить место» или ручная разметка. Ставьте только в свободное место. Существующий EFI-раздел (~100–260 МБ, FAT32) **не форматируйте**, Fedora добавит туда свой загрузчик рядом с Windows. Включите шифрование (LUKS).
3. После установки зарегистрируйте ключ Universal Blue, иначе модули ядра из образа не загрузятся при Secure Boot:
   ```bash
   ujust enroll-secure-boot-key
   ```
   При перезагрузке появится синий экран MokManager: Enroll MOK → Continue → пароль `universalblue`.

### Вариант Б: сначала Fedora, потом Windows

Установщик Windows не стирает загрузчик Fedora: он находит существующий EFI-раздел и кладёт свой загрузчик рядом. Но он ставит себя первым в порядке загрузки, и это нужно один раз исправить.

1. **Fedora.** Secure Boot включён, флешка через F12. В Anaconda выберите ручную разметку, а не «весь диск». Оставьте 100–150 ГБ **неразмеченными** под Windows. Разделы Fedora:
   - `/boot/efi`: 600 МБ, EFI;
   - `/boot`: 2 ГБ, ext4;
   - остальное под btrfs с шифрованием (LUKS).

   После установки зарегистрируйте ключ, как в варианте А: `ujust enroll-secure-boot-key`.
2. **Windows.** Флешка через F12 → «Выборочная установка» → выберите **неразмеченное пространство** → «Далее». Сами разделы не создавайте и ничего не удаляйте: служебные разделы Windows создаст сама.
3. **В Windows** сделайте то же, что в варианте А: сохраните ключ BitLocker (Windows 11 на ноутбуках часто включает шифрование сама), отключите быстрый запуск, переведите часы на UTC.
4. **Верните Fedora первой в загрузке.** Два способа:
   - BIOS: F1 на логотипе → Startup → Boot, поднимите Fedora выше Windows Boot Manager;
   - или загрузитесь в Fedora через F12 и выполните `sudo efibootmgr`. Команда покажет номера пунктов. Затем `sudo efibootmgr -o <номер Fedora>,<номер Windows>`.
5. Пункт «Windows» появится в GRUB сам, с ближайшей загрузки Fedora.

### Выбор системы при включении
- В GRUB есть пункты Fedora и «Windows». Пункт Windows добавляет сервис `grub-windows-entry` при первой загрузке, он появится со второй перезагрузки. Если вы сами создали `/boot/grub2/custom.cfg`, сервис его не трогает.
- Запасной путь, который работает всегда: F12 на логотипе Lenovo → Windows Boot Manager или Fedora.
- Если после обновления Windows ноутбук грузится сразу в Windows, верните Fedora первой в BIOS (F1 → Startup → Boot) или выберите её через F12.

## После первой загрузки

- **Отпечаток.** Вход, sudo и запросы прав по отпечатку уже включены в обоих образах. Осталось записать палец: `fprintd-enroll`, а в GNOME через Настройки → Пользователи. Пока отпечаток не записан, работает обычный пароль.
- **Лимит заряда 80 %.** В driftwm он включён сразу: зарядка до 80 %, дозарядка ниже 75 % ([thinkpad-battery.conf](system_files/usr/lib/tmpfiles.d/thinkpad-battery.conf)). Чтобы один раз зарядить до 100 %, выполните `echo 100 | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold`, после перезагрузки снова будет 80. В GNOME: Настройки → Питание → «Preserve Battery Health».
- **Ночной режим в driftwm** настроен на координаты Москвы. Если вы в другом городе, поправьте `wlsunset -l … -L …` в `~/.config/driftwm/config.toml`.
- **Внешний монитор в driftwm.** Профили описываются в `~/.config/kanshi/config`, пример там уже есть.

## driftwm: что есть из коробки

Новый пользователь получает [панель и скрипты из extras driftwm](https://github.com/malbiruk/driftwm/tree/main/extras) и наш [конфиг](system_files/usr/share/my-fedora/driftwm-config.toml) поверх.

| Клавиши / событие | Что происходит |
|---|---|
| `Alt+Shift` (нажать и отпустить) | Переключение us ⇄ ru. Через XKB это не сделано, потому что тогда сломались бы перетаскивания с `Alt+Shift` |
| `Super+A` или щипок 4 пальцами | Домашний экран с панелью: время, раскладка, Wi-Fi, Bluetooth, батарея и профиль питания, громкость, яркость, трей, меню питания |
| `Super+D` | Поиск по окнам и приложениям (fuzzel) |
| `Super+V` | История буфера обмена (cliphist) |
| `Super+N` | Центр уведомлений (swaync) |
| `Print` / `Shift+Print` / `Ctrl+Print` | Область с редактором (swappy) / область в буфер / активное окно в буфер |
| Клавиши громкости и яркости | Индикатор на экране (swayosd) |
| Медиаклавиши | playerctl, работают в любом плеере |
| 5 / 5,5 / 15 минут простоя | Блокировка / выключение экрана / сон. Перед сном экран блокируется всегда |
| Вечер | Тёплые цвета экрана (wlsunset) |
| Раз в день | Уведомление, если для BIOS, EC или сканера есть новая прошивка |

Кроме того, в образе driftwm есть печать (CUPS и «Настройки принтера»), а в обоих образах — шрифты, совместимые с Times New Roman, Arial, Calibri и Cambria. С ними документы MS Office в OnlyOffice не разъезжаются.

## Без своего образа

Если driftwm не нужен, ставьте **Fedora Workstation** и запустите [setup.sh](setup.sh). Другой вариант: **Bluefin** или **Aurora**, им скрипт не нужен.

Fedora 45 перенесли с 20 октября на 27 октября (возможно, на 3 ноября). Если 45 ещё не вышла, ставьте 44 и обновитесь позже. Rawhide не берите.

## Что исправлено в исходной шпаргалке

| Было | На самом деле |
|---|---|
| `power-profiles-daemon` стоит по умолчанию | С Fedora 41 по умолчанию стоит **`tuned-ppd`**. Он даёт тот же интерфейс (`powerprofilesctl`, переключатель в GNOME). Менять его не обязательно. Если хотите вернуть PPD: `sudo dnf swap tuned-ppd power-profiles-daemon` |
| `amd_pstate` active [Вероятно] | [Точно] Cezanne поддерживает CPPC через MSR. С ядра 6.5 режим `active` включён по умолчанию. Если в `status` пусто, значит ядро откатилось на `acpi-cpufreq`. Тогда проверьте, включён ли CPPC в BIOS |
| freeworld Mesa: «команды из скрипта» | Сейчас пакет ставится напрямую, `swap` для VA больше не нужен. Команды есть в `setup.sh` |
| btrfs + снапшоты | btrfs стоит в Fedora по умолчанию. Снапшотов из коробки **нет**, их нужно настроить: snapper или btrfs-assistant. LUKS включается галочкой в Anaconda |
| Лимит заряда через `tmpfiles` | В GNOME 48+ есть встроенная опция: Настройки → Питание → «Preserve Battery Health» (75–80 %), через UPower и `thinkpad_acpi`. Ручной `tmpfiles` спорил бы с ней. Используйте только одно |
| `fprintd` [Догадка] | На P14s Gen 2 AMD стоит Synaptics Prometheus (`06cb:00bd`). libfprint его поддерживает, fprintd в Workstation уже установлен. Прошивку сканера обновляет fwupd |
| Сон: «s2idle, смотрите BIOS» [Догадка] | Подтверждено: у этой модели были баги входа и выхода из s0ix (drm/amd #1738, #1800). В ядро добавлен quirk для P14s Gen 2. Нужны свежие BIOS и ядро. При проблемах запустите `amd_s2idle.py` от AMD |
| 5–8 Вт в простое | Источник не найден, оставляю как [Догадка] |

Остальное подтверждено: TLP или auto-cpufreq рядом с PPD или tuned-ppd ставить нельзя, systemd-юниты конфликтуют. `thermald` нужен только для Intel. Прошивки приходят через LVFS.

## Проверка на ноутбуке

Для любого варианта:

```bash
cat /sys/devices/system/cpu/amd_pstate/status   # active
powerprofilesctl                                # три профиля
vainfo | grep -E 'H264|HEVC'                    # декодирование есть
cat /sys/power/mem_sleep                        # [s2idle]
lsusb | grep -i 06cb                            # сканер отпечатков
```

Вручную: сон и пробуждение (крышка, 10+ минут), Wi-Fi, Bluetooth, звук, TrackPoint, жесты тачпада в driftwm.

## Источники

- [RPM Fusion: Multimedia](https://rpmfusion.org/Howto/Multimedia)
- [Fedora: tuned-ppd по умолчанию (F41 change)](https://discussion.fedoraproject.org/t/f41-change-proposal-make-tuned-the-default-power-profile-management-daemon-system-wide/118554)
- [Конфликт TLP и PPD/tuned-ppd](https://discussion.fedoraproject.org/t/43-to-44-upgrade-error-because-of-powerprofiles-service-tuned-ppd-tlp/190357)
- [Документация amd-pstate](https://docs.kernel.org/6.8/admin-guide/pm/amd-pstate.html), [active по умолчанию](https://lkml.rescloud.iu.edu/2306.2/04580.html)
- [s2idle на P14s Gen 2: #1738](https://gitlab.freedesktop.org/drm/amd/-/issues/1738), [#1800](https://gitlab.freedesktop.org/drm/amd/-/issues/1800), [quirk в ядре](https://phoronix.com/news/Linux-s2idle-More-AMD-Lenovo)
- [GNOME 48 Preserve Battery Health](https://community.frame.work/t/gnome-48-preserve-battery-health/67918)
- [Сканер отпечатков P14s Gen 2 AMD](https://bbs.archlinux.org/viewtopic.php?id=274278), [Arch Wiki T14s AMD](https://wiki.archLinux.org/title/Lenovo_ThinkPad_T14s_(AMD)_Gen_1)
- [Перенос Fedora 45](https://linuxiac.com/?p=221276)
- [Universal Blue image-template](https://universal-blue.org/)
- [bootupd: custom.cfg в статическом GRUB](https://github.com/coreos/bootupd/tree/main/src/grub2/configs.d), [пункт Windows на Fedora Atomic](https://discussion.fedoraproject.org/t/dual-boot-fedora-kinoite-windows-working-but-the-solution-feels-brittle/203065)
- [Ключ Secure Boot Universal Blue](https://docs.bazzite.gg/General/Installation_Guide/secure_boot/)
