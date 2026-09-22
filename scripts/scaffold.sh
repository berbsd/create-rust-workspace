#!/usr/bin/env bash
# =============================================================================
# scaffold.sh — generate a new project from rust-workspace-template via
# cargo-generate
# =============================================================================
# rust-workspace-template now carries its own cargo-generate.toml and
# hooks/post.rhai, which do everything the old version of this script used to
# do by hand: cloning, copying, token substitution, and pinning the Rust
# toolchain version across the three files that need it. This script's
# remaining jobs are the ones cargo-generate has no equivalent for —
# resolving "latest tag", refusing a non-empty target directory, and (since
# `--init` ignores `--vcs` entirely — verified empirically) running `git
# init` itself — plus translating this plugin's flags into `cargo
# generate`'s.
#
# Usage:
#   scaffold.sh --target DIR --name NAME --slug SLUG \
#     --author-name NAME --author-email EMAIL \
#     --license LICENSE --repo-url URL \
#     --rust-version VERSION [--metric-namespace NS] \
#     [--template-repo URL] [--template-ref REF] [--template-dir LOCAL_PATH] \
#     [--git-init]
#
# All of --target/--name/--slug/--author-name/--author-email/--license/
# --repo-url/--rust-version are required. --metric-namespace defaults to
# --slug.
#
# --target is the exact directory the workspace is generated into — it has
# no required relationship to --slug (a project can live in a folder named
# anything). If --target doesn't exist, it's created. If it exists and is
# NOT EMPTY, this script refuses rather than merging into or overwriting
# whatever's there — cargo-generate's own `--init` mode does neither check
# (verified empirically: it silently coexists with pre-existing files), so
# the check has to happen here.
#
# --git-init runs `git init` + an initial commit after a successful
# generation. This is NOT cargo-generate's own `--vcs git` — `--init` mode
# ignores `--vcs` unconditionally (verified: no `.git` appears even when
# `--vcs git` is passed alongside `--init`), so this script does it by hand.
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
#                                empirically, not something this script's own
#                                git-init cleans up since there was never a
#                                clone to skip. `--git`/`--template-repo` (the
#                                default, real-clone path) doesn't have this
#                                problem.
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

if [[ -e "$TARGET" ]]; then
  [[ -d "$TARGET" ]] || die "target exists and is not a directory: $TARGET"
  [[ -n "$(ls -A "$TARGET" 2>/dev/null)" ]] && die "target directory is not empty: $TARGET"
fi

command -v cargo-generate >/dev/null 2>&1 \
  || die "cargo-generate is not installed — run: cargo install cargo-generate --locked"

CARGO_GENERATE_VERSION=$(cargo generate --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[[ -z "$CARGO_GENERATE_VERSION" ]] && die \
  "couldn't parse a version out of 'cargo generate --version' — is cargo-generate installed correctly?"
version_ge "$CARGO_GENERATE_VERSION" "$MIN_CARGO_GENERATE_VERSION" || die \
  "cargo-generate $CARGO_GENERATE_VERSION is installed, but rust-workspace-template needs >= $MIN_CARGO_GENERATE_VERSION (typed/regex-validated placeholders, [conditional] sections, Rhai hooks) — run: cargo install cargo-generate --locked --force"

mkdir -p "$TARGET"

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
  --init
  --name "$PROJECT_SLUG"
  --silent
  # rust-workspace-template's post-generation hook shells out to `sed`/`gh`
  # to pin the Rust toolchain version and fetch license text — see that
  # repo's hooks/post.rhai for why. This is the same template this plugin
  # already trusted to run arbitrary sed/rsync before the cargo-generate
  # migration; the trust boundary hasn't changed, only where the
  # substitution logic lives.
  --allow-commands
  -d "PROJECT_NAME=$PROJECT_NAME"
  -d "AUTHOR_NAME=$AUTHOR_NAME"
  -d "AUTHOR_EMAIL=$AUTHOR_EMAIL"
  -d "LICENSE=$LICENSE"
  -d "REPO_URL=$REPO_URL"
  -d "METRIC_NAMESPACE=$METRIC_NAMESPACE"
  -d "RUST_VERSION=$RUST_VERSION"
)

echo ">>> Running cargo generate"
(cd "$TARGET" && cargo generate "${CARGO_GENERATE_ARGS[@]}")

PUSH_STEP=""
if [[ "$GIT_INIT" -eq 1 ]]; then
  echo ">>> git init"
  (cd "$TARGET" && git init -q && git add -A && git commit -q -m "chore: scaffold from rust-workspace-template" \
    && git remote add origin "$REPO_URL")
  # git remote add only records the URL — it never pushes, and never checks
  # the URL is real (a placeholder like https://github.com/you/repo is
  # recorded exactly as happily as a real one), so pushing is always a
  # separate, explicit step for the user to take once the remote is real.
  PUSH_STEP="  git push -u origin \$(git branch --show-current)  # once $REPO_URL is a real, empty repo"
fi

cat <<EOF

Done. $PROJECT_NAME scaffolded at $TARGET (template ref: $RESOLVED_REF)

Next steps:
  cd $TARGET
  ./bin/bootstrap       # installs rustup toolchain, just, lefthook, taplo, typos
  ./bin/doctor          # confirms everything installed cleanly and is up to date
  just check            # format check, clippy, tests, typos, cargo-deny
$PUSH_STEP
EOF
