#!/usr/bin/env bash
# =============================================================================
# scaffold.sh — generate a new project from rust-workspace-template via
# cargo-generate
# =============================================================================
# rust-workspace-template now carries its own cargo-generate.toml and
# hooks/post.rhai, which do everything the old version of this script used to
# do by hand: cloning, copying, token substitution, the example-service
# on/off switch, and pinning the Rust toolchain version across the three
# files that need it. This script's only remaining job is the one thing
# cargo-generate has no equivalent for — resolving "latest tag" — plus
# translating this plugin's flags into `cargo generate`'s.
#
# Usage:
#   scaffold.sh --target DIR --name NAME --slug SLUG \
#     --author-name NAME --author-email EMAIL \
#     --license LICENSE --repo-url URL \
#     --rust-version VERSION [--metric-namespace NS] \
#     [--template-repo URL] [--template-ref REF] [--template-dir LOCAL_PATH] \
#     [--no-example] [--git-init]
#
# All of --target/--name/--slug/--author-name/--author-email/--license/
# --repo-url/--rust-version are required. --metric-namespace defaults to
# --slug. --no-example populates the template's `keep_example` placeholder
# with `false`. --git-init tells cargo-generate to run `git init` + an
# initial commit (`--vcs git`); without it, no VCS is initialized
# (`--vcs none`) — cargo-generate owns this now, so the initial commit
# message is cargo-generate's own, not this script's.
#
# --target's basename MUST equal --slug. cargo-generate names the directory
# it creates after `--name` (kebab-cased --slug) and has no flag to decouple
# the output directory's name from that value — see "Output Parameters" in
# `cargo generate --help`. If you need a differently-named directory, rename
# it after generation.
#
# Template source (in priority order), same semantics as before:
#   --template-dir LOCAL_PATH   Passed to `cargo generate --path`. Skips the
#                                network entirely — for testing the generator
#                                against an uncommitted/untagged template.
#                                --template-repo/--template-ref are ignored.
#                                Point this at a plain checkout, not a git
#                                worktree: `cargo generate --path` copies the
#                                directory as-is with no VCS handling, so a
#                                worktree's `.git` (a pointer file back to the
#                                main repo, not a real git dir) gets copied
#                                straight into the generated output — observed
#                                empirically, not something `--vcs none`
#                                cleans up since there was never a clone to
#                                skip. `--git`/`--template-repo` (the default,
#                                real-clone path) doesn't have this problem.
#   --template-repo URL         Passed to `cargo generate --git`. Defaults to
#                                https://github.com/berbsd/rust-workspace-template.git.
#   --template-ref REF          Passed to `cargo generate --tag` — despite
#                                the flag name, cargo-generate's --tag
#                                accepts branch names too (verified:
#                                `--tag main` resolves the same as
#                                `--branch main`), so a single flag covers
#                                both cases. Defaults to the latest git tag on
#                                --template-repo, resolved via `git
#                                ls-remote` (cargo-generate has no "latest
#                                tag" concept of its own). If the repo has no
#                                tags and no ref was given explicitly, this is
#                                a hard error — pass e.g. `--template-ref
#                                main` rather than have this script silently
#                                guess.
# =============================================================================

set -euo pipefail

TARGET=""
PROJECT_NAME=""
PROJECT_SLUG=""
AUTHOR_NAME=""
AUTHOR_EMAIL=""
LICENSE=""
REPO_URL=""
RUST_VERSION=""
METRIC_NAMESPACE=""
KEEP_EXAMPLE=true
GIT_INIT=0
TEMPLATE_REPO="https://github.com/berbsd/rust-workspace-template.git"
TEMPLATE_REF=""
TEMPLATE_DIR_OVERRIDE=""

# The oldest version this has actually been tested against — not researched
# as the theoretical minimum that first shipped typed/regex-validated
# placeholders, [conditional] sections, and Rhai hooks (rust-workspace-template
# relies on all three). Bump this only after testing against a newer floor.
MIN_CARGO_GENERATE_VERSION="0.25.0"

die() {
  echo "error: $1" >&2
  exit 1
}

# True (exit 0) if version $1 >= $2, comparing dot-separated numeric fields
# left to right. Not `sort -V`: portable across whatever `sort` a user's
# machine happens to have, no assumption that a modern GNU/BSD-with-version-sort
# build is what's on PATH.
version_ge() {
  local a="$1" b="$2"
  local -a a_parts b_parts
  IFS='.' read -r -a a_parts <<<"$a"
  IFS='.' read -r -a b_parts <<<"$b"
  for i in 0 1 2; do
    local x="${a_parts[i]:-0}" y="${b_parts[i]:-0}"
    ((10#$x > 10#$y)) && return 0
    ((10#$x < 10#$y)) && return 1
  done
  return 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --name) PROJECT_NAME="$2"; shift 2 ;;
    --slug) PROJECT_SLUG="$2"; shift 2 ;;
    --author-name) AUTHOR_NAME="$2"; shift 2 ;;
    --author-email) AUTHOR_EMAIL="$2"; shift 2 ;;
    --license) LICENSE="$2"; shift 2 ;;
    --repo-url) REPO_URL="$2"; shift 2 ;;
    --rust-version) RUST_VERSION="$2"; shift 2 ;;
    --metric-namespace) METRIC_NAMESPACE="$2"; shift 2 ;;
    --template-repo) TEMPLATE_REPO="$2"; shift 2 ;;
    --template-ref) TEMPLATE_REF="$2"; shift 2 ;;
    --template-dir) TEMPLATE_DIR_OVERRIDE="$2"; shift 2 ;;
    --no-example) KEEP_EXAMPLE=false; shift ;;
    --git-init) GIT_INIT=1; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -z "$TARGET" ]] && die "--target is required"
