# macOS UI operations

## Capture

Use `shotport` first for screenshots and screen inspection. Prefer
`shotport window` for the frontmost app; otherwise select `app`, `browser`,
`desktop`, `ios`, or `android`. Read extracted accessibility text before opening
pixels. If capture is empty or fails, retry with the correct active app/session
invocation before opening System Settings.

For an existing screenshot, inspect the newest PNG in `~/Desktop` or
`~/Downloads`; verify the UI rather than trusting its filename. For asset
replacement, inspect dimensions with `sips`, prefer 2x, optimize with
`imageoptim`, preserve dimensions, then run the gate and verify CI.

## Interact

Use `guiport` for deterministic Mac app inspection and interaction; use
`shotport` for capture. Prefer accessibility identifiers, re-read the tree
after state changes, and use OCR or coordinates only when accessibility data is
insufficient. Use `um` when the task needs LLM-mediated desktop actions rather
than deterministic selectors.

## Native development

- Xcode projects/workspaces: `xcp --help`.
- YAML-generated Xcode projects: `xcodegen --help`.
- iOS Simulator inspection and interaction: `axe list-simulators`, then
  `axe describe-ui`, `axe tap`, or `axe type-text` with the selected UDID.
- Native debugging: run `lldb` inside tmux and attach to the signed app. Never
  re-sign or change bundle identity as a debugging shortcut without approval.
