# Contributing to Rokuga

## Setup

Rokuga requires macOS, Xcode 26, and [mise](https://mise.jdx.dev/).

```bash
mise install
mise run xcode-project:generate
```

Edit `project.yml` instead of `Rokuga.xcodeproj`, then regenerate the project. Run `./scripts/setup-dev-signing.sh` when manual testing requires persistent Screen Recording permission.

## Workflow

1. Create a short-lived `<type>/short-description` branch from `main`. Use `feature`, `fix`, `perf`, `refactor`, `docs`, `test`, or `chore`.
2. Add tests with code changes.
3. Run `mise run changelog:add` for user-facing changes.
4. Use English Conventional Commits, for example `fix: correct recording duration`.
5. Open a pull request against `main` and describe the change and verification performed.

## Test and lint

```bash
mise run repository:test-and-lint
```

For website changes, also run:

```bash
mise run website:test-lint-build
```

Test UI and recording changes in the app. Include screenshots for visible UI changes.

Contributions are licensed under the [Apache License 2.0](LICENSE).
