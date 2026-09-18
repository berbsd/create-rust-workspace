# create-rust-workspace

A Claude Code plugin that scaffolds a new Rust microservices Cargo workspace from
[rust-workspace-template](https://github.com/berbsd/rust-workspace-template).

## Install

```
/plugin marketplace add berbsd/create-rust-workspace
/plugin install create-rust-workspace@create-rust-workspace
```

## Use

Ask Claude Code to start a new Rust project — e.g. "start a new Rust microservices
workspace" or "scaffold a new Rust backend". The skill will ask for a project name, slug,
Rust version, author, license, repo URL, and whether to keep the bundled example
service, then generate the workspace.

## How it works

This repo contains only the generator (`SKILL.md` + `scripts/scaffold.sh`) — it does not
vendor a copy of the template. At generation time, `scaffold.sh` shallow-clones
`rust-workspace-template` from GitHub, by default pinned to its **latest release tag** (not
the default branch), then copies it into the target directory and substitutes the
project's values into the template's `{{TOKEN}}` placeholders.

See `scripts/scaffold.sh --help`-style usage comments at the top of the script for the full
flag list, including `--template-ref`/`--template-repo`/`--template-dir` for pinning to a
specific template version or testing against a local checkout.

## License

Licensed under the Apache License, Version 2.0 (the "License"); see [LICENSE](LICENSE).
