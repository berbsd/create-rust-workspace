# create-rust-workspace

A Claude Code plugin that scaffolds a new Rust microservices Cargo workspace from
[rust-workspace-template](https://github.com/berbsd/rust-workspace-template).

## Install

Run these as slash commands inside a Claude Code session (not in a regular shell):

```
/plugin marketplace add berbsd/create-rust-workspace
/plugin install create-rust-workspace@create-rust-workspace
```

Also requires [`cargo-generate`](https://github.com/cargo-generate/cargo-generate):
`cargo install cargo-generate --locked` (or `brew install cargo-generate`).

## Update

Run `/plugin marketplace update` **before** `/plugin update` — in testing, `/plugin
update` alone kept reinstalling the previously-cached version even after a new release
was live on GitHub; only refreshing the marketplace first picked up the new version:

```
/plugin marketplace update create-rust-workspace
/plugin update create-rust-workspace@create-rust-workspace
```

If it's still showing the old version afterward, restart Claude Code — plugin metadata
may be cached for a session's lifetime.

`/plugin list` shows what's currently installed (including version); `/plugin uninstall
create-rust-workspace@create-rust-workspace` removes it.

## Use

Ask Claude Code to start a new Rust project — e.g. "start a new Rust microservices
workspace" or "scaffold a new Rust backend". The skill will ask for a target folder,
project name, slug, Rust version, author, license, repo URL, and whether to initialize
git, then generate the workspace. The target folder is independent of the project
name/slug — it can be any path, but it must not already exist non-empty.

## How it works

This repo contains only the generator (`SKILL.md` + `scripts/scaffold.sh`) — it does not
vendor a copy of the template. At generation time, `scaffold.sh` resolves which version of
`rust-workspace-template` to use (by default, its **latest release tag**, not the default
branch — `cargo generate` has no "latest tag" concept of its own, so this script resolves
it via `git ls-remote` first), refuses if the target folder already exists and isn't
empty, then hands off to
[`cargo generate --init`](https://github.com/cargo-generate/cargo-generate) (run from
inside that folder — no subfolder is created, so the target's name has no required
relationship to the project's slug) for the actual clone, copy, and `{{TOKEN}}`
substitution. `rust-workspace-template` carries its own `cargo-generate.toml` and
`hooks/post.rhai`, which define the substitution rules, the Rust-toolchain version pin,
and the license-text fetch. `--init` ignores `cargo generate`'s own `--vcs` flag, so
`scaffold.sh` runs `git init`/`add`/`commit`/`remote add origin` itself when git-init is
requested.

See `scripts/scaffold.sh --help`-style usage comments at the top of the script for the full
flag list, including `--template-ref`/`--template-repo`/`--template-dir` for pinning to a
specific template version or testing against a local checkout.

## Releasing

`bin/release VERSION` previews a release (changelog, version bump, tag) without changing
anything; `bin/release VERSION --execute` cuts it for real — commits, tags, pushes, and
opens a GitHub Release with the new `CHANGELOG.md` section as its notes. Changelog entries
come from conventional commit messages via `git-cliff` (`.cliff.toml`).

## License

Licensed under the Apache License, Version 2.0 (the "License"); see [LICENSE](LICENSE).
