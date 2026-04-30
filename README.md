# Automate Scripts

Automate Scripts is an open-source macOS menu bar and CLI app for managing personal automation scripts without editing raw cron expressions.

## Goals

- Launch automatically after macOS login.
- Show script status from the menu bar.
- Manage multiple script jobs from GUI and CLI using one shared store.
- Use friendly schedule presets instead of raw cron syntax.
- Support English and Korean user-facing text.

## Current status

Alpha scaffold. The core model, CLI, schedule compiler, LaunchAgent dry-run sync, runner, tests, and menu bar shell are being built from the PRD in `.hypercore/prd/` and development plan in `.omx/plans/`.

> `.hypercore/` and `.omx/` are local planning/runtime artifacts and are intentionally ignored by Git.

## Build

```bash
swift test
swift build --product automate
swift run automate --help
```

## CLI examples

```bash
swift run automate add backup --cmd /bin/echo --args "hello" --daily 09:00
swift run automate add cleanup --cmd /bin/echo --every-minutes 30
swift run automate add report --cmd /bin/echo --weekly mon 08:30
swift run automate list
swift run automate run backup
swift run automate sync --dry-run
```

Raw cron expressions are intentionally not accepted in the default UX. Use presets such as `--daily`, `--weekly`, `--monthly`, `--every-minutes`, `--at-login`, or `--manual`.

## Localization

- English: default
- Korean: `--lang ko` in CLI; GUI includes Korean string catalog entries and a language setting.

## Security notes

This app runs local commands on your Mac. Review every script before scheduling it. Avoid storing secrets in plain text environment variables.

## License

MIT. See [LICENSE](LICENSE).
