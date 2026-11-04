# Как участвовать

**CleanLinux-Recipes** — рецепты пакетов базы CleanLinux, часть [CleanLinux](https://github.com/vovawees/CleanLinux). *English [below](#english).*

## С чего начать

- Что входит в базу, а что ставится сверху — [SCOPE.md](https://github.com/vovawees/CleanLinux/blob/main/docs/SCOPE.md); как всё устроено — [ARCHITECTURE.md](https://github.com/vovawees/CleanLinux/blob/main/docs/ARCHITECTURE.md).
- Что дальше — [ROADMAP.md](https://github.com/vovawees/CleanLinux/blob/main/docs/ROADMAP.md), issues с меткой `roadmap` и общая доска [CleanLinux roadmap](https://github.com/users/vovawees/projects/1).
- Крупную правку сначала обсудите в issue, чтобы не делать работу дважды.

## Проверки

Хостингового CI нет: проверки запускаются локально, одной командой (нужен shellcheck 0.11 или новее).

`tools/check.sh` — shellcheck, `tools/lint.sh` всех рецептов и загрузка с проверкой sha256 изменённых (`--all` — всех); `tools/edge.sh` — ежедневные обновления upstream в канал `edge` (cron).

Быстрые проверки можно запускать автоматически перед каждым `git push`:

```sh
git config core.hooksPath tools/hooks   # перед push: tools/check.sh --quick
```

## Правила

- Только текст: ссылки на исходники upstream, sha256, рецепты и маленькие патчи — никаких бинарников.
- Рецепт — по [TEMPLATE.recipe](TEMPLATE.recipe); sha256 — только `burn checksum --write <pkg>` из настоящих файлов; категория — слой базы ([RECIPES.md](https://github.com/vovawees/CleanLinux/blob/main/docs/RECIPES.md)).
- Пакет в базе, только если он нужен, чтобы система загрузилась, обновлялась или использовала железо ([SCOPE.md](https://github.com/vovawees/CleanLinux/blob/main/docs/SCOPE.md)); остальное — в сборки.
- Исправление уязвимости: в рецепте `security=(CVE-… GHSA-…)` — его берёт `burn update --security`.
- Новый рецепт собирается хотя бы один раз: `burn -R packages build <pkg>` (для `core` — и в bootstrap).

## Коммиты и pull request'ы

- Одна логическая правка — один коммит. Сообщение — на английском, в стиле истории: `область: что изменилось`
  (`bootstrap: …`, `docs: …`), подробности — в теле письма.
- Ветка от `main`, pull request в `main`; `Closes #N` (или `Closes vovawees/CleanLinux#N`) закрывает issue при слиянии.
- Документация меняется в том же pull request'е, что и поведение.

## English

CleanLinux-Recipes is part of [CleanLinux](https://github.com/vovawees/CleanLinux). There is no hosted CI: run `tools/check.sh` (shellcheck 0.11+)
before every push (`git config core.hooksPath tools/hooks` runs the quick checks automatically). Text only (links, sha256, recipes, small patches); sha256 come from `burn checksum --write`; a package belongs here only if the base needs it (SCOPE.md); security fixes list their advisories in `security=()`; every new recipe is built at least once.
Commit messages are in English (`area: what changed`); pull requests target `main`, and `Closes #N` closes the issue.
See the [roadmap](https://github.com/vovawees/CleanLinux/blob/main/docs/ROADMAP.md) and the [project board](https://github.com/users/vovawees/projects/1).
