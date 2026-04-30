# Architecture

Automate Scripts is split into three layers:

1. `AutomateCore` — models, storage, scheduler compilation, runner, logs, localization.
2. `automate` CLI — scriptable interface over the shared core.
3. `AutomateMenuBarApp` — SwiftUI menu bar shell over the shared core.

The GUI and CLI must not duplicate business logic. They share `JobStore`, `SchedulePreset`, `ScheduleCompiler`, `ScriptRunner`, and `RunLogStore`.
