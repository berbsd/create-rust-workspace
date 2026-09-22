# create-rust-workspace — Agent Guide

Claude Code plugin: `SKILL.md` (the workflow an agent follows) + `scripts/scaffold.sh` (a
thin wrapper around `cargo generate`). It generates new projects from
[rust-workspace-template](https://github.com/berbsd/rust-workspace-template); it does not
vendor or duplicate that template's content.

## Division of responsibility

- **Here:** resolving which template version to use (`cargo-generate` has no "latest tag"
  concept — see `scaffold.sh`'s header), translating this plugin's flags into
  `cargo generate`'s, and the install/version checks for `cargo-generate` itself.
- **rust-workspace-template:** everything else — cloning, copying, `{{TOKEN}}`
  substitution, the example-service on/off switch, the Rust-toolchain version pin. That
  logic lives in that repo's `cargo-generate.toml` / `hooks/post.rhai`, not here. If a
  generated workspace looks wrong, check there first before assuming a `scaffold.sh` bug.

## Making changes

- `scripts/scaffold.sh` is the only real code in this repo. Keep it `bash`,
  `set -euo pipefail`, and run `shellcheck scripts/scaffold.sh` after any edit — it's the
  closest thing to a test suite here.
- No automated tests. Verify behavior changes by actually running the script end-to-end,
  both with and without `--no-example`. Use `--template-dir <local rust-workspace-template
  checkout>` to skip the network — point it at a plain checkout, not a git worktree (leaks
  a stray `.git` file into the output; see that flag's comment).
- Don't hand-edit generated output in a test run to "fix" something — the fix belongs in
  `scaffold.sh` or in `rust-workspace-template`, never patched around after the fact.

## Commits & releases

- Conventional commits (`feat:`, `fix:`, `chore:`, `feat!:` / `BREAKING CHANGE:` footer for
  breaking changes) — `CHANGELOG.md` is generated from these via `git-cliff`
  (`.cliff.toml`), never hand-written.
- `bin/release VERSION` previews a release; `bin/release VERSION --execute` cuts it: bumps
  `.claude-plugin/plugin.json`, regenerates the changelog, tags, pushes, opens a GitHub
  Release. Don't hand-edit `CHANGELOG.md` or the manifest version directly.
- Only commit when asked — this repo has no pre-commit hooks enforcing any of the above.
