#!/usr/bin/env bash
set -euo pipefail

# Fork-only helper. Rebuilds local/patched from local/ci and the PR branches,
# then pushes it. The push triggers .github/workflows/local-build.yml.
#
# Usage:
#   scripts/update-local-build.sh             rebuild and push
#   scripts/update-local-build.sh --rebuild   push a local-build-* tag for the
#                                             current local/patched commit
#   SKIP_VERIFY=1 scripts/update-local-build.sh
#
# Never pushes to main.

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

BASE_BRANCH="${BASE_BRANCH:-local/ci}"
BUILD_BRANCH="${BUILD_BRANCH:-local/patched}"
REMOTE="${REMOTE:-fork}"
PATCHES=(nickname-exclude horizontal-sidebar)

if [[ "${1:-}" == "--rebuild" ]]; then
    if ! git rev-parse --verify --quiet "$BUILD_BRANCH" >/dev/null; then
        echo "error: $BUILD_BRANCH does not exist" >&2
        exit 1
    fi
    tag="local-build-$(date -u +%Y%m%d-%H%M%S)"
    git tag -f "$tag" "$BUILD_BRANCH"
    git push -f "$REMOTE" "$tag"
    exit 0
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "error: working tree is not clean" >&2
    exit 1
fi

git fetch origin --prune
git fetch "$REMOTE" --prune

git switch "$BASE_BRANCH"
git rebase origin/main

git switch -C "$BUILD_BRANCH" "$BASE_BRANCH"

for patch in "${PATCHES[@]}"; do
    echo "Merging $REMOTE/$patch"
    if ! git merge --no-edit "$REMOTE/$patch"; then
        conflicts="$(git diff --name-only --diff-filter=U)"
        if [[ "$conflicts" == "CHANGELOG.md" ]]; then
            echo "Keeping the integration branch CHANGELOG.md"
            git checkout --ours CHANGELOG.md
            git add CHANGELOG.md
            git commit --no-edit
        else
            echo "error: unexpected conflicts:" >&2
            echo "$conflicts" >&2
            git merge --abort || true
            exit 1
        fi
    fi
done

if [[ "${SKIP_VERIFY:-0}" != "1" ]]; then
    cargo fmt --all -- --check
    cargo check --workspace --all-targets
fi

git push --force-with-lease "$REMOTE" "$BASE_BRANCH" "$BUILD_BRANCH"

echo "Pushed $BUILD_BRANCH at $(git rev-parse --short HEAD)"
echo "CI: https://github.com/ransagy/halloy/actions/workflows/local-build.yml"
