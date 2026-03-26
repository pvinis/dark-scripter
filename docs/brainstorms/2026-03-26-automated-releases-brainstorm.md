# Brainstorm: Automated Releases from PRs

**Date:** 2026-03-26
**Status:** Ready for planning

## What We're Building

An automated release pipeline driven entirely by PR labels. When a PR is merged to main with version labels (`major`, `minor`, `patch`), a GitHub Actions workflow will:

1. Determine the bump type from the PR labels
2. Bump the version string in `Sources/main.swift`
3. Update `CHANGELOG.md` in Keep A Changelog format
4. Commit the changes, create a git tag, and push
5. The existing `release.yml` picks up the tag and handles building, GitHub Release creation, and Homebrew tap update

No manual version bumping. No manual tagging. Just label your PR and merge.

## Why This Approach

**Custom GH Actions workflow over established tools (auto, release-please, semantic-release) because:**

- **PR labels are the input.** release-please and semantic-release require Conventional Commits, not labels. auto supports labels but needs Node.js.
- **Keep A Changelog format.** None of the established tools output this format natively.
- **Composes with existing release.yml.** The custom workflow just creates the tag. The existing workflow handles everything downstream (build, release, Homebrew). No need to rewrite what already works.
- **No external dependencies.** Pure bash and gh CLI. No Node.js runtime in CI for a Swift project.
- **Small project, simple needs.** ~80 lines of YAML vs. configuring a complex tool and working around its assumptions.

## Key Decisions

### Version bump signal: PR labels
- Labels: `major`, `minor`, `patch`
- PRs without a version label are skipped (no release)
- Simple, visual, easy to add/change before or after merge

### CHANGELOG categorization: Extra labels
- Labels: `added`, `changed`, `fixed`, `removed` (matching Keep A Changelog sections)
- These labels determine which section the PR title goes under
- If no category label is present, default to "Changed"
- A PR has both a version label AND a category label (e.g., `minor` + `added`)

### CHANGELOG format: Keep A Changelog
- Standard format from keepachangelog.com
- Sections: Added, Changed, Fixed, Removed
- Each entry is the PR title with a link to the PR number

### Release trigger: On PR merge
- Fully automatic on merge to main
- No intermediate "release PR" step
- No manual dispatch needed

### Composability with existing workflow
- New workflow: `version-bump.yml` - triggers on PR merge, bumps version, updates changelog, commits, tags
- Existing workflow: `release.yml` - triggers on `v*` tag push, builds, creates GitHub Release, updates Homebrew
- Clean separation of concerns

## Labels to Create

| Label | Purpose | Color suggestion |
|-------|---------|-----------------|
| `major` | Major version bump (breaking changes) | red |
| `minor` | Minor version bump (new features) | blue |
| `patch` | Patch version bump (bug fixes) | green |
| `added` | CHANGELOG: Added section | light blue |
| `changed` | CHANGELOG: Changed section | yellow |
| `fixed` | CHANGELOG: Fixed section | orange |
| `removed` | CHANGELOG: Removed section | gray |

## Open Questions

None - all key decisions resolved.
