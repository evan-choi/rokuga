# Contributing to Rokuga

## Set up the repository

Rokuga development requires macOS, Xcode 26, and [mise](https://mise.jdx.dev/).

```bash
git clone https://github.com/evan-choi/rokuga.git
cd rokuga
mise install
xcodegen generate
```

The default ad-hoc signature is sufficient for builds. Run `./scripts/setup-dev-signing.sh` if you need macOS to retain Screen Recording permission between builds.

## Create a branch

Rokuga uses trunk-based development. `main` is the only long-lived branch.

```bash
git switch main
git pull --ff-only
git switch -c feature/short-description
```

Keep the branch focused and merge it as soon as the change is complete. Do not create `develop` or long-lived release branches.

## Commit changes

Use English Conventional Commits:

```text
<type>(<scope>): <subject>
```

Use `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, or `chore`. Omit the scope when the repository has no established scope for the change. Keep unrelated changes in separate commits.

## Add release notes

Add a Changie fragment for each user-facing change:

```bash
mise run change
```

Choose the kind based on the user-visible effect:

| Kind | `auto` increment |
| --- | --- |
| `Added` | minor |
| `Changed` | minor |
| `Fixed` | patch |
| `Removed` | major |
| `Security` | patch |

Write a concise English sentence describing the result for users. Skip fragments for internal refactoring, CI-only changes, and documentation that does not change product behavior.

## Run checks

```bash
(cd RokugaCore && swift test)
actionlint
swiftlint lint --strict
swiftformat --lint .
python3 scripts/lint-localization.py
./scripts/audit-zero-copy.sh
```

Website changes also require:

```bash
cd website
bun install --frozen-lockfile
bun test
bun run lint
bun run build
```

## Open a pull request

Push the branch and open a pull request against `main`. Describe the behavior change, verification performed, compatibility impact, and known limitations. Required CI checks must pass before squash merge.

## Release process

Maintainers run **Cut Release** from GitHub Actions and choose `auto` unless a specific SemVer increment is required. The workflow opens a short-lived release pull request containing the batched changelog and version update.

Merging the release pull request starts **Release**. It uploads the App Store build, creates the GitHub Release and tag, then updates the Homebrew cask. Retry a failed deployment by running **Release** with the existing version and `deploy=true`; do not run **Cut Release** again.
