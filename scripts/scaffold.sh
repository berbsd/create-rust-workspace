#!/usr/bin/env bash
# =============================================================================
# scaffold.sh — generate a new project from rust-workspace-template
# =============================================================================
# Fetches rust-workspace-template (by default: a shallow clone of its latest
# git tag from GitHub) and copies it to a target directory, substituting the
# template's placeholder tokens with real values. Deterministic by design: no
# LLM judgment calls happen here, so a generated workspace is byte-for-byte
# reproducible from the same inputs and the same resolved template ref.
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
# --slug. --no-example removes the bundled example service/host. --git-init
# runs `git init` and an initial commit in the target directory.
#
# Template source (in priority order):
#   --template-dir LOCAL_PATH   Use this local checkout directly. Skips the
#                                network entirely — for testing the generator
#                                against an uncommitted/untagged template.
#                                --template-repo/--template-ref are ignored.
#   --template-repo URL         Where to clone from. Defaults to
#                                https://github.com/berbsd/rust-workspace-template.git.
#   --template-ref REF          Tag/branch/sha to clone. Defaults to the
#                                latest git tag on --template-repo, resolved
#                                via `git ls-remote`. If the repo has no tags
#                                and no ref was given explicitly, this is a
#                                hard error — pass e.g. `--template-ref main`
#                                rather than have this script silently guess.
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
KEEP_EXAMPLE=1
GIT_INIT=0
TEMPLATE_REPO="https://github.com/berbsd/rust-workspace-template.git"
TEMPLATE_REF=""
TEMPLATE_DIR_OVERRIDE=""

die() {
  echo "error: $1" >&2
  exit 1
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
    --no-example) KEEP_EXAMPLE=0; shift ;;
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

# =============================================================================
# Resolve the template source
# =============================================================================
if [[ -n "$TEMPLATE_DIR_OVERRIDE" ]]; then
  [[ ! -d "$TEMPLATE_DIR_OVERRIDE" ]] && die "--template-dir not found: $TEMPLATE_DIR_OVERRIDE"
  TEMPLATE_DIR="$TEMPLATE_DIR_OVERRIDE"
  echo ">>> Using local template at $TEMPLATE_DIR (skipping clone)"
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

  TMP_CLONE="$(mktemp -d)"
  trap 'rm -rf "$TMP_CLONE"' EXIT

  echo ">>> Cloning $TEMPLATE_REPO at $TEMPLATE_REF"
  git clone --quiet --depth 1 --branch "$TEMPLATE_REF" "$TEMPLATE_REPO" "$TMP_CLONE" \
    || die "failed to clone $TEMPLATE_REPO at ref '$TEMPLATE_REF'"
  TEMPLATE_DIR="$TMP_CLONE"
fi

echo ">>> Copying template to $TARGET"
mkdir -p "$TARGET"
if command -v rsync >/dev/null 2>&1; then
  # -a preserves permissions/timestamps; excludes keep build artifacts and
  # the template's own git history out of the new project.
  rsync -a --exclude='.git' --exclude='target' "$TEMPLATE_DIR/" "$TARGET/"
else
  # Trailing slash on the source copies contents, not the directory itself.
  cp -R "$TEMPLATE_DIR/" "$TARGET/"
  rm -rf "$TARGET/.git" "$TARGET/target"
fi

if [[ "$KEEP_EXAMPLE" -eq 0 ]]; then
  echo ">>> Removing bundled example service/host (--no-example)"
  rm -rf "$TARGET/services/example" "$TARGET/hosts/example-host"
  # Exact-match removal of the one workspace.dependencies line referencing it.
  grep -v '^example  *= { path = "services/example" }$' "$TARGET/Cargo.toml" > "$TARGET/Cargo.toml.tmp"
  mv "$TARGET/Cargo.toml.tmp" "$TARGET/Cargo.toml"

  # services/ and hosts/ are now empty. A `members` glob matching zero
  # directories fails the whole workspace (the template's own root Cargo.toml
  # comment documents this — it's the same reason jobs/ and workers/ have no
  # glob until their first member exists), so drop both the directories and
  # their glob entries together; add each back when the first service/host
  # lands.
  rmdir "$TARGET/services" "$TARGET/hosts" 2>/dev/null || true
  sed -i.bak 's/members  = \["crates\/\*", "hosts\/\*", "services\/\*"\]/members  = ["crates\/*"]/' "$TARGET/Cargo.toml"
  rm -f "$TARGET/Cargo.toml.bak"
