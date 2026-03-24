---
title: "feat: Skip scripts with underscore prefix"
type: feat
status: active
date: 2026-03-24
---

# Skip scripts with underscore prefix

Scripts in `~/.config/dark-scripter/` whose filenames start with `_` should be skipped during execution. This lets users create helper/intermediate scripts that are called by other scripts but never invoked directly by dark-scripter.

## Motivation

A user may want to share common logic between multiple scripts. For example, a `_common.sh` that exports shared environment setup, sourced by `theme.sh` and `wallpaper.sh`. Without a skip convention, dark-scripter would execute `_common.sh` on its own, which is not intended.

The underscore prefix convention is familiar from Python (`__init__.py`, `_private.py`), Sass (`_partial.scss`), and other tools where `_` means "not a direct entry point."

## Acceptance Criteria

- [x] Scripts starting with `_` are not executed by dark-scripter
- [x] `--help` output mentions the underscore-prefix skip behavior
- [x] README documents the convention with a concrete helper script example
- [x] Version bumped to `1.1.0`

## Implementation

### 1. `Sources/main.swift` - Add prefix check (~line 55)

Add `script.hasPrefix("_")` to the existing guard:

```swift
// Sources/main.swift, in the for loop inside runScripts()
guard !script.hasPrefix("_"), fm.isExecutableFile(atPath: path) else { continue }
```

This is a single-line change. The `_` check goes before the executable check so we skip early without hitting the filesystem.

### 2. `Sources/main.swift` - Update help text (~lines 12-13)

Update the help text to mention the skip behavior:

```swift
print("Each executable file in the config directory is run with DARKMODE=1 (dark)")
print("or DARKMODE=0 (light) set in the environment. Scripts run in alphabetical order.")
print("Files starting with _ are skipped, so you can use them as helpers called by other scripts.")
```

### 3. `Sources/main.swift` - Bump version (line 3)

```swift
let version = "1.1.0"
```

### 4. `README.md` - Document the convention

Add a section or note near the existing script examples explaining:

- Files starting with `_` are skipped
- Use case: shared helper scripts sourced by other scripts
- Concrete example: `_common.sh` sourced by another script

Update the existing line about skipping behavior (line 57) from:

> Scripts run in alphabetical order. Only executable files are run -- non-executable files and dotfiles like `.DS_Store` are skipped.

To:

> Scripts run in alphabetical order. Only executable files are run. Files starting with `_` are skipped, so you can use them as helpers called by other scripts. Non-executable files and dotfiles like `.DS_Store` are also skipped.

Add an example:

```sh
cat > ~/.config/dark-scripter/_common.sh << 'EOF'
#!/usr/bin/env bash
export PATH="/opt/homebrew/bin:$PATH"
current_mode() {
  if [ "$DARKMODE" = "1" ]; then echo "dark"; else echo "light"; fi
}
EOF
chmod +x ~/.config/dark-scripter/_common.sh
```

```sh
cat > ~/.config/dark-scripter/theme.sh << 'EOF'
#!/usr/bin/env bash
source "$(dirname "$0")/_common.sh"
echo "Switched to $(current_mode) mode"
EOF
chmod +x ~/.config/dark-scripter/theme.sh
```

## Edge Cases Considered

- **`__double_underscore.sh`**: Starts with `_`, so skipped. Correct.
- **Bare `_` filename**: Starts with `_`, so skipped. Correct.
- **Symlink `_link -> real.sh`**: Skipped based on the link name, not the target. Correct, the convention is about the name in the config directory.
- **Symlink `run.sh -> _helper.sh`**: Not skipped because the link name does not start with `_`. Correct.
- **Non-executable `_helper.sh`**: Already skipped by the executable check. The underscore prefix adds a second reason. No conflict.

## Out of Scope

- Dotfile explicit filtering (README says dotfiles are skipped but the code only checks executability. This is a pre-existing inaccuracy, separate from this feature.)
- Directory exclusion (`isExecutableFile` returns true for directories on macOS. Pre-existing edge case.)
- Verbose/debug logging for skipped scripts
- Temporary disable mechanism (e.g. `.disabled` suffix)
