---
name: create-rust-workspace
description: Use when the user wants to start a new Rust microservices project, workspace, or backend from scratch — scaffolding a new repo from rust-workspace-template. Triggers on "new rust project", "new rust workspace", "start a new service", "scaffold a rust backend", "create a new platform repo", or requests to generate a project from the rust-workspace-template.
---

# create-rust-workspace

Generates a new Rust microservices workspace from
[rust-workspace-template](https://github.com/berbsd/rust-workspace-template) (by default, its
latest tagged release) using [`cargo generate`](https://github.com/cargo-generate/cargo-generate).
The template bundles a `justfile`/`lefthook`/CI tooling stack, one shared library crate
(`common-types` — the API error envelope and keyset pagination), empty `services/`,
`hosts/`, `jobs/`, `workers/` directories scaffolded via the bundled `create-rust-service`
skill (no shared service framework — see the template's own README for why), and a set of
engineering-discipline Claude Code skills (`rust-quality`, `rust-documenter`, and others).

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

1. **Collect inputs — one question per message, waiting for a reply each time.**
   Never bundle multiple fields into one paragraph (e.g. "what's the project name,
   author, and repo URL?") and never print the full list of fields below as a
   checklist — both read as a form, not a conversation, and both have caused this
   skill to guess wrong when the user replied "go"/"yes" without addressing every
   field packed into one message. Two kinds of ask, plus values resolved without
   asking:

   - **Ask the free-form fields one at a time, each its own message, waiting for the
     reply before asking the next:** target folder; project name; author name; author
     email; repository URL (a placeholder like `https://github.com/you/repo` is fine if
     none exists yet); Rust toolchain version. The **target folder** is independent of
     the project name — don't derive one from the other, and don't assume the current
     directory without asking (default the *offer* to the current directory if that
     seems right, but still ask, since silently assuming it is exactly what caused this
     skill to scaffold into the wrong place before). It can be a name that has nothing
     to do with the project's display name or slug. If the user's own request already answered one of these,
     skip asking it — but don't fold two *unanswered* fields into the same message. For
     the Rust version specifically: this is the `rust-toolchain.toml` channel (and, via
     `scaffold.sh`, also the Dockerfile's `FROM rust:` tag and both CI toolchain steps —
     all four stay in lockstep), not the Cargo edition (pinned to 2024 throughout; not
     reconfigured by this skill). Resolve the current latest stable release *first* (in
     order of preference: `rustc +stable --version`/`rustup check` if available, else a
     quick web check against the Rust blog or
     `static.rust-lang.org/dist/channel-rust-stable.toml`, else tell the user you
     couldn't confirm it and ask them to supply one), then ask for confirmation by
     stating that resolved version as the default in its own message — never skip
     mentioning it, and never pass the bare word `stable` to `scaffold.sh` (a floating
     channel defeats the reproducibility `rust-toolchain.toml` exists for).
   - **Ask with one `AskUserQuestion` call, both questions together** (real options, not
     prose — and not split into separate calls or skipped as "obvious"):
     1. **License** — options like `MIT`, `Apache-2.0`, `MIT OR Apache-2.0` (dual), and
        `UNLICENSED`, since `AskUserQuestion` always offers a custom "Other" slot for any
        other SPDX id or dual expression. The template fetches the real license text per
        id from GitHub's Licenses API at generation time (needs `gh` installed and
        authenticated — if it's missing or the id isn't one GitHub recognizes,
        generation still succeeds but no `LICENSE` file is written for that id; mention
        this to the user rather than silently treating it as done). "UNLICENSED" (npm's
        proprietary marker, not a real SPDX id) always falls into that no-file case.
     2. **Initialize git and make the first commit?** — yes (recommended) / no. When
        yes, `scaffold.sh` runs `git init`/`add`/`commit` itself and adds `origin`
        pointing at the repo URL from step 1 (recorded only — never pushed, never
        checked for being real). Always ask this one — don't infer it and skip asking.
   - **Resolve the rest yourself and state what you chose in the final report — don't
     ask about these at all:**
     - **Slug**: derive from the project name (kebab-case); only ask if it looks wrong
       or ambiguous. This is unrelated to the target folder's name (see above) — it only
       feeds `cargo-generate`'s `--name` (the `project-name`/`crate_name` placeholders),
       nothing about the directory.
     - **Metrics namespace**: defaults to the slug; only ask if it's likely to differ.
     - **Template version**: only ask if the user explicitly wants something other than
       the latest tagged release (e.g. pinning to an older version, or tracking `main`
       for unreleased template changes). Otherwise `scaffold.sh` resolves the latest tag
       automatically and reports which one it used.

2. **Run the scaffold script**, using the plugin-provided path so it works regardless of
   where Claude Code installed this plugin:

   ```sh
   "${CLAUDE_PLUGIN_ROOT}/scripts/scaffold.sh" \
     --target "<target folder>" \
     --name "<project name>" \
     --slug "<slug>" \
     --author-name "<author name>" \
     --author-email "<author email>" \
     --license "<license>" \
     --repo-url "<repo url>" \
     --rust-version "<rust version>" \
     --metric-namespace "<metric namespace>" \
     [--template-ref "<template version, if the user asked for a non-default one>"] \
     [--git-init]
   ```

   `--target` is the exact folder from step 1 — it can be any path/name, with no
   required relationship to `--slug`.

   The script resolves which template ref to use (by default, `rust-workspace-template`'s
   latest git tag — `cargo generate` has no "latest tag" concept of its own), refuses if
   `--target` exists and is non-empty, then hands off to `cargo generate --init --git ...
   --tag ... -d KEY=value ... --silent --allow-commands` run from inside `--target`: the
   clone, the copy, the `{{TOKEN}}` substitution, pinning the Rust toolchain version, and
   fetching the chosen license's real text all live in `rust-workspace-template`'s own
   `cargo-generate.toml`/`hooks/post.rhai` now, not in this script. `--allow-commands` is
   required because that hook shells out to `sed`/`gh` for the toolchain-pin substitution
   and license fetch — this is the same template this plugin already trusted to run
   arbitrary shell commands before the cargo-generate migration, so the trust boundary
   hasn't changed. `--init` mode ignores `cargo generate`'s own `--vcs` flag entirely
   (verified), so `--git-init` makes this script run `git init`/`add`/`commit`/`remote
   add origin <repo-url>` itself afterward — `git remote add` only records the URL, it
   never pushes and never checks the URL is real. The script exits non-zero with a clear
   message on bad input (non-empty target, missing required field, malformed slug,
   cargo-generate not installed or too old, no tags found on the template repo). If
   `cargo generate` itself fails (e.g. "Substitution skipped, found invalid syntax in
   ..." or a Rhai hook error), that's a bug in the template, not something to patch
   around here — report the exact error to the user rather than hand-editing the
   generated output.

3. **Report the result**: the target path, which template version was used, and the
   "Next steps" lines — copy these from the script's own printed output verbatim
   (`./bin/bootstrap`, then `./bin/doctor`, then `just check`, then a `git push` line if
   `--git-init` was used); don't retype or paraphrase filenames from memory, since
   that's how a wrong name (e.g. "bootstrap.sh" — the actual file has no extension) or a
   dropped step creeps in. Also
   state whatever you resolved silently in step 1 without asking — slug, metrics
   namespace, template version — so the user sees what was chosen on their behalf. Don't
   run `bootstrap`/`doctor`/`just check` yourself unless the user asks — `bootstrap`
   installs system-level tooling (Homebrew casks, rustup components) and is a
   meaningfully impactful action to take unprompted.

## Notes

- This skill's job is generation, not template maintenance. If the user wants to change
  something about the *template itself* (add a crate, change a lint, port a different
  skill), that's a change to `rust-workspace-template` directly — out of scope here.
- `scaffold.sh` also supports `--template-dir LOCAL_PATH` and `--template-repo URL` for
  testing against a non-default template source; these aren't part of the normal
  user-facing flow and shouldn't be offered unless the user is explicitly working on the
  generator or template itself. `--template-dir` should point at a plain checkout, not a
  git worktree — see the flag's own comment in `scaffold.sh` for why.
- `--target` can be any folder — it has no required relationship to `--slug`. If it
  already exists and has anything in it at all, `scaffold.sh` refuses rather than
  merging into or overwriting what's there (`cargo generate --init`'s own behavior,
  verified empirically: it silently coexists with pre-existing files, so the emptiness
  check has to happen in this script).
