# CleanLinux-Recipes

Рецепты пакетов для **CleanLinux** — базы для Linux-сборок, как Arch: система «с нуля» (не LFS), драйверы и оптимизация под железо для ПК, ноутбуков, портативных консолей и плат на **x86_64 и arm64**.

Это аналог AUR, но для всей системы: **здесь нет ни одного бинарника** — только ссылки на исходники upstream, их sha256 и инструкции сборки. Всё собирает пакетный менеджер `burn` прямо на машине пользователя под её процессор и видеокарту (профили `steam-deck`, `rog-ally`, `mangmi-air-x`, `raspberry-pi-5`, `native`, …).

*English summary [below](#english).*

## Принципы

- **Только база.** Здесь рецепты слоёв core, hardware и platform ([SCOPE.md](https://github.com/vovawees/CleanLinux/blob/main/docs/SCOPE.md)). DE, WM, приложения, Steam и всё «по вкусу» живут в репозиториях сборок — это оверлеи рецептов поверх этого репозитория.
- **Только ссылки + рецепты.** Исходники качаются по `https://` (или через зеркала `gnu://`, `kernel://`), у каждого есть sha256 — при несовпадении `burn` сборку не начнёт. CI отклоняет двоичные файлы и файлы больше 256 KiB.
- **Детерминированность.** Опциональные зависимости включаются только через *features* (аналог USE-флагов), а не «что случайно нашлось в системе». Для meson по умолчанию `--auto-features=disabled`.
- **Минимализм.** Без документации и лишних локалей (настраивается `KEEP_DOCS`, `LOCALES`), без `.la` и статических библиотек, если есть `.so`, бинарники стрипаются.
- **Совместимость.** glibc (не musl), merged `/usr` (`/bin`, `/lib`, `/lib64` → `/usr/...`), init — dinit. Программный стек (Wayland или X11, PipeWire, …) выбирает сборка через features.
- **Оптимизация под железо.** Флаги CPU (`-march`/`-mcpu`), LTO и hardening приходят из профиля устройства, рецепты их не трогают.

## Структура

```
packages/<имя>/recipe      рецепт (bash)
packages/<имя>/patches/    патчи (необязательно)
packages/<имя>/<файл>      мелкие локальные файлы: конфиги, фрагменты
tools/lint.sh              автономная проверка рецептов (её запускает CI)
tools/updates.sh           слежение за upstream: какие рецепты отстали (--write поднимает версии и sha256)
TEMPLATE.recipe            шаблон нового рецепта
```

## Формат рецепта

Рецепт — это bash-файл с переменными и (необязательно) функциями:

```bash
name=zstd
version=1.5.7
release=1
summary="Zstandard: fast real-time compression"
homepage=https://facebook.github.io/zstd/
license=(BSD-3-Clause GPL-2.0-only)
depends=(glibc zlib-ng:zlib xz:lzma lz4:lz4)   # pkg:feature — только при включённой feature
features=(+zlib +lzma +lz4)                    # +вкл / -выкл по умолчанию
build_type=meson
meson_subdir=build/meson
source=(https://github.com/facebook/zstd/releases/download/v$version/zstd-$version.tar.gz)
sha256=(eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3)
meson_args=(-Dbin_programs=true -Dmulti_thread=enabled)
meson_extra() { meson_feature zlib; meson_feature lzma; meson_feature lz4; }
```

| Переменная | Смысл |
|---|---|
| `name`, `version`, `release` | имя (= имя каталога), версия upstream, номер сборки рецепта |
| `summary`, `homepage`, `license` | описание |
| `category` | слой базы: `core` `devel` `meta` `kernel` `firmware` `drivers` `platform` (см. «Категории») |
| `depends`, `makedepends` | зависимости времени работы / только сборки; `pkg:feat`, `pkg:!feat` — условные |
| `features` | переключатели: `+feat` включена, `-feat` выключена по умолчанию |
| `build_type` | `autotools` `meson` `cmake` `make` `cargo` `python` `custom` `meta` |
| `source`, `sha256` | исходники (`[имя::]url` или локальный файл) и их хеши |
| `patches`, `patch_strip` | патчи и уровень `-p` (по умолчанию 1) |
| `configure_args`, `meson_args`, `cmake_args`, `make_args`, `make_install_args`, `cargo_args` | аргументы систем сборки |
| `out_of_tree`, `meson_subdir`, `cmake_subdir`, `srcdir` | раскладка исходников |
| `options` | `!lto` `!strip` `!hardening` `!prune` `!linker` (только GNU ld) `staticlibs` `emptydirs` `o3` (горячий код: -O3) |
| `backup` | конфиги, которые нельзя перезаписывать (новая версия ляжет как `.burnnew`) |
| `split` | дополнительные пакеты из той же сборки (`split=(gcc-libs)`); для каждого: `files_KEY` (пути и glob-шаблоны внутри `$DESTDIR`, обязательно), `summary_KEY`, `depends_KEY`, `backup_KEY`, `license_KEY`, где `KEY` — имя с `_` вместо `-` и `.` |

Функции (все необязательны, выполняются в каталоге исходников): `do_prepare`, `do_configure`, `do_build`, `do_check`, `do_install`, `post_install`, а также `configure_extra`/`meson_extra`/`cmake_extra` (печатают по аргументу в строке). Внутри доступны `$SRC $BUILD $DESTDIR $FILES $CC $CFLAGS $LDFLAGS $CHOST $CARCH $KARCH $CROSS $JOBS $VIDEO_CARDS`, помощники `use`, `use_enable`, `use_with`, `meson_feature`, `meson_use`, `cmake_use` и стандартные шаги `bt_configure`, `bt_build`, `bt_install`.

## Категории

Категория — это слой базы, к которому относится пакет ([SCOPE.md](https://github.com/vovawees/CleanLinux/blob/main/docs/SCOPE.md)):

| Категория | Слой | Что там |
|---|---|---|
| `core` | core | рантайм базовой системы: libc, init, утилиты и библиотеки, которые им нужны |
| `devel` | core | тулчейн и инструменты сборки (`base-devel`): CleanLinux собирает всё из исходников |
| `meta` | core | мета-пакеты (`base`, `base-devel`) |
| `kernel` | hardware | ядро и то, что собирается вместе с ним |
| `firmware` | hardware | firmware из upstream; на устройство ставится только нужное его профилю |
| `drivers` | hardware | драйверы и поддержка железа в userspace: Mesa, ALSA UCM, правила и quirks устройств |
| `platform` | platform | нейтральный фундамент для сборок: Wayland, libinput, seatd, D-Bus, PipeWire, … — в `base` не входит |

DE, WM, приложений и игр здесь нет: их рецепты живут в репозиториях сборок и личных оверлеях, с категорией `extra`.
`tools/lint.sh` не пропускает в этот репозиторий рецепты без категории слоя.

## Каналы (rolling release+++)

- `main` — основной канал: только рецепты, прошедшие CI (lint + проверка ссылок и sha256).
- `edge` — свежие версии сразу после выхода upstream: workflow `updates` каждый день запускает `tools/updates.sh --write`, проверяет новые ссылки и sha256 (`tools/lint.sh --fetch`), публикует результат в ветку `edge` и предлагает его в `main` через PR. Подписаться: `CHANNEL=edge` в `/etc/burn/burn.conf`.
- `security` *(план)* — только исправления безопасности поверх `main`.

`burn update` не обновляет вслепую: показывает план (что, зачем, риск `major`/`core`, changelog из git-истории рецептов), сначала **собирает всё**, затем делает снимок btrfs (сам burn, без btrfs-progs), применяет, сам пересобирает пакеты, чьи библиотеки сменили soname, и проверяет систему (`burn doctor`). Любой пакет можно откатить (`burn rollback`) и заморозить (`burn hold`).

## Как добавить пакет

```sh
mkdir packages/foo && cp TEMPLATE.recipe packages/foo/recipe   # заполнить
burn -R packages checksum --write foo    # настоящие sha256 из скачанных файлов
burn -R packages lint foo
burn -R packages build foo               # или: install
tools/lint.sh --fetch foo                 # то же, что проверяет CI
```

## Как обновить пакеты

```sh
tools/updates.sh -v                       # что отстало от upstream (GITHUB_TOKEN поднимает лимиты API)
tools/updates.sh --write foo bar          # новые версии, release=1, скачать исходники, новые sha256
tools/lint.sh --fetch foo bar
```

Upstream определяется по ссылкам самого рецепта, отдельные метаданные не нужны: листинги GNU и kernel.org (включая каталоги версий вроде `gcc-X/` и `util-linux/vX.Y/`), stable-ядро из `releases.json`, GitHub releases (теги как запасной вариант), любые https-каталоги, официальные патчи bash/readline (`_patches=({001..NNN})`).

## Пакеты

| Пакет | Категория | Версия | Сборка | Описание |
|---|---|---|---|---|
| `base-devel` | meta | 2026.1 | meta | Toolchain for building recipes natively (meta package) |
| `base` | meta | 2026.1 | meta | Minimal CleanLinux userland (meta package) |
| `bash` | core | 5.3.20 | autotools | GNU Bourne Again shell (with all upstream patches) |
| `binutils` | devel | 2.47 | autotools | GNU assembler, linker and binary utilities |
| `bison` | devel | 3.8.2 | autotools | GNU parser generator (yacc replacement) |
| `btrfs-progs` | core | 7.3 | autotools | btrfs filesystem tools: mkfs.btrfs, btrfs (subvolumes, snapshots, scrub, send), btrfsck |
| `burn` | core | 0.6.0 | make | The CleanLinux package manager: source based, rolling+++ |
| `coreutils` | core | 9.12 | autotools | GNU core utilities: ls, cp, mv, cat, ... |
| `dbus` | core | 1.16.2 | meson | D-Bus: the message bus daemon and libdbus |
| `dhcpcd` | core | 10.5.2 | custom | DHCP and DHCPv6 client: IPv4LL, SLAAC, privilege separation |
| `diffutils` | core | 3.12 | autotools | GNU diff, cmp, diff3 and sdiff |
| `dinit` | core | 0.22.1 | custom | dinit: fast, small service manager and init with dependency handling |
| `dosfstools` | core | 4.2 | autotools | FAT filesystem tools: mkfs.fat, fsck.fat, fatlabel (the EFI system partition) |
| `e2fsprogs` | core | 1.47.4 | autotools | ext2/3/4 filesystem tools: mke2fs, e2fsck, tune2fs, resize2fs, debugfs |
| `ell` | core | 0.83 | autotools | Embedded Linux Library: the D-Bus, netlink, crypto and TLS core of iwd |
| `eudev` | core | 3.3.0 | autotools | udev without systemd: device manager (udevd, udevadm), rules, hwdb and libudev |
| `expat` | core | 2.10.0 | autotools | Expat: stream-oriented XML parser library |
| `filesystem` | core | 2026.1 | custom | CleanLinux base layout: merged /usr, default /etc files, os-release |
| `findutils` | core | 4.11.0 | autotools | GNU find, xargs and locate |
| `gawk` | core | 5.4.1 | autotools | GNU awk |
| `gcc` | devel | 16.2.0 | autotools | GNU Compiler Collection: C and C++ compilers and their runtime libraries |
| `glibc` | core | 2.44 | autotools | GNU C library: libc, the dynamic loader and friends |
| `gperf` | devel | 3.3 | autotools | GNU perfect hash function generator (builds the keyword tables of eudev) |
| `grep` | core | 3.12 | autotools | GNU grep: search text with regular expressions |
| `gzip` | core | 1.15 | autotools | GNU gzip compression utility |
| `iproute2` | core | 7.3.0 | custom | IP routing utilities: ip, ss, bridge, tc |
| `iwd` | core | 3.12 | autotools | iwd: the wireless daemon (WPA2/WPA3, enterprise) and iwctl |
| `kmod` | core | 34.3 | meson | Kernel module tools and library: modprobe, depmod, lsmod, insmod, rmmod, modinfo |
| `libxcrypt` | core | 4.5.2 | autotools | Modern crypt(3): yescrypt, bcrypt and SHA-crypt password hashing (libcrypt) |
| `linux-headers` | core | 7.3.1 | custom | Linux kernel userspace API headers |
| `linux-pam` | core | 1.7.3 | meson | Linux-PAM: pluggable authentication modules (pam_unix, pam_limits, pam_env, ...) |
| `linux` | kernel | 7.3.1 | custom | The Linux kernel and modules (CleanLinux defaults + profile GPU drivers) |
| `lz4` | core | 1.10.0 | make | Extremely fast compression (library and lz4 tool) |
| `m4` | devel | 1.4.21 | autotools | GNU m4 macro processor |
| `make` | devel | 4.4.1 | autotools | GNU make |
| `ncurses` | core | 6.6 | autotools | Terminal handling library (wide character build) |
| `openresolv` | core | 3.17.4 | custom | resolvconf: /etc/resolv.conf from DHCP clients, VPNs and local resolvers |
| `pambase` | core | 2026.1 | custom | CleanLinux PAM stacks: system-auth, system-login, system-services, other |
| `patch` | devel | 2.8.1 | autotools | GNU patch: apply diff files |
| `pkgconf` | devel | 3.0.10 | meson | pkg-config implementation (also installed as pkg-config) |
| `readline` | core | 8.3.6 | autotools | GNU readline: line editing and history for interactive programs |
| `sed` | core | 4.10 | autotools | GNU stream editor |
| `shadow` | core | 4.20.3 | autotools | Password and account tools: passwd, useradd, usermod, groupadd, chage, newuidmap, ... |
| `systemd-boot` | core | 261.4 | meson | systemd-boot: the UEFI boot manager of systemd, built alone (no systemd) |
| `tar` | core | 1.35 | autotools | GNU tar archiver |
| `util-linux` | core | 2.42.4 | autotools | Core Linux system utilities: mount, fdisk, lsblk, agetty, kill, ... |
| `xz` | core | 5.8.4 | autotools | XZ Utils: LZMA/xz compression library and tools |
| `zlib-ng` | core | 2.3.3 | cmake | zlib replacement with SIMD optimisations (zlib-compatible API and ABI) |
| `zstd` | core | 1.5.7 | meson | Zstandard: fast real-time compression (library and zstd tool) |

## English

**CleanLinux-Recipes** is the package recipe repository of CleanLinux, a base for Linux spins like Arch: a from-scratch (not LFS) system, drivers and hardware tuning for PCs, laptops, handhelds and boards (x86_64 and arm64), built on glibc. It holds the base layers only (core, hardware, platform); desktops, applications and games belong to spin repositories, which are recipe overlays on top of this one. Like the AUR, but for the whole system: it contains **no binaries**, only upstream source links, their sha256 and build instructions. The `burn` package manager builds everything locally, tuned by a hardware profile (CPU flags, GPU drivers, features). Rules: https-only sources with mandatory checksums, no binary or vendored files, deterministic builds through explicit features, minimal output (no docs/extra locales/static libs by default). `tools/lint.sh` is the self-contained checker used by CI; `--fetch` also downloads the sources and verifies their checksums. `tools/updates.sh` watches upstream releases (inferred from the recipe sources: GNU/kernel.org listings, GitHub releases, bash/readline patch levels); the daily `updates` workflow bumps and verifies recipes, publishes them to the `edge` channel and proposes them to `main`.

License of the recipes: MIT (see `LICENSE`). Each package keeps its own upstream license (`license=` in the recipe).
