# Contributing

Thanks for helping improve Automate Scripts.

## Development

```bash
swift test
swift build --product automate
```

## Guidelines

- Keep GUI and CLI behavior backed by `AutomateCore`.
- Do not add raw cron-expression entry points to the default UX.
- Add or update Korean and English strings together.
- Add tests for scheduler, store, runner, or CLI changes.
- Avoid new dependencies unless the trade-off is documented.
