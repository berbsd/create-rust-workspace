# Changelog

All notable changes to this project will be documented in this file.

## [0.2.1] - 2026-09-22

### Bug Fixes

- Actually ask for Rust version, keep-example, and git-init

### Documentation

- Marketplace update must run before plugin update

## [0.2.0] - 2026-09-22

### Bug Fixes

- Stop the skill from dumping a 10-field checklist upfront

### Documentation

- Describe cargo-generate's license-fetch behavior in SKILL.md
- Add AGENTS.md
- Add plugin install/update instructions to README

### Features

- Generate workspaces via cargo-generate instead of hand-rolled sed
- Reject an unsupported cargo-generate version before generating

## [0.1.1] - 2026-09-18

### Bug Fixes

- Stale bin/bootstrap.sh reference, renamed to bootstrap

## [0.1.0] - 2026-09-18

### Features

- Initial create-rust-workspace generator plugin
- Add changelog support via git-cliff and bin/release

### Miscellaneous

- Add .envrc for direnv


