# Repository workflow

## Trunk-based development

- Keep `main` as the only long-lived branch and keep it releasable.
- Create each change from the latest `main` in a short-lived `<type>/<slug>` branch. Use `feature`, `fix`, `perf`, `refactor`, `docs`, `test`, or `chore` as the type.
- Merge completed work into `main` through a pull request. Do not create long-lived `develop` or `release` branches.
- Do not commit directly to `main`.
- Use English Conventional Commits: `<type>(<scope>): <subject>`. Omit the scope when none is established.
- Commit each meaningful unit separately. Local commits do not require approval.
- Obtain explicit approval immediately before a push, pull request creation, workflow dispatch, or other externally visible action.

## Change fragments

- Add a Changie fragment for every user-facing change before committing:

  ```bash
  mise run change
  ```

- Do not add fragments for internal refactoring, CI-only changes, or documentation changes that do not affect users.
- Write fragment bodies as concise English release notes for users.

## Releases

- Cut releases only from `main` after required checks pass.
- Run the **Cut Release** workflow and use `auto` unless a specific SemVer increment is required.
- **Cut Release** batches Changie fragments, updates `CHANGELOG.md` and the Xcode project version, then opens a release pull request with `chore: release vX.Y.Z`.
- Merging the release pull request starts **Release**, which uploads the App Store build, creates the GitHub Release and tag from the Changie notes, then updates the Homebrew cask.
- If deployment fails after the release commit exists, do not run **Cut Release** again. Run **Release** with the existing version and `deploy=true`.
- Do not create release tags manually.