fi

# =============================================================================
# Token substitution
# =============================================================================
# Every text file may contain any of these {{TOKEN}} placeholders.
#
# Deliberately not `grep -Z | xargs -0`: on a system where `grep` resolves to
# ugrep (common via Homebrew), `-Z` means `--decompress`, not "null-terminate
# output" — a silent behavior difference from GNU/BSD grep that corrupted
# every substitution the first time this ran. `find -print0` is unambiguous
# across find implementations, so the loop uses that instead.
substitute() {
  local token="$1" value="$2"
  local escaped
  escaped=$(printf '%s' "$value" | sed 's/[\/&]/\\&/g')
  while IFS= read -r -d '' file; do
    sed -i.bak "s/{{$token}}/$escaped/g" "$file"
  done < <(find "$TARGET" -type f -print0)
  find "$TARGET" -name '*.bak' -delete
}

echo ">>> Substituting template tokens"
substitute "PROJECT_NAME" "$PROJECT_NAME"
substitute "PROJECT_SLUG" "$PROJECT_SLUG"
substitute "METRIC_NAMESPACE" "$METRIC_NAMESPACE"
substitute "AUTHOR_NAME" "$AUTHOR_NAME"
substitute "AUTHOR_EMAIL" "$AUTHOR_EMAIL"
substitute "LICENSE" "$LICENSE"
substitute "REPO_URL" "$REPO_URL"

echo ">>> Pinning Rust toolchain to $RUST_VERSION"
# Three independent places pin a version, because neither Docker's FROM nor
# the CI action's toolchain step reads rust-toolchain.toml at that point —
# Docker's base-image tag is resolved before any repo file is even copied in,
# and the CI toolchain-install step runs before the checkout is guaranteed
# usable by rustup's auto-detection. All three get the same version here so
# they can never drift from each other or from the file a local
# `cargo +nightly fmt`/`cargo build` actually honors.
#
# Regex-matched against whatever concrete version the template currently
# ships (an X.Y.Z pattern), not a hardcoded literal — so this substitution
# never itself goes stale when the template's own shipped default is bumped.
# A channel already set to a floating value (`stable`/`nightly`/`beta`) is
# deliberately left alone: it has no version number to match, and this
# script does not decide to change that choice.
version_re='[0-9]+\.[0-9]+\.[0-9]+'
for f in "$TARGET/rust-toolchain.toml" "$TARGET/docker/Dockerfile" "$TARGET/.github/workflows/ci.yml"; do
  sed -i.bak -E \
    -e "s/channel    = \"$version_re\"/channel    = \"$RUST_VERSION\"/" \
    -e "s/FROM rust:$version_re-alpine3\.23/FROM rust:$RUST_VERSION-alpine3.23/" \
    -e "s/dtolnay\/rust-toolchain@$version_re/dtolnay\/rust-toolchain@$RUST_VERSION/g" \
    "$f"
  rm -f "$f.bak"
done

# Matches only this script's own token vocabulary — not a generic
# `{{...}}` scan, which also matches unrelated text like a Rust format
# string's `${{SERVICE}}` (its escape for a literal `${SERVICE}`).
remaining=$(grep -rlI -E '\{\{(PROJECT_NAME|PROJECT_SLUG|METRIC_NAMESPACE|AUTHOR_NAME|AUTHOR_EMAIL|LICENSE|REPO_URL)\}\}' "$TARGET" 2>/dev/null || true)
if [[ -n "$remaining" ]]; then
  echo "warning: unresolved template tokens remain in:" >&2
  echo "$remaining" >&2
fi

if [[ "$GIT_INIT" -eq 1 ]]; then
  echo ">>> git init"
  (cd "$TARGET" && git init -q && git add -A && git commit -q -m "chore: scaffold from rust-workspace-template")
fi

cat <<EOF

Done. $PROJECT_NAME scaffolded at $TARGET (template ref: ${TEMPLATE_REF:-local override})

Next steps:
  cd $TARGET
  ./bin/bootstrap.sh   # installs rustup toolchain, just, lefthook, taplo, typos
  just check            # format check, clippy, tests, typos, cargo-deny
EOF
