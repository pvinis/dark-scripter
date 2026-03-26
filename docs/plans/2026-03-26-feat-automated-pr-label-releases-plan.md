---
title: "feat: Automated releases from PR labels"
type: feat
status: completed
date: 2026-03-26
origin: docs/brainstorms/2026-03-26-automated-releases-brainstorm.md
---

# Automated Releases from PR Labels

## Overview

Add a GitHub Actions workflow (`version-bump.yml`) that automates the entire release process when a PR is merged to main with version labels. The workflow bumps the version in `Sources/main.swift`, updates `CHANGELOG.md` in Keep A Changelog format, commits, tags, and pushes. The existing `release.yml` picks up the tag and handles building, GitHub Release creation, and Homebrew tap update.

No manual version bumping. No manual tagging. Just label the PR and merge. (see brainstorm: docs/brainstorms/2026-03-26-automated-releases-brainstorm.md)

## Problem Statement / Motivation

Version bumping is currently manual. Every release requires editing `Sources/main.swift`, committing "Bump version to X.Y.Z", tagging, and pushing the tag. There is no changelog. This is tedious for a one-person project and error-prone (tag/source mismatch, forgotten changelog entries). PR labels are the simplest possible input signal, requiring zero changes to the existing development workflow.

## Proposed Solution

A two-label system on PRs:

1. **Version label** (exactly one required for a release): `major`, `minor`, `patch`
2. **Category label** (optional, defaults to "Changed"): `added`, `changed`, `fixed`, `removed`

A new workflow `version-bump.yml` triggers on PR merge to main, reads labels, bumps the version, updates the changelog, commits, tags, and pushes. The existing `release.yml` handles everything downstream.

### Architecture

```
PR merged to main (with labels)
        │
        ▼
version-bump.yml
  ├── Read PR labels
  ├── Determine bump type (major/minor/patch)
  ├── Read current version from Sources/main.swift:3
  ├── Compute new version
  ├── Update Sources/main.swift
  ├── Update CHANGELOG.md (insert entry under correct section)
  ├── Commit both files
  ├── Create tag v{new_version}
  └── Push commit + tag (atomic)
        │
        ▼
release.yml (existing, triggered by v* tag)
  ├── Validate tag matches source version
  ├── Build universal binary
  ├── Create GitHub Release (with auto-generated notes)
  └── Update Homebrew tap
```

## Technical Considerations

### Version storage

The version is a string literal at `Sources/main.swift:3`:
```swift
let version = "1.2.1"
```

The sed replacement must be anchored to this pattern: `let version = "..."`. The existing `release.yml` already uses a robust regex to extract it (line 22). The new workflow should use the same pattern for reading and a targeted sed for writing.

### Concurrency control

If two version-labeled PRs merge in quick succession, both workflow runs would read the same version and race. Solution: use a GitHub Actions `concurrency` group that queues runs (does not cancel in-progress). Each run starts with a fresh checkout of `main` at its current state.

```yaml
concurrency:
  group: version-bump
  cancel-in-progress: false
```

This serializes version bumps so they cannot conflict.

### Atomic push

Push the commit and tag together in a single command to minimize partial failure:
```bash
git push origin main v{new_version}
```

If the push fails (e.g., another run pushed first), the entire operation fails cleanly. The queued concurrency group prevents this in practice.

### Branch protection

This project does not currently have branch protection on `main`. The default `GITHUB_TOKEN` with `contents: write` is sufficient to push commits and tags. If branch protection is added later, a GitHub App token or PAT with bypass permissions would be needed.

### CHANGELOG format

Keep A Changelog format with comparison links:

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.3.0] - 2026-03-26

### Added

