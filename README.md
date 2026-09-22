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

Claude Code checks marketplaces for updates periodically in the background, but to
update right away:

```
/plugin marketplace update create-rust-workspace
/plugin update create-rust-workspace@create-rust-workspace
```

`/plugin list` shows what's currently installed (including version); `/plugin uninstall
create-rust-workspace@create-rust-workspace` removes it.

## Use

Ask Claude Code to start a new Rust project — e.g. "start a new Rust microservices
workspace" or "scaffold a new Rust backend". The skill will ask for a project name, slug,
Rust version, author, license, repo URL, and whether to keep the bundled example
service, then generate the workspace. The generated directory is always named after the
slug — `cargo generate` ties the two together with no override.

## How it works

This repo contains only the generator (`SKILL.md` + `scripts/scaffold.sh`) — it does not
vendor a copy of the template. At generation time, `scaffold.sh` resolves which version of
`rust-workspace-template` to use (by default, its **latest release tag**, not the default
branch — `cargo generate` has no "latest tag" concept of its own, so this script resolves
it via `git ls-remote` first), then hands off to
[`cargo generate`](https://github.com/cargo-generate/cargo-generate) for the actual clone,
copy, and `{{TOKEN}}` substitution. `rust-workspace-template` carries its own
`cargo-generate.toml` and `hooks/post.rhai`, which define the substitution rules, the
keep-or-drop-the-example-service choice, and the Rust-toolchain version pin — this repo no
longer implements any of that itself.

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
