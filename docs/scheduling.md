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
