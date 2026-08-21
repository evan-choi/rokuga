# Contributing to Rokuga

## Setup

Rokuga requires macOS, Xcode 26, and [mise](https://mise.jdx.dev/).

```bash
mise install
mise exec -- xcodegen generate
```

Edit `project.yml` instead of `Rokuga.xcodeproj`, then regenerate the project. Run `./scripts/setup-dev-signing.sh` when manual testing requires persistent Screen Recording permission.

## Workflow

1. Create a short-lived `<type>/short-description` branch from `main`. Use `feature`, `fix`, `perf`, `refactor`, `docs`, `test`, or `chore`.
2. Add tests with code changes.
3. Run `mise run change` for user-facing changes.
4. Use English Conventional Commits, for example `fix: correct recording duration`.
5. Open a pull request against `main` and describe the change and verification performed.

## Checks

```bash
(cd RokugaCore && swift test)
mise exec -- actionlint
mise exec -- swiftlint lint --strict
mise exec -- swiftformat --lint .
mise exec -- bun scripts/lint-localization.ts
mise exec -- bun scripts/audit-zero-copy.ts
```

For website changes, also run:

```bash
cd website
mise exec -- bun install --frozen-lockfile
mise exec -- bun test
mise exec -- bun run lint
mise exec -- bun run build
```

Test UI and recording changes in the app. Include screenshots for visible UI changes.

Contributions are licensed under the [Apache License 2.0](LICENSE).
