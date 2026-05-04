# Scheduling

The product intentionally avoids asking users to type cron expressions.

Supported presets:

- Manual only
- At login
- Every 5/10/15/30 minutes
- Hourly at a minute
- Daily at a time
- Weekly on a weekday and time
- Monthly on day 1...28 and time

Internally, presets compile to a scheduler-neutral representation and then to app-managed LaunchAgent plist files. Only labels prefixed with `com.alpox.automate-scripts.job` are managed.

## Every-N-minutes cadence

`Every 5/10/15/30 minutes` presets are compiled as explicit `StartCalendarInterval`
minute entries instead of `StartInterval` seconds. For example, `Every 10 minutes`
becomes minute boundaries `00, 10, 20, 30, 40, 50` every hour. This keeps the
behavior cron-like and easy to verify from the generated LaunchAgent plist.

Scheduler sync is idempotent: if the generated plist content has not changed,
Automate Scripts leaves the plist loaded as-is instead of rewriting and
re-bootstraping it.
