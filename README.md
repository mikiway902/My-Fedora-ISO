# My-Fedora-ISO

Два варианта системы для ThinkPad P14s Gen 2 AMD (Ryzen 7 PRO 5850U, Radeon Vega 8) с одинаковым набором программ, каждый в двух исполнениях:

- **атомарный** (bootc, обновляется готовым образом, откат через GRUB);
- **классический** (обычная Fedora: Anaconda ставит пакеты из репозиториев, дальше `dnf upgrade`).

Оба работают рядом с Windows. Атомарные собраны по шаблону [ublue-os/image-template](https://github.com/ublue-os/image-template), классические — netinstall ISO на базе Fedora Everything. Проверено по источникам 2026-10-29.

### Атомарные образы (bootc)

| Образ | Оболочка | Основа |
|---|---|---|
| `ghcr.io/mikiway902/my-fedora-iso-driftwm` | [driftwm](https://github.com/malbiruk/driftwm), вход через greetd + tuigreet | `ublue-os/base-main:44` (Fedora без DE) |
| `ghcr.io/mikiway902/my-fedora-iso-gnome` | GNOME, вход через GDM | `ublue-os/silverblue-main:44` (Silverblue) |

В обеих основах уже есть кодеки и полная Mesa из negativo17. Freeworld Mesa из RPM Fusion **не** ставится: она конфликтует с negativo17, а H.264/HEVC и так работают.

### Классические ISO (Anaconda + dnf)

| Артефакт | Оболочка | Что внутри |
|---|---|---|
| `classic-driftwm-iso` | driftwm, greetd + tuigreet | Fedora 44 + те же пакеты, что в атомарном driftwm |
| `classic-gnome-iso` | GNOME, GDM | Fedora Workstation 44 + те же пакеты |

В классических ISO кодеки и полная Mesa ставятся из RPM Fusion в `%post`: полный `ffmpeg` вместо `ffmpeg-free`, `mesa-va-drivers-freeworld` и `mesa-vulkan-drivers-freeworld`.

### Сравнение четырёх вариантов

| | Atomic GNOME | Atomic DriftWM | Classic GNOME | Classic DriftWM |
|---|---|---|---|---|
| Основа | Silverblue bootc | base-main bootc | Fedora Workstation | Fedora Everything |
| Установка | Anaconda + `bootc switch` | Anaconda + `bootc switch` | Anaconda, пакеты из репозиториев | Anaconda, пакеты из репозиториев |
| Обновление | `bootc upgrade` | `bootc upgrade` | `dnf5 upgrade --refresh` | `dnf5 upgrade --refresh` |
| Откат | `bootc rollback` / прошлый deployment в GRUB | так же | нет (обычная Fedora) | нет |
| Зависимость от GHCR | нужна при установке и обновлении | так же | нет | нет |
| Разметка | Anaconda, интерактивная | так же | Anaconda, интерактивная | так же |
| Домашняя папка | сохраняется при обновлении/откате | так же | сохраняется | сохраняется |

## Как устроено

| Файл | Что в нём |
|---|---|
| [Containerfile](Containerfile) | Атомарные образы: этапы `driftwm` и `gnome`, нужный выбирается через `--target`. Версия driftwm закреплена тегом и commit (`DRIFTWM_VERSION=v0.21.0`, `DRIFTWM_COMMIT=df3de27…`), при обновлении меняйте оба значения осознанно |
| [build_files/packages.sh](build_files/packages.sh) | Единые списки пакетов для атомарной и классической сборки: сессии, железо, программы, COPR и vendor RPM |
| [build_files/build.sh](build_files/build.sh) | Атомарная сборка: копирует `system_files`, ставит пакеты, opencode CLI и DeepSeek Harness |
| [build_files/generate-kickstarts.sh](build_files/generate-kickstarts.sh) | Генерирует `driftwm.ks` и `gnome.ks` для классического установщика из тех же списков пакетов |
| [build_files/classic-post.sh](build_files/classic-post.sh) | `%post` классической установки: RPM Fusion, COPR, vendor RPM, opencode CLI, DSH, `system_files` и сервисы |
| [build_files/build-classic-iso.sh](build_files/build-classic-iso.sh) | Скачивает Fedora Everything netinst и добавляет kickstart и payload через `mkksiso` |
| [system_files/etc/tuned/](system_files/etc/tuned) | Профили TuneD для P14s Gen 2 AMD и отображение PPD → TuneD: balanced, power saver, performance |
| [system_files/usr/bin/my-fedora-battery](system_files/usr/bin/my-fedora-battery) | Пороги заряда ThinkPad: `show`, `apply`, `set`, пресеты 75/80, 40/80, 95/100 |
| [system_files/usr/bin/thinkpad-diagnostics](system_files/usr/bin/thinkpad-diagnostics) | Диагностика CPU, батареи, температур, сна, Wi-Fi/BT и NVMe |
| [system_files/usr/bin/my-fedora-power-profile](system_files/usr/bin/my-fedora-power-profile) | Переключение профилей питания в DriftWM без GNOME |
| [build_files/tests/](build_files/tests), [build_files/validate.sh](build_files/validate.sh) | Локальные тесты и полная проверка исходников (`just test`, `just validate`) |
| [system_files/usr/share/my-fedora/](system_files/usr/share/my-fedora) | Списки `flatpaks`, `vscode-extensions`, пункт Windows для GRUB, конфиг DriftWM |
| [system_files/](system_files) | Копируется в `/`: greetd, профиль kanshi, сервис порогов заряда, уведомление о прошивках (всё это только для driftwm, в образе GNOME удаляется или не включается), репозиторий VS Code, сервисы установки, конфиг opencode |
| [disk_config/iso-driftwm.toml](disk_config/iso-driftwm.toml), [iso-gnome.toml](disk_config/iso-gnome.toml) | Установщик Anaconda для атомарных образов. Модуль Users включён: в driftwm нет мастера первого запуска, поэтому пользователя создаёт установщик. `%post` переключается на образ из GHCR с повторами и понятной ошибкой |
| [Justfile](Justfile) | Переменная `VARIANT` (`driftwm` по умолчанию или `gnome`) задаёт этап, имя образа и ISO. Отдельные цели: `build-atomic-*`, `build-classic-*`, `build-all`, `build-all-isos`, `test`, `validate`, `check-packages`, `sbom` |
| [.github/workflows/](.github/workflows) | `build.yml` (Atomic-образы), `build-disk.yml` (Atomic ISO), `build-classic.yml` (Classic ISO), `validate.yml` (проверки исходников) |

## Программы

| Программа | Откуда | Обновления |
|---|---|---|
| Firefox, Git, qBittorrent, mpv, Nautilus, File Roller + 7zip + unrar, grim/slurp/swappy (скриншоты) | Fedora | С образом |
| VS Code | Репозиторий Microsoft | С образом |
| Расширения VS Code: Claude Code и opencode (`sst-dev.opencode`) | Marketplace, при первом входе пользователя | Сами, через VS Code |
| `docker` / `docker compose` (поверх rootless Podman) | Fedora: `podman-docker`, `podman-compose` | С образом |
| PdfCraft, Happ | GitHub Releases, версия и SHA256 закреплены в `packages.sh` | С образом |
| opencode CLI (`opencode`) | GitHub Releases, версия и SHA256 закреплены в `packages.sh` | С образом |
| DeepSeek Harness (`dsh`, web UI) | npm, версия закреплена в `packages.sh` | С образом |
| Discord, Telegram, Moonlight, OnlyOffice, Podman Desktop, Bazaar (магазин Flatpak), Flatseal (права Flatpak) | Flathub, при первой загрузке | Сами, таймер Flatpak |
| Extension Manager (только GNOME) | Flathub, при первой загрузке | Сам, таймер Flatpak |
| Расширения GNOME: AppIndicator (значки в трее), Dash to Dock, Caffeine (не засыпать); GNOME Tweaks | Fedora, включены сразу | С образом |
| Шрифт JetBrains Mono (по умолчанию в VS Code, терминале foot и моноширинным в GNOME), русский словарь hunspell | Fedora | С образом |

Программу из списков `flatpaks` или `vscode-extensions` можно добавить в любой момент: после обновления системы она установится сама. Если пользователь удалил программу, обратно она не ставится.

opencode ставится как терминальная программа (не desktop) и уже настроен без запросов разрешений: новый пользователь получает `~/.config/opencode/opencode.json` из `system_files/etc/skel`. DeepSeek Harness запускается командой `dsh`. Версии сторонних программ и их SHA256 лежат в [build_files/packages.sh](build_files/packages.sh); при обновлении меняйте версию и хеш вместе, сборка не установит непроверенный файл.

Атомарные образы пересобираются каждый день в 06:05 по Москве, при каждом push и вручную (Actions → Run workflow). GitHub отключает расписание, если в репо 60 дней не было коммитов. Тогда его нужно включить заново на вкладке Actions. Классические ISO собираются вручную через workflow **Build classic ISO**.

## Сборка

### Через GitHub (рекомендую)

1. Запушьте репо на GitHub как `mikiway902/My-Fedora-ISO`. Если имя другое, поправьте `REPO_ORGANIZATION` в [image-template.env](image-template.env) и адреса в `disk_config/iso-*.toml`.
2. Создайте ключ подписи для контейнерных образов, без него `build.yml` падает на шаге подписи:
   ```bash
   COSIGN_PASSWORD="" cosign generate-key-pair
   ```
   ```bash
   gh secret set SIGNING_SECRET < cosign.key
   ```
   Закоммитьте `cosign.pub`. `cosign.key` не коммитьте никогда, он уже в `.gitignore`.
3. Push в `main` запускает `build.yml`, и он собирает оба атомарных образа параллельно. Сделайте оба пакета публичными в настройках GHCR.
4. ISO: Actions → **Build disk images** (атомарные) или **Build classic ISO** (классические) → Run workflow → выберите `gnome`, `driftwm` или `both`. Подробности — [Download prebuilt ISO](#download-prebuilt-iso). Для сборки ISO секреты не нужны; для классических не нужен и ключ cosign из шага 2.

### Что запускает CI

| Событие | Workflow | Результат |
|---|---|---|
| push в `main` / pull request | **Validate** | Justfile, shellcheck, bash -n, actionlint, kickstart (`ksvalidator`), systemd units, hadolint, TOML, unit-тесты; отдельная job проверяет имена пакетов в Fedora 44 |
| push в `main`, ежедневно 06:05 MSK, вручную, тег `v*` | **Build container image** | Atomic-образы `gnome`/`driftwm` в GHCR, SBOM и build metadata |
| вручную, тег `v*` | **Build disk images** | Atomic ISO + `SHA256SUMS.txt` + `build-info.txt` |
| вручную, еженедельно, тег `v*` | **Build classic ISO** | Classic ISO + `SHA256SUMS.txt` + `build-info.txt` + kickstart + список пакетов |

Тег `v*` дополнительно публикует Atomic-образы под этим тегом. `latest` обновляется только после успешной сборки; упавшая сборка не перезаписывает его. Артефакты ISO/SBOM хранятся 14 дней.


### Локально (Linux с podman и just)

```bash
# атомарные образы и их ISO
VARIANT=gnome just build && VARIANT=gnome just build-iso

# классический netinstall ISO (нужен rootful podman для mkksiso)
VARIANT=gnome just build-classic-iso

# или отдельные цели без ручного VARIANT
just build-atomic-gnome
just build-atomic-driftwm
just build-classic-gnome
just build-classic-driftwm
just build-all          # Atomic-образы + Classic ISO для обоих рабочих столов
just build-all-isos     # все четыре загрузочных ISO
```

Без `VARIANT` собирается driftwm. Атомарный ISO будет в `output/bootiso/install.iso`, классический — в `output/bootiso/my-fedora-classic-<variant>.iso`. Проверить в VM: `just run-vm-iso` или `just run-vm-classic-iso`.

Проверки исходников (без сборки образов):

```bash
just check           # синтаксис Justfile
just test            # локальные unit-тесты: батарея, kickstart, пакеты, диагностика
just validate        # shellcheck, bash -n, actionlint, ksvalidator, systemd-analyze, hadolint, TOML
just check-packages  # имена пакетов в Fedora 44 (в контейнере)
just sbom            # SPDX-инвентарь уже собранного образа
```

### Обновления после установки

- **Атомарные образы:** система тянет новые сборки из GHCR сама (`bootc upgrade`). Поменяли `build.sh`, сделали push, перезагрузились, и изменения на месте. Откат: `sudo bootc rollback`.

  ```bash
  sudo bootc status            # текущий и предыдущий deployment, образ, digest
  sudo bootc upgrade           # скачать и подготовить новую сборку
  sudo bootc rollback          # вернуться на предыдущий deployment
  ```

  bootc/ostree сам создаёт загрузочные записи для текущего и предыдущего deployment; предыдущая рабочая версия не удаляется при обычном обновлении. Выбрать её можно и в меню GRUB при загрузке. Вручную GRUB и `custom.cfg` для этого не редактируются: сервис `grub-windows-entry` добавляет только пункт Windows, не трогая записи bootc. Наличие нескольких пунктов GRUB само по себе не гарантирует откат — проверяйте `bootc status` после обновления.
- **Классические:** обычное `sudo dnf5 upgrade --refresh` (в Fedora 44 это штатный менеджер; `dnf` — совместимая команда). Образ с GHCR не связан, отката к прошлому образу нет; для отката пакетов используйте историю dnf и снапшоты btrfs, если настроили их сами.
- **Atomic ISO и `latest`:** ISO при установке выполняет `bootc switch` на `ghcr.io/mikiway902/my-fedora-iso-<variant>:latest`, поэтому ставится последняя опубликованная сборка, а не обязательно та, что была в момент сборки ISO. Без сети/GHCR установка Atomic ISO завершится понятной ошибкой; Classic ISO от GHCR не зависит.

## Download prebuilt ISO

Готовый загрузочный ISO можно скачать с GitHub, ничего не собирая на своём компьютере. Нужен только браузер.

1. Откройте репозиторий на GitHub и вкладку **Actions**.
2. В списке слева выберите workflow:
   - **Build disk images** — атомарные образы;
   - **Build classic ISO** — классические netinstall ISO.
3. Справа нажмите **Run workflow**.
4. В поле **variant** выберите `gnome`, `driftwm` или `both` и нажмите зелёную **Run workflow**.
5. Дождитесь зелёной галочки у запуска (обычно 30–60 минут). Варианты собираются независимо: если один упал, ISO второго всё равно загрузится.
6. Внизу страницы запуска, в разделе **Artifacts**, скачайте нужный архив:

   | Workflow | Артефакт | Файл внутри |
   |---|---|---|
   | Build disk images | `gnome-anaconda-iso` | `my-fedora-iso-gnome.iso` |
   | Build disk images | `driftwm-anaconda-iso` | `my-fedora-iso-driftwm.iso` |
   | Build classic ISO | `classic-gnome-iso` | `my-fedora-classic-gnome.iso` |
   | Build classic ISO | `classic-driftwm-iso` | `my-fedora-classic-driftwm.iso` |

   В Classic-архиве рядом с ISO лежат `SHA256SUMS.txt`, `build-info.txt`, `<variant>.ks` и `packages.sh` (точный kickstart и списки пакетов). Для Atomic-образов отдельными артефактами публикуются `atomic-<variant>-sbom` (SPDX) и `atomic-<variant>-metadata`.
7. Артефакты хранятся **14 дней**, потом GitHub их удаляет. Скачайте ISO сразу; иначе запустите workflow заново.

Оба варианта — установщик Anaconda: загрузитесь с флешки и установите систему. Атомарный ISO после установки обновляется из GHCR через `bootc upgrade`; классический — обычными `dnf upgrade` из репозиториев Fedora.

### Запись на флешку

Нужна флешка на 8 ГБ или больше. Всё её содержимое будет стёрто.

- **Rufus (Windows).** Выберите флешку в поле «Устройство», нажмите «Выбрать» и укажите `.iso`. Схема раздела GPT, целевая система UEFI. Нажмите «Старт». Если Rufus предложит режим ISO или DD, выбирайте **DD**.
- **balenaEtcher (Windows, Linux, macOS).** «Flash from file» → выберите ISO → «Select target» → флешка → «Flash!».

После записи загрузитесь с флешки: F12 на логотипе Lenovo → USB.

### Проверка SHA256

Сравните хеш скачанного ISO со строкой в `SHA256SUMS.txt`.

Windows (PowerShell):

```powershell
Get-FileHash .\my-fedora-iso-gnome.iso -Algorithm SHA256
```

Linux/macOS:

```bash
sha256sum -c SHA256SUMS.txt
```

На macOS вместо `sha256sum` используйте `shasum -a 256 -c SHA256SUMS.txt`. Если хеши не совпали, файл скачался с ошибкой — скачайте артефакт заново.

## Переключение driftwm ⇄ GNOME

Этот раздел — только для **атомарных** образов: там оболочка меняется готовым образом. В классической системе переключение означает переустановку (или ручную установку нужных пакетов и смену display manager).

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
3. **Только для атомарных образов:** зарегистрируйте ключ Universal Blue, иначе модули ядра из образа не загрузятся при Secure Boot:
   ```bash
   ujust enroll-secure-boot-key
   ```
   При перезагрузке появится синий экран MokManager: Enroll MOK → Continue → пароль `universalblue`. В классической Fedora этот шаг не нужен: ядро и модули подписаны ключом Fedora.

### Вариант Б: сначала Fedora, потом Windows

Установщик Windows не стирает загрузчик Fedora: он находит существующий EFI-раздел и кладёт свой загрузчик рядом. Но он ставит себя первым в порядке загрузки, и это нужно один раз исправить.

1. **Fedora.** Secure Boot включён, флешка через F12. В Anaconda выберите ручную разметку, а не «весь диск». Оставьте 100–150 ГБ **неразмеченными** под Windows. Разделы Fedora:
   - `/boot/efi`: 600 МБ, EFI;
   - `/boot`: 2 ГБ, ext4;
   - остальное под btrfs с шифрованием (LUKS).

   После установки зарегистрируйте ключ, как в варианте А: `ujust enroll-secure-boot-key` (только для атомарного образа; в классической Fedora не нужно).
2. **Windows.** Флешка через F12 → «Выборочная установка» → выберите **неразмеченное пространство** → «Далее». Сами разделы не создавайте и ничего не удаляйте: служебные разделы Windows создаст сама.
3. **В Windows** сделайте то же, что в варианте А: сохраните ключ BitLocker (Windows 11 на ноутбуках часто включает шифрование сама), отключите быстрый запуск, переведите часы на UTC.
4. **Верните Fedora первой в загрузке.** Два способа:
   - BIOS: F1 на логотипе → Startup → Boot, поднимите Fedora выше Windows Boot Manager;
   - или загрузитесь в Fedora через F12 и выполните `sudo efibootmgr`. Команда покажет номера пунктов. Затем `sudo efibootmgr -o <номер Fedora>,<номер Windows>`.
5. Пункт «Windows» появится в GRUB сам, с ближайшей загрузки Fedora.

### Выбор системы при включении
- В GRUB есть пункты Fedora и «Windows». В Atomic пункт Windows добавляет сервис `grub-windows-entry` при первой загрузке (появится со второй перезагрузки); в Classic тот же пункт добавляется в `/etc/grub.d/40_custom` и применяется через `grub2-mkconfig` при установке. Если вы сами создали `/boot/grub2/custom.cfg` в Atomic, сервис его не трогает. В Classic ручной `/etc/grub.d/40_custom` тоже не перезаписывается после установки.
- Запасной путь, который работает всегда: F12 на логотипе Lenovo → Windows Boot Manager или Fedora.
- Если после обновления Windows ноутбук грузится сразу в Windows, верните Fedora первой в BIOS (F1 → Startup → Boot) или выберите её через F12.

## Питание, сон и ThinkPad P14s Gen 2 AMD

### Профили питания

В обеих редакциях установлен только `tuned-ppd`. TLP, auto-cpufreq и второй `power-profiles-daemon` не ставятся: они конфликтуют с TuneD. Профили PPD отображаются на профили TuneD из [system_files/etc/tuned/](system_files/etc/tuned):

- **Balanced** — штатный `balanced`: schedutil, EPP `balance_performance`, Boost включён;
- **Power Saver** — EPP `power`, low-power ACPI, панель экономичнее; Boost **не** отключается, Wi-Fi powersave и USB autosuspend принудительно не включаются;
- **Performance** — штатный `throughput-performance`: EPP `performance`, максимальная штатная производительность.

В GNOME профиль меняется в Настройки → Питание. В DriftWM — `Super+Shift+P` (меню fuzzel) или:

```bash
my-fedora-power-profile get
my-fedora-power-profile set power-saver|balanced|performance
my-fedora-power-profile next
```

Никакие параметры ядра (`amd_pstate=active`, `iommu=pt`, отключение USB и т. п.) не добавляются. `thinkpad-diagnostics` показывает фактический драйвер cpufreq, режим AMD P-State, governor и EPP.

### Пороги заряда

В DriftWM сервис `my-fedora-battery.service` применяет пороги при загрузке и после выхода из сна. Значения хранятся в `/etc/my-fedora/battery.conf` и меняются без пересборки:

```bash
my-fedora-battery show                     # что настроено и что реально в sysfs
sudo my-fedora-battery profile main        # 75/80, повседневный режим
sudo my-fedora-battery profile longevity   # 40/80, долго от сети
sudo my-fedora-battery profile travel      # 95/100, полный заряд перед поездкой
sudo my-fedora-battery set --start 60 --end 85
```

Скрипт проверяет диапазон (`0 ≤ start < end ≤ 100`), не пишет в sysfs без прав и не падает, если прошивка не отдаёт `charge_control_*_threshold`: система загружается и работает как обычно. В GNOME порогом управляет штатный UPower (Настройки → Питание → Preserve Battery Health); не включайте одновременно наш сервис и настройку GNOME, они пишут одно и то же значение.

### Сон и крышка

- В DriftWM закрытая крышка на питании от сети не усыпляет ноутбук ([50-lid-ac.conf](system_files/usr/lib/systemd/logind.conf.d/50-lid-ac.conf)), от батареи — усыпляет; с внешним монитором logind игнорирует крышку.
- В GNOME на AC автоматический сон отключён, от батареи остаётся штатное поведение GNOME.
- Используется `s2idle`/S0ix, который поддерживает эта модель; старые обходные пути (S3, `iommu=pt`, отключение USB) не добавляются.
- Перед сном экран блокируется. После пробуждения проверьте Wi-Fi, Bluetooth, NVMe, камеру, USB и расход батареи — готового автоматического теста нет, процедура описана в разделе [Проверка на ноутбуке](#проверка-на-ноутбуке).

### Wi-Fi, Bluetooth, USB и NVMe

Модель адаптера определяется по PCI/USB ID в `thinkpad-diagnostics`. Энергосбережение Wi-Fi и USB autosuspend по умолчанию не форсируются: на разных ревизиях P14s Gen 2 стоят разные адаптеры, а агрессивный autosuspend — частая причина отваливающейся мыши и Wi-Fi. Если после теста всё стабильно, включите вручную:

```bash
sudo iw dev wlan0 set power_save on
```

NVMe и вентилятор не трогаем: APST и thermal protection остаются штатными. Диагностика показывает температуры CPU/NVMe и состояние SMART (SMART — под root).

### Прошивки

BIOS/EC и прошивка сканера обновляются через `fwupd`/LVFS вручную:

```bash
fwupdmgr refresh
fwupdmgr get-updates
sudo fwupdmgr update
```

Автоматически прошивки не устанавливаются. В DriftWM раз в день приходит уведомление, если обновление доступно.

### Диагностика

```bash
thinkpad-diagnostics
thinkpad-diagnostics --report ~/thinkpad-report.txt
sudo thinkpad-diagnostics --report /var/tmp/thinkpad-report.txt   # + SMART
```

Скрипт только читает файлы и не меняет настройки. Он показывает CPU (модель, частоты, драйвер, AMD P-State, EPP), профиль питания, яркость экрана и подсветку клавиатуры, батарею (design/full capacity, циклы, пороги), температуры hwmon, режимы сна и статистику, Wi-Fi/BT/rfkill, NVMe/SMART, btrfs и `bootc status`. Отсутствующие датчики и утилиты не считаются ошибкой.

### Автономность: как измерять

Готовых «процентов экономии» проект не обещает. Чтобы сравнить режимы, используйте одинаковый сценарий:

1. Зарядите батарею до одного уровня (например, 80 %) и дайте 10 минут стабилизации.
2. Выполните `thinkpad-diagnostics --report` и запишите `energy_now`/`power_now` из `/sys/class/power_supply/BAT0/`, яркость и профиль.
3. Одинаковое время (например, 30 минут) работайте в одном и том же наборе приложений: Balanced, Power Saver, затем Performance от сети.
4. Сравнивайте не только расход, но и температуры/частоты и субъективную отзывчивость; для ноутбука важнее стабильность сна и Wi-Fi, чем минимальный ватт.
5. Для сна измерьте `energy_now` до и после 30–60 минут s2idle и пересчитайте расход в ваттах.

## После первой загрузки

- **Пользователь (классические ISO).** В kickstart root заблокирован, поэтому при первой загрузке запускается `initial-setup` (в GNOME — `gnome-initial-setup`) и просит создать пользователя. Это сделано специально: установщик не навязывает логин и пароль. Отметьте «Make this user administrator» (добавление в `wheel`), иначе не будет `sudo`.
- **Отпечаток.** Вход, sudo и запросы прав по отпечатку уже включены в обоих образах. Осталось записать палец: `fprintd-enroll`, а в GNOME через Настройки → Пользователи. Пока отпечаток не записан, работает обычный пароль.
- **Лимит заряда 80 %.** В driftwm он включён сразу: зарядка до 80 %, дозарядка ниже 75 %, сервис применяет значения при загрузке и после сна. Меняется без пересборки: `sudo my-fedora-battery profile travel` (95/100), `longevity` (40/80), `main` (75/80) или `sudo my-fedora-battery set --start 60 --end 85`. В GNOME: Настройки → Питание → «Preserve Battery Health». Не используйте оба механизма одновременно.
- **Сон на зарядке.** В обоих образах ноутбук на зарядке не засыпает от простоя, а от батареи засыпает. В GNOME это значение по умолчанию: его можно поменять в Настройки → Питание, и ваш выбор сохранится. Закрытие крышки: в driftwm на зарядке ноутбук не засыпает, от батареи засыпает. С внешним монитором крышка не усыпляет никогда. В GNOME крышка, как и раньше, усыпляет всегда, кроме случая с внешним монитором.
- **Орфография на русском** работает в Firefox и GTK-программах. VS Code системный словарь не использует, ему нужно расширение Code Spell Checker со словарём Russian. У Flatpak-программ (OnlyOffice, Telegram) свои словари, системный им не виден. В OnlyOffice русский словарь уже встроен.
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
| 5 / 5,5 / 15 минут простоя | Блокировка / выключение экрана / сон. Сон только от батареи, на зарядке ноутбук не засыпает. Перед сном экран блокируется всегда |
| Вечер | Тёплые цвета экрана (wlsunset) |
| Обои | Статичный шейдер `dark_sea`. Другие лежат в `~/.config/driftwm/wallpapers/`, меняются в `[background]` конфига. Анимированные (`animated/`) расходуют батарею |
| Раз в день | Уведомление, если для BIOS, EC или сканера есть новая прошивка |

Кроме того, в образе driftwm есть печать (CUPS и «Настройки принтера»), а в обоих образах — шрифты, совместимые с Times New Roman, Arial, Calibri и Cambria. С ними документы MS Office в OnlyOffice не разъезжаются.

## Без своего образа

Если driftwm не нужен, ставьте **Fedora Workstation** и запустите [setup.sh](setup.sh). Другой вариант: **Bluefin** или **Aurora**, им скрипт не нужен.

Fedora 45 перенесли с 20 октября на 27 октября (возможно, на 3 ноября). Если 45 ещё не вышла, ставьте 44 и обновитесь позже. Rawhide не берите.

## Что исправлено в исходной шпаргалке

| Было | На самом деле |
|---|---|
| `power-profiles-daemon` стоит по умолчанию | С Fedora 41 по умолчанию стоит **`tuned-ppd`**. Он даёт тот же D-Bus интерфейс и переключатель в GNOME; CLI `powerprofilesctl` относится к пакету `power-profiles-daemon`, поэтому в DriftWM профиль меняется через `my-fedora-power-profile` (busctl). Менять `tuned-ppd` не обязательно. Если хотите вернуть PPD: `sudo dnf swap tuned-ppd power-profiles-daemon` (тогда профили TuneD из этого проекта не используются) |
| `amd_pstate` active [Вероятно] | [Точно] Cezanne поддерживает CPPC через MSR. С ядра 6.5 режим `active` включён по умолчанию. Если в `status` пусто, значит ядро откатилось на `acpi-cpufreq`. Тогда проверьте, включён ли CPPC в BIOS |
| freeworld Mesa: «команды из скрипта» | Сейчас пакет ставится напрямую, `swap` для VA больше не нужен. Команды есть в `setup.sh` |
| btrfs + снапшоты | btrfs стоит в Fedora по умолчанию. Снапшотов из коробки **нет**, их нужно настроить: snapper или btrfs-assistant. LUKS включается галочкой в Anaconda |
| Лимит заряда через `tmpfiles` | В GNOME 48+ есть встроенная опция: Настройки → Питание → «Preserve Battery Health» (75–80 %), через UPower и `thinkpad_acpi`. Ручной `tmpfiles` спорил бы с ней. В этом проекте для DriftWM вместо tmpfiles используется `my-fedora-battery.service` + CLI, а в GNOME остаётся штатная настройка. Используйте только одно |
| `fprintd` [Догадка] | На P14s Gen 2 AMD стоит Synaptics Prometheus (`06cb:00bd`). libfprint его поддерживает, fprintd в Workstation уже установлен. Прошивку сканера обновляет fwupd |
| Сон: «s2idle, смотрите BIOS» [Догадка] | Подтверждено: у этой модели были баги входа и выхода из s0ix (drm/amd #1738, #1800). В ядро добавлен quirk для P14s Gen 2. Нужны свежие BIOS и ядро. При проблемах запустите `amd_s2idle.py` от AMD |
| 5–8 Вт в простое | Источник не найден, оставляю как [Догадка] |

Остальное подтверждено: TLP или auto-cpufreq рядом с PPD или tuned-ppd ставить нельзя, systemd-юниты конфликтуют. `thermald` нужен только для Intel. Прошивки приходят через LVFS.

## Проверка на ноутбуке

Для любого варианта:

```bash
thinkpad-diagnostics --report ~/thinkpad-report.txt
my-fedora-power-profile get                       # active tuned-ppd profile
cat /sys/devices/system/cpu/amd_pstate/status     # active
vainfo | grep -E 'H264|HEVC'                      # декодирование есть
cat /sys/power/mem_sleep                          # [s2idle]
lsusb | grep -i 06cb                              # сканер отпечатков
my-fedora-battery show                            # пороги и состояние батареи
```

Вручную: сон и пробуждение (крышка, 10+ минут), Wi-Fi, Bluetooth, звук, TrackPoint, жесты тачпада в driftwm. Для SMART и части прошивочных данных запускайте диагностику через `sudo`. Полный отчёт приложите к issue, если что-то не работает.

## Ограничения и что не проверено

- **Физическое железо.** В рамках этой доработки проверены сборка Atomic-образов, `bootc container lint` (проходит; остаются предупреждения от пакетов greetd/blueman/fprintd о содержимом `/var`), диагностика и unit-тесты. Сон/пробуждение, Wi-Fi и Bluetooth после сна, сканер отпечатков, пороги заряда на конкретной прошивке и автономность нужно проверить на самом P14s Gen 2 AMD.
- **Classic ISO.** Локально полная сборка не выполнялась: `mkksiso` → `mkefiboot` требует rootful podman. Kickstart проходит `ksvalidator`, пакеты разрешаются, но установку в VM/на железо ещё нужно прогнать через GitHub Actions и вручную.
- **Atomic ISO.** Для сборки нужен `bootc-image-builder` с rootful podman; локально не запускался. Установка Atomic ISO требует сети и доступа к GHCR.
- **Откат Atomic.** Механизм bootc/ostree не менялся; команды и поведение GRUB описаны выше, но реальный цикл «обновление → откат» на железе не прогонялся.
- **SBOM.** Публикуется инвентарь пакетов SPDX из RPM-базы образа. Сканирование уязвимостей (grype/trivy) в CI не включено: нужен проверенный источник БД; при необходимости запускайте его отдельно по SBOM.
- **Питание.** Wi-Fi powersave и USB autosuspend намеренно не включаются автоматически. TuneD-профили не меняют лимиты вентилятора и thermal protection. Пороги заряда в GNOME и DriftWM — два разных механизма, одновременно их использовать не нужно.
- **Secure Boot.** Не отключается и не переподписывается. Для Atomic по-прежнему нужен `ujust enroll-secure-boot-key`; Classic использует подписанное ядро Fedora.
- **Dual Boot.** Разметка остаётся интерактивной; EFI-раздел и Windows не трогаются автоматически. Проверка на реальном Dual Boot — в списке ручных тестов.

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