[[ -z "$PROJECT_NAME" ]] && die "--name is required"
[[ -z "$PROJECT_SLUG" ]] && die "--slug is required"
[[ -z "$AUTHOR_NAME" ]] && die "--author-name is required"
[[ -z "$AUTHOR_EMAIL" ]] && die "--author-email is required"
[[ -z "$LICENSE" ]] && die "--license is required"
[[ -z "$REPO_URL" ]] && die "--repo-url is required"
[[ -z "$RUST_VERSION" ]] && die "--rust-version is required"
[[ -z "$METRIC_NAMESPACE" ]] && METRIC_NAMESPACE="$PROJECT_SLUG"

[[ ! "$PROJECT_SLUG" =~ ^[a-z][a-z0-9-]*$ ]] && die "--slug must be lowercase kebab-case (e.g. 'acme')"
[[ -e "$TARGET" ]] && die "target already exists: $TARGET"

TARGET_PARENT="$(dirname -- "$TARGET")"
TARGET_BASENAME="$(basename -- "$TARGET")"
[[ "$TARGET_BASENAME" != "$PROJECT_SLUG" ]] && die \
  "--target's basename ('$TARGET_BASENAME') must equal --slug ('$PROJECT_SLUG') — cargo-generate names the generated directory after --slug and has no flag to decouple the two. Generate at .../$PROJECT_SLUG, then rename afterward if you need a different directory name."

command -v cargo-generate >/dev/null 2>&1 \
  || die "cargo-generate is not installed — run: cargo install cargo-generate --locked"

CARGO_GENERATE_VERSION=$(cargo generate --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[[ -z "$CARGO_GENERATE_VERSION" ]] && die \
  "couldn't parse a version out of 'cargo generate --version' — is cargo-generate installed correctly?"
version_ge "$CARGO_GENERATE_VERSION" "$MIN_CARGO_GENERATE_VERSION" || die \
  "cargo-generate $CARGO_GENERATE_VERSION is installed, but rust-workspace-template needs >= $MIN_CARGO_GENERATE_VERSION (typed/regex-validated placeholders, [conditional] sections, Rhai hooks) — run: cargo install cargo-generate --locked --force"

mkdir -p "$TARGET_PARENT"

# =============================================================================
# Resolve the template source
# =============================================================================
CARGO_GENERATE_ARGS=()

if [[ -n "$TEMPLATE_DIR_OVERRIDE" ]]; then
  [[ ! -d "$TEMPLATE_DIR_OVERRIDE" ]] && die "--template-dir not found: $TEMPLATE_DIR_OVERRIDE"
  echo ">>> Using local template at $TEMPLATE_DIR_OVERRIDE (skipping clone)"
  CARGO_GENERATE_ARGS+=(--path "$TEMPLATE_DIR_OVERRIDE")
  RESOLVED_REF="local override"
else
  if [[ -z "$TEMPLATE_REF" ]]; then
    echo ">>> Resolving latest tag on $TEMPLATE_REPO"
    TEMPLATE_REF=$(git ls-remote --tags --sort='-v:refname' "$TEMPLATE_REPO" 2>/dev/null \
      | awk '{print $2}' \
      | grep -v '\^{}$' \
      | sed 's#^refs/tags/##' \
      | head -1) || true
    # The pipeline above legitimately exits non-zero when the repo has no
    # tags (grep/head see no input) — `|| true` stops that from tripping
    # `set -e` before the check below gets to run.
    [[ -z "$TEMPLATE_REF" ]] && die "no tags found on $TEMPLATE_REPO — pass --template-ref explicitly (e.g. main)"
    echo ">>> Latest tag: $TEMPLATE_REF"
  fi
  CARGO_GENERATE_ARGS+=(--git "$TEMPLATE_REPO" --tag "$TEMPLATE_REF")
  RESOLVED_REF="$TEMPLATE_REF"
fi

CARGO_GENERATE_ARGS+=(
  --name "$PROJECT_SLUG"
  --destination "$TARGET_PARENT"
  --silent
  # rust-workspace-template's post-generation hook shells out to `sed` to pin
  # the Rust toolchain version (and, with --no-example, trim Cargo.toml) —
  # see that repo's hooks/post.rhai for why. This is the same template this
  # plugin already trusted to run arbitrary sed/rsync before the
  # cargo-generate migration; the trust boundary hasn't changed, only where
  # the substitution logic lives.
  --allow-commands
  -d "PROJECT_NAME=$PROJECT_NAME"
  -d "AUTHOR_NAME=$AUTHOR_NAME"
  -d "AUTHOR_EMAIL=$AUTHOR_EMAIL"
  -d "LICENSE=$LICENSE"
  -d "REPO_URL=$REPO_URL"
  -d "METRIC_NAMESPACE=$METRIC_NAMESPACE"
  -d "RUST_VERSION=$RUST_VERSION"
  -d "keep_example=$KEEP_EXAMPLE"
)

if [[ "$GIT_INIT" -eq 1 ]]; then
  CARGO_GENERATE_ARGS+=(--vcs git)
else
  CARGO_GENERATE_ARGS+=(--vcs none)
fi

echo ">>> Running cargo generate"
cargo generate "${CARGO_GENERATE_ARGS[@]}"

cat <<EOF

Done. $PROJECT_NAME scaffolded at $TARGET (template ref: $RESOLVED_REF)

Next steps:
  cd $TARGET
  ./bin/bootstrap       # installs rustup toolchain, just, lefthook, taplo, typos
  just check            # format check, clippy, tests, typos, cargo-deny
EOF
