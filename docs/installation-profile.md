# Переносимый профиль Fedora 45 — 2026-11-17

Исходная система: Fedora 45 Workstation, GNOME Shell 51, x86_64.
Это **сетевой установщик**, а не побайтовый клон ноутбука.
Fedora, Chrome, ChatGPT и Flathub устанавливают доступные в день установки
версии; закреплённые vendor bundles/CLI используют версии и SHA256 из репозитория.
Настройка мониторов, драйверов и энергопотребления зависит от нового оборудования.

## Два GNOME ISO

| Профиль | Назначение | Файл после успешной сборки |
|---|---|---|
| `generic` | Ноутбук ThinkPad P14s Gen 2 AMD | `output/bootiso/my-fedora-classic-gnome.iso` |
| `desktop-nvidia` | Ryzen 9600X, RTX 4060 8 GB, 32 GB RAM | `output/bootiso/my-fedora-classic-gnome-desktop-nvidia.iso` |

Оба используют обычную Fedora Workstation, Anaconda и dnf5. Разметка остаётся
интерактивной: автоматических `clearpart`, `autopart`, пароля или пользователя нет.
Пользователь создаётся через GNOME Initial Setup; новые пользователи получают
настройки из `/etc/skel`, а GNOME — defaults из dconf.

Desktop-профиль не применяет профили TuneD P14s, пороги заряда, конфигурацию
мониторов ноутбука, его идентификаторы дисков или настройки Windows.
CPU/RAM не требуют особой редакции Fedora. EXPO/6400 MT/s настраивается
в UEFI вручную: стабильность памяти образ гарантировать не может.

## Что перенесено

- Программы Fedora из `build_files/packages.sh`, GNOME, VS Code и два расширения
  VS Code; Node.js 22, Podman/Compose, GCC/GDB, Java, Python, RE-инструменты.
- Chrome, ChatGPT, Tailscale, Sunshine, Happ; устанавливаются начисто.
- OpenCode 2.3.0, универсальные lead/coder/hard/reviewer и `/dev`, `/review`,
  публичные MCP REA/Context7, без авторизации и истории.
- Python dev-tools из обнаруженного пользовательского Python 3.14, устанавливаемые
  в отдельное venv; список версий — `python-requirements.txt`. Это не копия venv.
- Flathub: AnyDesk, Discord, Telegram, Moonlight, Podman Desktop, Bazaar,
  Flatseal, Extension Manager.
- ArtCraft Launcher 0.19.2, CADCraft 0.20.1, DeckCraft 0.18.1,
  GridCraft 0.19.1, PDFCraft 0.21.1, WordCraft 0.18.1, SolidCraft 0.42.0.
  Их bundle-файлы загружаются при первой загрузке и проверяются по SHA256.
- Русская локаль, раскладки US/RU, выбранные UI-настройки GNOME и совместимые
  пользовательские расширения. Точный список и хеши:
  [desktop-snapshot.json](desktop-snapshot.json).

Flatpak-приложения появляются не мгновенно: дождитесь завершения
`flatpak-preinstall.service` и проверьте `systemctl status flatpak-preinstall`.

## Что не переносится

Домашний каталог целиком, Git-репозитории/рабочие данные, контейнеры и тома,
виртуальные машины, файлы Documents/Downloads, браузерные профили и cookies,
почта, контакты, Wi-Fi/VPN/прокси-профили, ключи SSH/GPG, keyring, пароли,
OpenCode DB, API/OAuth-токены, облачная авторизация, clipboard/history/cache,
Sunshine pairing, Tailscale machine identity, список серверов Happ.

Не копируются абсолютные пути, `.gitconfig` с именем/почтой, `monitors.xml`,
личные GTK bookmarks, custom launcher-команды, геолокация погоды.
OpenCode skills и специализированные project-level настройки остаются в
исходных проектах и не публикуются как универсальный профиль.

ResourceBuzzLite не заявляет GNOME 51: его принудительное включение и
глобальное отключение проверки совместимости не переносятся.
OnlyOffice, старый PDFCraft RPM, DeepSeek Harness и OmniRoute больше не входят
в набор: они не соответствуют текущему активному составу программ.

## Сборка

Повторный снимок разрешённых настроек (выполнять **обычным пользователем**):

```bash
python3 build_files/capture-desktop.py
bash build_files/tests/run-tests.sh
```

Для полноценного UEFI ISO `mkksiso` нужны rootful Podman и loop devices.
Не используйте `--skip-mkefiboot`: такой результат не равнозначен проверенному
USB-установщику UEFI.

На Fedora установите недостающие инструменты сборки, если их ещё нет:

```bash
sudo dnf5 install podman xorriso
```

Сборка без `just` (текущие scripts используют rootful контейнер только для remaster):

```bash
VARIANT=gnome HARDWARE_PROFILE=generic bash build_files/build-classic-iso.sh
VARIANT=gnome HARDWARE_PROFILE=desktop-nvidia bash build_files/build-classic-iso.sh
```

Обе команды потребуют `sudo` для контейнера. Они не устанавливают систему
на диск, не записывают флешку, не изменяют разметку и не запускают установщик.

После сборки:

```bash
sha256sum output/bootiso/my-fedora-classic-gnome*.iso
```

Альтернатива: GitHub Actions → **Build classic ISO**, `variant=gnome`,
`hardware_profile=generic` или `desktop-nvidia`.
Изменения сначала должны попасть в GitHub; локальная подготовка не означает
публикацию образов. Автоматические commit/push не выполняются.

## RTX 4060 и Secure Boot

Desktop-профиль устанавливает akmod NVIDIA из RPM Fusion, генерирует новый
локальный ключ подписи, строит модули для установленных ядер и проверяет их
наличие/подпись до пересборки initramfs. Ошибка драйвера завершает установку
профиля ошибкой, а не выдаётся за успешную установку.

Secure Boot не отключается, ключ ноутбука в ISO не включается.
Если Secure Boot включён, после установки зарегистрируйте **новый ключ ПК**:

```bash
sudo mokutil --sb-state
sudo mokutil --import /etc/pki/akmods/certs/public_key.der
```

Задайте временный пароль, перезагрузитесь и подтвердите Enroll MOK в
MOK Manager, затем перезагрузитесь снова. Если GUI пока не работает,
используйте текстовую консоль Ctrl+Alt+F3.

```bash
mokutil --test-key /etc/pki/akmods/certs/public_key.der
nvidia-smi
```

Те же инструкции устанавливаются в `/usr/share/my-fedora/NVIDIA-SECURE-BOOT.txt`.
При выключенном Secure Boot регистрация MOK обычно не требуется.
Не включайте Secure Boot повторно, пока ключ не зарегистрирован.

## Приёмка на новом устройстве

1. Проверить ISO/SHA256, загрузить через UEFI сначала в VM с пустым диском.
2. Проверить интерактивную разметку и создание нового пользователя.
3. Проверить `/var/log/my-fedora-install/{failures,warnings}.log`.
4. Дождаться Flatpak; проверить приложения, GNOME extensions и их preferences.
5. Авторизовать браузеры/ChatGPT/OpenCode, Happ/Tailscale и Sunshine заново.
6. На ПК проверить `nvidia-smi`, Wayland, аппаратное декодирование, suspend,
   звук и сеть. На другом GPU это не заменяет реальный hardware-тест.

Сборка/структурная проверка ISO не является доказательством успешной установки
в VM или работоспособности драйвера на физической RTX 4060.