- Add dark mode scheduling ([#8](https://github.com/pvinis/dark-scripter/pull/8))

## [1.2.2] - 2026-03-25

### Fixed

- Fix crash on nil config ([#9](https://github.com/pvinis/dark-scripter/pull/9))

[1.3.0]: https://github.com/pvinis/dark-scripter/compare/v1.2.2...v1.3.0
[1.2.2]: https://github.com/pvinis/dark-scripter/compare/v1.2.1...v1.2.2
```

No `[Unreleased]` section needed since every version-labeled PR merge triggers an immediate release.

## Label Validation Rules

These rules resolve edge cases identified during spec analysis:

| Scenario | Behavior |
|---|---|
| No version label | Workflow exits cleanly, no release |
| One version label | Normal flow |
| Multiple version labels | Take highest: major > minor > patch |
| No category label (with version label) | Default to "Changed" (see brainstorm) |
| Multiple category labels | Entry listed under each matching section |
| PR closed without merge | Workflow does not trigger |
| PR to non-main branch | Workflow does not trigger |

## Acceptance Criteria

### Labels

- [x] Create 7 labels in the repo: `major`, `minor`, `patch`, `added`, `changed`, `fixed`, `removed`
- [x] Labels have appropriate colors and descriptions

### CHANGELOG bootstrap

- [x] Create initial `CHANGELOG.md` with Keep A Changelog header (no retroactive entries, start fresh)

### Workflow: `.github/workflows/version-bump.yml`

- [x] Triggers on PR merge to `main` only
- [x] Exits cleanly when no version label is present
- [x] Reads version label and computes correct semver bump
- [x] Handles multiple version labels by taking the highest
- [x] Reads current version from `Sources/main.swift` using anchored pattern
- [x] Writes new version back with sed, targeting `let version = "..."` pattern
- [x] Reads category label(s), defaults to "Changed" if none present
- [x] Inserts changelog entry under correct section(s) with PR title and link
- [x] Adds comparison link at bottom of CHANGELOG.md
- [x] Commits both `Sources/main.swift` and `CHANGELOG.md`
- [x] Creates tag `v{new_version}`
- [x] Pushes commit and tag atomically
- [x] Uses `concurrency` group to serialize runs
- [x] Has `contents: write` permission
- [x] Commit author is `github-actions[bot]`

### Integration with existing release.yml

- [x] Tag format matches existing `v*` trigger pattern
- [x] Version in source matches tag (passes validation step in release.yml)
- [x] No changes needed to existing `release.yml`

### Error handling

- [x] Fails clearly if version regex does not match in `Sources/main.swift`
- [x] Fails clearly if computed tag already exists
- [x] No partial state left on push failure (atomic push)

## Implementation Checklist

### Step 1: Create labels

Use `gh label create` to add all 7 labels with colors and descriptions matching the brainstorm's color suggestions.

### Step 2: Bootstrap CHANGELOG.md

Create `CHANGELOG.md` at the repo root with the standard Keep A Changelog header. No retroactive entries.

### Step 3: Write `.github/workflows/version-bump.yml`

The workflow file, approximately 80-100 lines of YAML with inline bash. Key structure:

```
on:
  pull_request:
    types: [closed]
    branches: [main]

concurrency:
  group: version-bump
  cancel-in-progress: false

permissions:
  contents: write

jobs:
  version-bump:
    if: github.event.pull_request.merged == true
    runs-on: ubuntu-latest
    steps:
      - checkout
      - extract labels from github.event.pull_request.labels
      - determine bump type (exit if none)
      - read current version
      - compute new version
      - update Sources/main.swift
      - update CHANGELOG.md
      - configure git user
      - commit
      - tag
      - push (atomic)
```

### Step 4: Test

- Merge a test PR with `patch` + `fixed` labels and verify the full pipeline
- Merge a PR with no version label and verify it is skipped
- Verify `release.yml` triggers and completes successfully on the new tag

## Dependencies & Risks

**Dependencies:**
- `GITHUB_TOKEN` must have `contents: write` (default for workflows)
- No branch protection on `main` (or a bypass token if protection is added)

**Risks:**
- **Sed fragility:** If `Sources/main.swift` format changes (version moves to a different line or pattern), the sed replacement breaks. Mitigated by anchoring to `let version = "` pattern rather than line number.
- **Pre-release versions:** Not supported in this iteration. The existing `release.yml` handles pre-release tags, but `version-bump.yml` only handles major/minor/patch bumps. Pre-release support can be added later if needed.
- **PR title quality:** Changelog entries use PR titles verbatim. Poor PR titles lead to poor changelog entries. This is acceptable for a single-maintainer project.

## Sources & References

- **Origin brainstorm:** [docs/brainstorms/2026-03-26-automated-releases-brainstorm.md](docs/brainstorms/2026-03-26-automated-releases-brainstorm.md) - all key decisions (label-driven, Keep A Changelog, custom workflow over established tools, composability with existing release.yml)
- Existing release workflow: `.github/workflows/release.yml`
- Version source of truth: `Sources/main.swift:3`
- Keep A Changelog spec: keepachangelog.com
- Homebrew tap: `pvinis/homebrew-pvinis`
