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
| `alsa-lib` | drivers | 1.2.16.1 | autotools | ALSA library: the userspace sound API of Linux (PCM, mixer, UCM, plugins) |
| `alsa-ucm-conf` | drivers | 1.2.16.1 | custom | ALSA Use Case Manager profiles: sound routing of laptops, handhelds and SoCs (SOF, Snapdragon, ...) |
| `alsa-utils` | drivers | 1.2.16 | autotools | ALSA tools: alsamixer, amixer, aplay, arecord, alsactl (mixer state across reboots) |
| `autoconf` | devel | 2.73 | autotools | GNU autoconf: configure scripts from configure.ac |
| `automake` | devel | 1.19 | autotools | GNU automake: Makefile.in from Makefile.am |
| `base-devel` | meta | 2026.1 | meta | Everything needed to build any recipe natively (meta package) |
| `base` | meta | 2026.1 | meta | Minimal CleanLinux userland (meta package) |
| `bash` | core | 5.3.20 | autotools | GNU Bourne Again shell (with all upstream patches) |
| `bc` | devel | 1.08.2 | autotools | GNU bc and dc: arbitrary precision calculators (the kernel build uses bc) |
| `binutils` | devel | 2.47 | autotools | GNU assembler, linker and binary utilities |
| `bison` | devel | 3.8.2 | autotools | GNU parser generator (yacc replacement) |
| `bluez` | drivers | 5.87 | autotools | BlueZ: the Bluetooth daemon (bluetoothd), bluetoothctl and libbluetooth |
| `btrfs-progs` | core | 7.3 | autotools | btrfs filesystem tools: mkfs.btrfs, btrfs (subvolumes, snapshots, scrub, send), btrfsck |
| `burn` | core | 0.7.0 | make | The CleanLinux package manager: source based, rolling+++ |
| `bzip2` | core | 1.0.8 | custom | Block-sorting file compressor and libbz2 |
| `ca-certificates` | core | 2026.10.20 | custom | Mozilla's trusted root certificates for TLS (the NSS bundle as extracted by curl.se) |
| `ccache` | devel | 4.14.2 | cmake | Compiler cache: rebuilds of the same sources come from the cache (burn CCACHE=1) |
| `cleanlinux-boot` | core | 0.2.0 | make | Boot of CleanLinux: dinit services and their C helper (early filesystems, devices, clock, getty, zram, power, kernels in the ESP) |
| `cleanlinux-install` | core | 0.1.0 | make | The CleanLinux installer: GPT, ESP and btrfs, the running system's packages (burn clone), fstab, systemd-boot, users |
| `cmake` | devel | 4.4.5 | custom | Cross-platform build system generator |
| `coreutils` | core | 9.12 | autotools | GNU core utilities: ls, cp, mv, cat, ... |
| `curl` | core | 8.23.0 | autotools | URL transfer tool and library (libcurl): HTTP/1.1, HTTPS through OpenSSL, FTP |
| `dbus` | core | 1.16.2 | meson | D-Bus: the message bus daemon and libdbus |
| `dhcpcd` | core | 10.5.2 | custom | DHCP and DHCPv6 client: IPv4LL, SLAAC, privilege separation |
| `diffutils` | core | 3.12 | autotools | GNU diff, cmp, diff3 and sdiff |
| `dinit` | core | 0.22.1 | custom | dinit: fast, small service manager and init with dependency handling |
| `dosfstools` | core | 4.2 | autotools | FAT filesystem tools: mkfs.fat, fsck.fat, fatlabel (the EFI system partition) |
| `duktape` | platform | 2.7.0 | custom | Duktape: an embeddable JavaScript engine (the rules of polkit) |
| `dwarves` | devel | 1.32 | cmake | pahole and the DWARF tools: BTF for the kernel (sched_ext, BPF), struct layouts |
| `e2fsprogs` | core | 1.47.4 | autotools | ext2/3/4 filesystem tools: mke2fs, e2fsck, tune2fs, resize2fs, debugfs |
| `elfutils` | devel | 0.197 | autotools | ELF and DWARF libraries and tools: libelf (objtool, BTF), libdw (pahole), eu-* tools |
| `ell` | core | 0.83 | autotools | Embedded Linux Library: the D-Bus, netlink, crypto and TLS core of iwd |
| `elogind` | platform | 257.16 | meson | elogind: the logind API of systemd without systemd (sessions, seats, device access, suspend) |
| `eudev` | core | 3.3.0 | autotools | udev without systemd: device manager (udevd, udevadm), rules, hwdb and libudev |
| `expat` | core | 2.10.0 | autotools | Expat: stream-oriented XML parser library |
| `filesystem` | core | 2026.1 | custom | CleanLinux base layout: merged /usr, default /etc files, os-release |
| `findutils` | core | 4.11.0 | autotools | GNU find, xargs and locate |
| `flex` | devel | 2.6.4 | autotools | Fast lexical analyser generator (lex) |
| `fontconfig` | platform | 2.18.3 | meson | Fontconfig: font discovery and configuration (fc-list, fc-match, fc-cache) |
| `freetype` | platform | 2.15.0 | meson | FreeType: the font rasterizer (TrueType, OpenType, CFF, WOFF, bitmap fonts) |
| `fribidi` | platform | 1.0.18 | meson | GNU FriBidi: the Unicode bidirectional algorithm (Arabic, Hebrew) for Pango and others |
| `gawk` | core | 5.4.1 | autotools | GNU awk |
| `gcc` | devel | 16.2.0 | autotools | GNU Compiler Collection: C and C++ compilers |
| `gdbm` | core | 1.26 | autotools | GNU dbm: key/value database library (man-db's index) |
| `gettext` | devel | 1.0 | autotools | GNU gettext tools: msgfmt, xgettext, autopoint (glibc has libintl itself) |
| `git` | core | 2.56.0 | custom | Distributed version control system |
| `glib` | platform | 2.90.1 | meson | GLib: the core library of GNOME and many others (GObject, GIO, D-Bus bindings) |
| `glibc` | core | 2.44 | autotools | GNU C library: libc, the dynamic loader and friends |
| `glslang` | devel | 16.6.0 | cmake | glslang: the Khronos GLSL/HLSL front end and glslangValidator (Mesa compiles the shaders of its Vulkan drivers with it) |
| `gperf` | devel | 3.3 | autotools | GNU perfect hash function generator (builds the keyword tables of eudev) |
| `grep` | core | 3.12 | autotools | GNU grep: search text with regular expressions |
| `groff` | core | 1.24.2 | autotools | GNU troff: formats manual pages for the terminal |
| `gzip` | core | 1.15 | autotools | GNU gzip compression utility |
| `hardware` | drivers | 1 | custom | The hardware profile of the device: its quirks (udev rules, hwdb, modprobe.d, sysctl.d) and boot modules |
| `harfbuzz` | platform | 15.0.0 | meson | HarfBuzz: the text shaping engine (OpenType layout of every script) |
| `hwdata` | platform | 0.413 | autotools | hwdata: PCI, USB and PNP id databases (lspci, lsusb, libdisplay-info) |
| `iproute2` | core | 7.3.0 | custom | IP routing utilities: ip, ss, bridge, tc |
| `iwd` | core | 3.12 | autotools | iwd: the wireless daemon (WPA2/WPA3, enterprise) and iwctl |
| `kbd` | core | 2.10.0 | autotools | Console keyboard maps and fonts: loadkeys, setfont, showkey, kbd_mode |
| `kmod` | core | 34.3 | meson | Kernel module tools and library: modprobe, depmod, lsmod, insmod, rmmod, modinfo |
| `less` | core | 710 | autotools | Terminal pager (man, git and burn show long output with it) |
| `libcap` | platform | 2.78 | custom | libcap: POSIX capabilities library and tools (getcap, setcap, capsh) |
| `libdisplay-info` | platform | 0.4.0 | meson | libdisplay-info: EDID and DisplayID parser for compositors (wlroots, KWin, Mutter) |
| `libdrm` | drivers | 2.4.134 | meson | libdrm: userspace interface to the kernel DRM (KMS, GEM) and the GPU-specific helpers of Mesa |
| `libepoxy` | platform | 1.5.10 | meson | libepoxy: OpenGL function pointer management over EGL and GLX (Xwayland's glamor, GTK) |
| `libevdev` | platform | 1.14.0 | meson | libevdev: the evdev input device interface for libinput (and its debugging tools) |
| `libffi` | devel | 3.8.0 | autotools | Foreign function interface library: calls with argument lists built at run time (Python ctypes, GLib) |
| `libfontenc` | platform | 1.1.9 | autotools | libfontenc: font encodings of the X11 font library |
| `libinput` | platform | 1.32.0 | meson | libinput: input devices for Wayland compositors and X11 (touchpads, touchscreens, tablets, quirks) |
| `libpipeline` | core | 1.5.8 | autotools | Library for running pipelines of subprocesses (man-db) |
| `libpng` | platform | 1.6.59 | autotools | libpng: the PNG reference library (freetype's color glyphs, image loaders) |
| `libtool` | devel | 2.6.2 | autotools | GNU libtool: portable shared libraries for autotools builds, and libltdl |
| `libx11` | platform | 1.8.14 | autotools | libX11: Xlib, the core X11 client library, and the locale data of X input methods |
| `libxau` | platform | 1.0.12 | autotools | libXau: X11 authorization protocol (.Xauthority) |
| `libxcb` | platform | 1.17.0 | autotools | libxcb: the X11 protocol C binding (XCB) and its extension libraries (randr, dri3, present, xkb, xinput, ...) |
| `libxcomposite` | platform | 0.4.7 | autotools | libXcomposite: client library of the Composite extension |
| `libxcrypt` | core | 4.5.2 | autotools | Modern crypt(3): yescrypt, bcrypt and SHA-crypt password hashing (libcrypt) |
| `libxcursor` | platform | 1.2.3 | autotools | libXcursor: X11 cursor themes and animated cursors |
| `libxcvt` | platform | 0.1.3 | meson | libxcvt: VESA CVT display timings (the modes that Xwayland offers to X11 clients) |
| `libxdamage` | platform | 1.1.7 | autotools | libXdamage: client library of the DAMAGE extension |
| `libxdmcp` | platform | 1.1.5 | autotools | libXdmcp: X Display Manager Control Protocol library |
| `libxext` | platform | 1.3.7 | autotools | libXext: client library of the common X11 extensions (SHAPE, MIT-SHM, SYNC, XC-MISC, ...) |
| `libxfixes` | platform | 6.0.2 | autotools | libXfixes: client library of the XFIXES extension (cursors, regions, selections) |
| `libxfont2` | platform | 2.0.9 | autotools | libXfont2: the font library of the X servers (the built-in fonts, PCF and FreeType fonts) |
| `libxi` | platform | 1.8.4 | autotools | libXi: client library of the X Input extension (XI2: touch, raw and multiple devices) |
| `libxinerama` | platform | 1.1.6 | autotools | libXinerama: client library of the Xinerama extension (screens of a multi-monitor desktop) |
| `libxkbcommon` | platform | 1.13.2 | meson | libxkbcommon: keymaps and keyboard state for Wayland compositors and clients, xkbregistry, xkbcli |
| `libxkbfile` | platform | 1.2.0 | meson | libxkbfile: the XKB file library of xkbcomp and the X servers |
| `libxml2` | platform | 2.15.4 | meson | libxml2: the XML parser and toolkit of GNOME (xmllint) |
| `libxpresent` | platform | 1.0.2 | autotools | libXpresent: client library of the Present extension |
| `libxrandr` | platform | 1.5.5 | autotools | libXrandr: client library of the RandR extension (outputs, modes, rotation) |
| `libxrender` | platform | 0.9.13 | autotools | libXrender: client library of the RENDER extension |
| `libxshmfence` | platform | 1.3.3 | autotools | libxshmfence: shared memory fences of DRI3 (Mesa and Xwayland) |
| `libxtst` | platform | 1.2.6 | autotools | libXtst: client library of the XTEST and RECORD extensions (input emulation) |
| `libxxf86vm` | platform | 1.1.7 | autotools | libXxf86vm: client library of the XFree86-VidMode extension (gamma ramps of old games, Mesa GLX) |
| `linux-firmware` | firmware | 20261019 | custom | Firmware of GPUs, Wi-Fi, Bluetooth, audio DSPs and other devices (what the profile needs: FIRMWARE) |
| `linux-headers` | core | 7.3.1 | custom | Linux kernel userspace API headers |
| `linux-pam` | core | 1.7.3 | meson | Linux-PAM: pluggable authentication modules (pam_unix, pam_limits, pam_env, ...) |
| `linux` | kernel | 7.3.1 | custom | The Linux kernel and modules (CleanLinux defaults + profile GPU drivers) |
| `llvm` | devel | 23.1.5 | cmake | LLVM and clang: the compiler of llvmpipe and lavapipe and of the OpenCL C kernels of Mesa (Intel, Mali) |
| `lua` | platform | 5.4.9 | custom | Lua 5.4: the embeddable scripting language (WirePlumber's scripts), shared liblua |
| `lz4` | core | 1.10.0 | make | Extremely fast compression (library and lz4 tool) |
| `m4` | devel | 1.4.21 | autotools | GNU m4 macro processor |
| `make` | devel | 4.4.1 | autotools | GNU make |
| `man-db` | core | 2.13.1 | autotools | man, apropos and whatis with an index of the installed manual pages |
| `mesa` | drivers | 26.2.6 | meson | Mesa: OpenGL, OpenGL ES, EGL, GBM and Vulkan drivers for the GPUs of the profile (VIDEO_CARDS) |
| `meson` | devel | 1.12.1 | custom | Build system: fast, user friendly (most of the base is built with it) |
| `mold` | devel | 3.0.0 | cmake | Fast linker for ELF (burn LINKER=mold) |
| `mtdev` | platform | 1.1.7 | autotools | mtdev: multitouch protocol A to B translation for libinput |
| `ncurses` | core | 6.6 | autotools | Terminal handling library (wide character build) |
| `ninja` | devel | 1.13.2 | cmake | Small build system with a focus on speed (the backend of meson and cmake) |
| `openresolv` | core | 3.17.4 | custom | resolvconf: /etc/resolv.conf from DHCP clients, VPNs and local resolvers |
| `openssl` | core | 3.5.9 | custom | TLS and cryptography library and the openssl tool (3.5 LTS) |
| `pambase` | core | 2026.1 | custom | CleanLinux PAM stacks: system-auth, system-login, system-services, other |
| `patch` | devel | 2.8.1 | autotools | GNU patch: apply diff files |
| `pcre2` | platform | 10.49 | autotools | PCRE2: Perl-compatible regular expressions (8, 16 and 32 bit, JIT) for GLib, Qt, grep |
| `perl` | devel | 5.44.0 | custom | The Perl 5 language: autoconf, automake, OpenSSL and kernel builds need it |
| `pipewire` | platform | 1.6.11 | meson | PipeWire: the audio and video server (ALSA, PulseAudio and JACK clients, cameras, screen capture) |
| `pixman` | platform | 0.46.4 | meson | pixman: low-level pixel manipulation (compositing, scaling) for cairo, wlroots and Xwayland |
| `pkgconf` | devel | 3.0.10 | meson | pkg-config implementation (also installed as pkg-config) |
| `polkit` | platform | 128 | meson | polkit: authorization for privileged actions of unprivileged programs (rules in JavaScript) |
| `procps-ng` | core | 4.0.7 | autotools | Process and memory tools: ps, top, free, vmstat, pgrep/pkill, watch, sysctl, uptime, w |
| `psmisc` | core | 23.7 | autotools | Process tools that use /proc: fuser, killall, pstree, prtstat, peekfd |
| `python-build` | devel | 1.6.1 | custom | build: the PEP 517 front end; with installer, the python build type of burn |
| `python-flit-core` | devel | 4.2.0 | custom | flit_core: the PEP 517 build backend of the pure Python packages (it builds itself, no pip) |
| `python-installer` | devel | 1.1.0 | custom | installer: installs Python wheels into a destination root (the python build type of burn) |
| `python-mako` | devel | 1.4.3 | python | Mako: the template library that generates the sources of Mesa |
| `python-markupsafe` | devel | 3.0.4 | python | MarkupSafe: escaped strings for templates (Mako, Jinja) |
| `python-packaging` | devel | 26.3 | custom | packaging: versions, specifiers and markers of Python packages (Mesa, build) |
| `python-pyproject-hooks` | devel | 1.3.3 | custom | pyproject_hooks: the PEP 517 hooks that front ends (build) call |
| `python-pyyaml` | devel | 6.0.3 | custom | PyYAML: the YAML parser of Python (Mesa's build scripts) |
| `python-setuptools` | devel | 84.2.1 | python | setuptools: the build backend of most Python packages with C extensions (it builds itself) |
| `python` | devel | 3.15.2 | autotools | The Python 3 language: meson, the kernel's and Mesa's build scripts need it |
| `readline` | core | 8.3.6 | autotools | GNU readline: line editing and history for interactive programs |
| `sbc` | drivers | 2.2 | autotools | SBC: the Bluetooth A2DP audio codec (PipeWire's Bluetooth audio) |
| `seatd` | platform | 0.9.3 | meson | seatd and libseat: seat management (GPU and input devices) for Wayland compositors without logind |
| `sed` | core | 4.10 | autotools | GNU stream editor |
| `shadow` | core | 4.20.3 | autotools | Password and account tools: passwd, useradd, usermod, groupadd, chage, newuidmap, ... |
| `sof-firmware` | firmware | 2026.09.2 | custom | Sound Open Firmware: the audio DSP firmware and topologies of Intel laptops and handhelds |
| `spirv-headers` | devel | 1.4.363.0 | cmake | SPIR-V headers and grammar of SPIRV-Tools and SPIRV-LLVM-Translator (the Vulkan SDK release) |
| `spirv-llvm-translator` | devel | 23.1.3 | cmake | SPIRV-LLVM-Translator: LLVM IR to SPIR-V and back (LLVMSPIRVLib, llvm-spirv) for the OpenCL C kernels of Mesa |
| `spirv-tools` | devel | 1.4.363.0 | cmake | SPIRV-Tools: the SPIR-V assembler, validator and optimizer (the OpenCL C kernels of Mesa for Intel and Mali) |
| `systemd-boot` | core | 261.4 | meson | systemd-boot: the UEFI boot manager of systemd, built alone (no systemd) |
| `tar` | core | 1.35 | autotools | GNU tar archiver |
| `turnstile` | platform | 0.1.11 | meson | turnstile: a user service manager (dinit --user) and XDG_RUNTIME_DIR for every login, without systemd |
| `util-linux` | core | 2.42.4 | autotools | Core Linux system utilities: mount, fdisk, lsblk, agetty, kill, ... |
| `vulkan-headers` | drivers | 1.4.367 | cmake | Vulkan headers and the API registry (vk.xml) of the Vulkan loader, Mesa and Vulkan applications |
| `vulkan-loader` | drivers | 1.4.367 | cmake | Vulkan loader (libvulkan): finds the drivers in /usr/share/vulkan/icd.d and the layers |
| `wayland-protocols` | platform | 1.50 | meson | Wayland protocol extensions (XML): xdg-shell, linux-dmabuf, presentation-time, ... |
| `wayland` | platform | 1.26.0 | meson | Wayland: the display protocol library (libwayland-client, -server, -cursor, -egl) and wayland-scanner |
| `wireless-regdb` | firmware | 2026.09.03 | custom | Wireless regulatory database: the allowed Wi-Fi channels and power of each country (signed) |
| `wireplumber` | platform | 0.5.19 | meson | WirePlumber: the session and policy manager of PipeWire (devices, routing, Bluetooth profiles) |
| `xcb-proto` | platform | 1.17.0 | autotools | XCB protocol descriptions: the XML of the X11 protocol and the xcbgen generator of libxcb |
| `xkbcomp` | platform | 1.5.0 | autotools | xkbcomp: the XKB keymap compiler of the X servers (Xwayland runs it for every keymap) |
| `xkeyboard-config` | platform | 2.48 | meson | XKB data: keyboard models, layouts and options for libxkbcommon and X11 |
| `xorgproto` | platform | 2026.1 | meson | X11 protocol headers: xproto, the extensions (randr, render, xinput, dri3, present, ...) and GL/GLX |
| `xtrans` | platform | 1.6.0 | autotools | xtrans: the transport layer of the X11 libraries and servers (headers only) |
| `xwayland` | platform | 24.1.14 | meson | Xwayland: the X server that runs X11 applications on a Wayland compositor (glamor, GLX, DRI3) |
| `xz` | core | 5.8.4 | autotools | XZ Utils: LZMA/xz compression library and tools |
| `zlib-ng` | core | 2.3.3 | cmake | zlib replacement with SIMD optimisations (zlib-compatible API and ABI) |
| `zstd` | core | 1.5.7 | meson | Zstandard: fast real-time compression (library and zstd tool) |

## English

**CleanLinux-Recipes** is the package recipe repository of CleanLinux, a base for Linux spins like Arch: a from-scratch (not LFS) system, drivers and hardware tuning for PCs, laptops, handhelds and boards (x86_64 and arm64), built on glibc. It holds the base layers only (core, hardware, platform); desktops, applications and games belong to spin repositories, which are recipe overlays on top of this one. Like the AUR, but for the whole system: it contains **no binaries**, only upstream source links, their sha256 and build instructions. The `burn` package manager builds everything locally, tuned by a hardware profile (CPU flags, GPU drivers, features). Rules: https-only sources with mandatory checksums, no binary or vendored files, deterministic builds through explicit features, minimal output (no docs/extra locales/static libs by default). `tools/lint.sh` is the self-contained checker used by CI; `--fetch` also downloads the sources and verifies their checksums. `tools/updates.sh` watches upstream releases (inferred from the recipe sources: GNU/kernel.org listings, GitHub releases, bash/readline patch levels); the daily `updates` workflow bumps and verifies recipes, publishes them to the `edge` channel and proposes them to `main`.

License of the recipes: MIT (see `LICENSE`). Each package keeps its own upstream license (`license=` in the recipe).
