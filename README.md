# CleanLinux-Recipes

Рецепты пакетов для **CleanLinux** — экспериментального Linux «с нуля» (не LFS) для портативных консолей и ПК на **x86_64 и arm64**.

Это аналог AUR, но для всей системы: **здесь нет ни одного бинарника** — только ссылки на исходники upstream, их sha256 и инструкции сборки. Всё собирает пакетный менеджер `burn` прямо на машине пользователя под её процессор и видеокарту (профили `steam-deck`, `rog-ally`, `mangmi-air-x`, `raspberry-pi-5`, `native`, …).

*English summary [below](#english).*

## Принципы

- **Только ссылки + рецепты.** Исходники качаются по `https://` (или через зеркала `gnu://`, `kernel://`), у каждого есть sha256 — при несовпадении `burn` сборку не начнёт. CI отклоняет двоичные файлы и файлы больше 256 KiB.
- **Детерминированность.** Опциональные зависимости включаются только через *features* (аналог USE-флагов), а не «что случайно нашлось в системе». Для meson по умолчанию `--auto-features=disabled`.
- **Минимализм.** Без документации и лишних локалей (настраивается `KEEP_DOCS`, `LOCALES`), без `.la` и статических библиотек, если есть `.so`, бинарники стрипаются.
- **Совместимость.** glibc (не musl), merged `/usr` (`/bin`, `/lib`, `/lib64` → `/usr/...`), init — dinit, Wayland-first.
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
| `summary`, `homepage`, `license`, `category` | описание |
| `depends`, `makedepends` | зависимости времени работы / только сборки; `pkg:feat`, `pkg:!feat` — условные |
| `features` | переключатели: `+feat` включена, `-feat` выключена по умолчанию |
| `build_type` | `autotools` `meson` `cmake` `make` `cargo` `python` `custom` `meta` |
| `source`, `sha256` | исходники (`[имя::]url` или локальный файл) и их хеши |
| `patches`, `patch_strip` | патчи и уровень `-p` (по умолчанию 1) |
| `configure_args`, `meson_args`, `cmake_args`, `make_args`, `make_install_args`, `cargo_args` | аргументы систем сборки |
| `out_of_tree`, `meson_subdir`, `cmake_subdir`, `srcdir` | раскладка исходников |
| `options` | `!lto` `!strip` `!hardening` `!prune` `staticlibs` `emptydirs` |
| `backup` | конфиги, которые нельзя перезаписывать (новая версия ляжет как `.burnnew`) |

Функции (все необязательны, выполняются в каталоге исходников): `do_prepare`, `do_configure`, `do_build`, `do_check`, `do_install`, `post_install`, а также `configure_extra`/`meson_extra`/`cmake_extra` (печатают по аргументу в строке). Внутри доступны `$SRC $BUILD $DESTDIR $FILES $CC $CFLAGS $LDFLAGS $CHOST $CARCH $KARCH $CROSS $JOBS $VIDEO_CARDS`, помощники `use`, `use_enable`, `use_with`, `meson_feature`, `meson_use`, `cmake_use` и стандартные шаги `bt_configure`, `bt_build`, `bt_install`.

## Каналы (rolling release+++)

- `main` — основной канал: только рецепты, прошедшие CI (lint + проверка ссылок и sha256).
- `edge` *(план)* — свежие версии сразу после выхода upstream.
- `security` *(план)* — только исправления безопасности поверх `main`.

`burn update` не обновляет вслепую: показывает план (что, зачем, риск `major`/`core`, changelog из git-истории рецептов), сначала **собирает всё**, затем делает снимок (btrfs-хук), применяет, сам пересобирает пакеты, чьи библиотеки сменили soname, и проверяет систему (`burn doctor`). Любой пакет можно откатить (`burn rollback`) и заморозить (`burn hold`).

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

Upstream определяется по ссылкам самого рецепта, отдельные метаданные не нужны: листинги GNU и kernel.org (включая каталоги версий вроде `gcc-X/` и `util-linux/vX.Y/`), stable-ядро из `releases.json`, GitHub releases (теги как запасной вариант), любые https-каталоги, официальные патчи bash/readline (`_patchlevel`).

## Пакеты

| Пакет | Версия | Сборка | Описание |
|---|---|---|---|
| `base-devel` | 2026.1 | meta | Toolchain for building recipes natively (meta package) |
| `base` | 2026.1 | meta | Minimal CleanLinux userland (meta package) |
| `bash` | 5.3.20 | autotools | GNU Bourne Again shell (with all upstream patches) |
| `binutils` | 2.47 | autotools | GNU assembler, linker and binary utilities |
| `bison` | 3.8.2 | autotools | GNU parser generator (yacc replacement) |
| `coreutils` | 9.12 | autotools | GNU core utilities: ls, cp, mv, cat, ... |
| `diffutils` | 3.12 | autotools | GNU diff, cmp, diff3 and sdiff |
| `dinit` | 0.22.1 | custom | dinit: fast, small service manager and init with dependency handling |
| `filesystem` | 2026.1 | custom | CleanLinux base layout: merged /usr, default /etc files, os-release |
| `findutils` | 4.11.0 | autotools | GNU find, xargs and locate |
| `gawk` | 5.4.1 | autotools | GNU awk |
| `gcc` | 16.2.0 | autotools | GNU Compiler Collection: C and C++ compilers and their runtime libraries |
| `glibc` | 2.44 | autotools | GNU C library: libc, the dynamic loader and friends |
| `grep` | 3.12 | autotools | GNU grep: search text with regular expressions |
| `gzip` | 1.15 | autotools | GNU gzip compression utility |
| `linux-headers` | 7.3.1 | custom | Linux kernel userspace API headers |
| `linux` | 7.3.1 | custom | The Linux kernel and modules (CleanLinux defaults + profile GPU drivers) |
| `lz4` | 1.10.0 | make | Extremely fast compression (library and lz4 tool) |
| `m4` | 1.4.21 | autotools | GNU m4 macro processor |
| `make` | 4.4.1 | autotools | GNU make |
| `ncurses` | 6.6 | autotools | Terminal handling library (wide character build) |
| `patch` | 2.8.1 | autotools | GNU patch: apply diff files |
| `pkgconf` | 3.0.10 | meson | pkg-config implementation (also installed as pkg-config) |
| `readline` | 8.3.6 | autotools | GNU readline: line editing and history for interactive programs |
| `sed` | 4.10 | autotools | GNU stream editor |
| `tar` | 1.35 | autotools | GNU tar archiver |
| `util-linux` | 2.42.4 | autotools | Core Linux system utilities: mount, fdisk, lsblk, agetty, kill, ... |
| `xz` | 5.8.4 | autotools | XZ Utils: LZMA/xz compression library and tools |
| `zlib-ng` | 2.3.3 | cmake | zlib replacement with SIMD optimisations (zlib-compatible API and ABI) |
| `zstd` | 1.5.7 | meson | Zstandard: fast real-time compression (library and zstd tool) |

## English

**CleanLinux-Recipes** is the package recipe repository of CleanLinux, an experimental from-scratch (not LFS) Linux for handheld consoles and PCs (x86_64 and arm64), built on glibc. Like the AUR, but for the whole system: it contains **no binaries**, only upstream source links, their sha256 and build instructions. The `burn` package manager builds everything locally, tuned by a hardware profile (CPU flags, GPU drivers, features). Rules: https-only sources with mandatory checksums, no binary or vendored files, deterministic builds through explicit features, minimal output (no docs/extra locales/static libs by default). `tools/lint.sh` is the self-contained checker used by CI; `--fetch` also downloads the sources and verifies their checksums.

License of the recipes: MIT (see `LICENSE`). Each package keeps its own upstream license (`license=` in the recipe).
