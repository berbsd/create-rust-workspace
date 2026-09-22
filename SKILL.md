---
name: create-rust-workspace
description: Use when the user wants to start a new Rust microservices project, workspace, or backend from scratch — scaffolding a new repo from rust-workspace-template. Triggers on "new rust project", "new rust workspace", "start a new service", "scaffold a rust backend", "create a new platform repo", or requests to generate a project from the rust-workspace-template.
---

# create-rust-workspace

Generates a new Rust microservices workspace from
[rust-workspace-template](https://github.com/berbsd/rust-workspace-template) (by default, its
latest tagged release) using [`cargo generate`](https://github.com/cargo-generate/cargo-generate).
The template bundles a `justfile`/`lefthook`/CI tooling stack, one shared library crate
(`common-types` — the API error envelope and keyset pagination), a minimal self-contained
example service + host built directly on `axum`/`sqlx`/`tokio` (no shared service framework —
see the template's own README for why), and a set of engineering-discipline Claude Code skills
(`rust-quality`, `rust-documenter`, and others).

Generation is deterministic — this skill's job is to collect the inputs, then hand off to
`scripts/scaffold.sh`, a thin wrapper that resolves which template version to use and then
calls `cargo generate` (which does the actual cloning, copying, and Liquid substitution —
`rust-workspace-template` carries its own `cargo-generate.toml` and `hooks/post.rhai` that
define how). Do not hand-copy or hand-edit template files yourself; the script exists
precisely so a generated workspace is reproducible from its inputs (including which template
version was used) rather than dependent on model judgment calls.

**Prerequisite:** `cargo-generate` must be installed (`cargo install cargo-generate --locked`,
or `brew install cargo-generate`). `scaffold.sh` checks for it and errors with the install
command if it's missing — if that happens, tell the user and ask before running the install
command yourself; it's a new global tool, not something to add silently.

## Steps

1. **Collect inputs — interactively, not as a checklist dump.** Never print the full
   list of fields below and ask the user to answer all of them in one reply; that's not
   interactive, it's a form. Instead:

   - **Ask directly, in one short message** (plain text — these are free-form, not a
     small option set): project name, author name and email, and repository URL (a
     placeholder like `https://github.com/you/repo` is fine if none exists yet). If the
     user's own request already gave one of these, don't re-ask it.
   - **Ask with `AskUserQuestion`** (real options, not prose) for:
     - **License** — options like `MIT`, `Apache-2.0`, `MIT OR Apache-2.0` (dual), and
       `UNLICENSED`, since `AskUserQuestion` always offers a custom "Other" slot for any
       other SPDX id or dual expression. The template fetches the real license text per
       id from GitHub's Licenses API at generation time (needs `gh` installed and
       authenticated — if it's missing or the id isn't one GitHub recognizes, generation
       still succeeds but no `LICENSE` file is written for that id; mention this to the
       user rather than silently treating it as done). "UNLICENSED" (npm's proprietary
       marker, not a real SPDX id) always falls into that no-file case.
     - **Keep the bundled example service?** — only ask if it's not obvious from the
       user's request (e.g. "start from a blank workspace" already answers it). Default
       to yes without asking otherwise; the example (`services/example` +
       `hosts/example-host`) demonstrates the service/host pattern end-to-end with a
       working CRUD resource and passing tests.
   - **Resolve the rest yourself and state what you chose — don't ask up front:**
     - **Slug**: derive from the project name (kebab-case). State it in your final
       report; only ask if the derived slug looks wrong or ambiguous. `cargo-generate`
       names the generated directory after the slug with no way to decouple the two (see
       `scaffold.sh`'s header comment) — the workspace **will** be created at
       `<parent>/<slug>`. If the user wants a differently-named directory, generate
       normally and rename it afterward — don't pass a mismatched `--target`;
       `scaffold.sh` rejects that outright.
     - **Target parent directory**: default to the current directory unless the user's
       request implies otherwise. `<parent>/<slug>` must not already exist.
     - **Rust toolchain version**: this is the `rust-toolchain.toml` channel (and, via
       `scaffold.sh`, also the Dockerfile's `FROM rust:` tag and both CI toolchain steps
       — all four stay in lockstep), not the Cargo edition (pinned to 2024 throughout;
       not reconfigured by this skill). **Default to the current latest stable Rust
       release**, resolved to a concrete version number — never pass the bare word
       `stable` to `scaffold.sh` (a floating channel defeats the reproducibility
       `rust-toolchain.toml` exists for). Resolve it, in order of preference:
       1. `rustc +stable --version` or `rustup check`, if `rustup`/`cargo` are available.
       2. A quick web check (e.g. the Rust blog's release announcements or
          `static.rust-lang.org/dist/channel-rust-stable.toml`) if available.
       3. Otherwise, tell the user you can't confirm the latest release and ask for one
          explicitly rather than guessing — a stale guess baked into every generated
          project's Dockerfile/CI is worse than asking.

       State the resolved version in your final report (e.g. "used 1.XX.0, today's
       latest stable") rather than silently assuming it with no mention at all.
     - **Metrics namespace**: defaults to the slug; only ask if it's likely to differ.
     - **Initialize git and make the first commit?**: default yes. Maps directly to
       `cargo generate`'s own `--vcs git`/`--vcs none`; the initial commit (when yes) is
       cargo-generate's own, not a custom message — there's no way to control its text.
     - **Template version**: only ask if the user explicitly wants something other than
       the latest tagged release (e.g. pinning to an older version, or tracking `main`
       for unreleased template changes). Otherwise `scaffold.sh` resolves the latest tag
       automatically and reports which one it used.

2. **Run the scaffold script**, using the plugin-provided path so it works regardless of
   where Claude Code installed this plugin:

   ```sh
   "${CLAUDE_PLUGIN_ROOT}/scripts/scaffold.sh" \
     --target "<parent dir>/<slug>" \
     --name "<project name>" \
     --slug "<slug>" \
     --author-name "<author name>" \
     --author-email "<author email>" \
     --license "<license>" \
     --repo-url "<repo url>" \
     --rust-version "<rust version>" \
     --metric-namespace "<metric namespace>" \
     [--template-ref "<template version, if the user asked for a non-default one>"] \
     [--no-example] \
     [--git-init]
   ```

   The script resolves which template ref to use (by default, `rust-workspace-template`'s
   latest git tag — `cargo generate` has no "latest tag" concept of its own), then hands
   everything else to `cargo generate --git ... --tag ... -d KEY=value ... --silent
   --allow-commands`: the clone, the copy, the `{{TOKEN}}` substitution, the
   keep-or-drop-the-example choice, and pinning the Rust toolchain version all live in
   `rust-workspace-template`'s own `cargo-generate.toml`/`hooks/post.rhai` now, not in this
   script. `--allow-commands` is required because that hook shells out to `sed` for the
   toolchain-pin substitution — this is the same template this plugin already trusted to run
   arbitrary shell commands before the cargo-generate migration, so the trust boundary hasn't
   changed. The script exits non-zero with a clear message on bad input (existing target,
   missing required field, malformed slug, mismatched target/slug basename, cargo-generate
   not installed, no tags found on the template repo). If `cargo generate` itself fails
   (e.g. "Substitution skipped, found invalid syntax in ..." or a Rhai hook error), that's a
   bug in the template, not something to patch around here — report the exact error to the
   user rather than hand-editing the generated output.

3. **Report the result**: the target path, which template version was used (the script's
   final output line states this), whether the example was kept, and the printed next steps
   (`./bin/bootstrap` then `just check`). Also state whatever you resolved automatically in
   step 1 instead of asking — slug, Rust version, git-init — so the user sees what was
   chosen on their behalf even though they were never asked. Don't run `bootstrap`/`just
   check` yourself unless the user asks — `bootstrap` installs system-level tooling
   (Homebrew casks, rustup components) and is a meaningfully impactful action to take
   unprompted.

## Notes

- This skill's job is generation, not template maintenance. If the user wants to change
  something about the *template itself* (add a crate, change a lint, port a different
  skill), that's a change to `rust-workspace-template` directly — out of scope here.
- `scaffold.sh` also supports `--template-dir LOCAL_PATH` and `--template-repo URL` for
  testing against a non-default template source; these aren't part of the normal
  user-facing flow and shouldn't be offered unless the user is explicitly working on the
  generator or template itself. `--template-dir` should point at a plain checkout, not a
  git worktree — see the flag's own comment in `scaffold.sh` for why.
- The generated directory's name is always the slug — `cargo generate` ties the two
  together with no override flag. Don't try to satisfy a request for a differently-named
  directory by passing a mismatched `--target`; generate normally, then `mv` it.
