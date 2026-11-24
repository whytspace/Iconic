#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/release.sh

Creates a local release commit and annotated tag with the next version number
(v1, v2, v3, ...).

The script does not push. Publish with:
  git push origin main
  git push origin vN
EOF
}

die() {
  echo "release: $*" >&2
  exit 1
}

case "${1:-}" in
  "") ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac

toc="Iconic.toc"
data_toc="Iconic_Data/Iconic_Data.toc"
changelog="CHANGELOG.md"

[ -f "$toc" ] || die "missing $toc"
[ -f "$changelog" ] || die "missing $changelog"

branch="$(git branch --show-current)"
[ "$branch" = "main" ] || die "releases must be cut from main, not $branch"

status="$(git status --porcelain)"
[ -z "$status" ] || die "worktree must be clean before cutting a release"

current_version="$(awk -F': *' '/^## Version:/ { print $2; exit }' "$toc")"
# A leading major from the old X.Y.Z scheme counts as the previous number.
[[ "$current_version" =~ ^([0-9]+)(\.[0-9]+\.[0-9]+)?$ ]] || die "expected a numeric ## Version in $toc, got '$current_version'"

version="$((BASH_REMATCH[1] + 1))"
tag="v$version"
today="$(date +%Y-%m-%d)"

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  die "tag $tag already exists"
fi

# Warn (don't block) when the Unreleased section has no notes: such a release
# ships only a maintenance placeholder to CurseForge. Done before any file is
# mutated so aborting leaves the worktree untouched.
unreleased="$(awk '
  /^## Unreleased[[:space:]]*$/ { grab = 1; next }
  grab && /^## / { exit }
  grab { print }
' "$changelog")"
if [ -z "$(printf '%s' "$unreleased" | tr -d '[:space:]')" ]; then
  echo "release: warning — '## Unreleased' has no notes; $tag will ship as a maintenance release." >&2
  printf 'release: continue anyway? [y/N] ' >&2
  read -r reply
  case "$reply" in
    y | Y | yes | YES) ;;
    *) die "aborted; add notes under '## Unreleased' first" ;;
  esac
fi

devc luacheck .
devc busted
devc stylua --check .

toc_tmp="$(mktemp "$toc.XXXXXX")"
if ! awk -v version="$version" '
  BEGIN { updated = 0 }
  /^## Version:/ && updated == 0 {
    print "## Version: " version
    updated = 1
    next
  }
  { print }
  END { if (updated == 0) exit 1 }
' "$toc" >"$toc_tmp"; then
  rm -f "$toc_tmp"
  die "could not update $toc"
fi
mv "$toc_tmp" "$toc"
sed -i.bak "s/^## Version: .*/## Version: $version/" "$data_toc" && rm -f "$data_toc.bak"

changelog_tmp="$(mktemp "$changelog.XXXXXX")"
if ! awk -v version="$version" -v today="$today" '
  BEGIN { updated = 0 }
  /^## Unreleased[[:space:]]*$/ && updated == 0 {
    print
    print ""
    print "## v" version " - " today
    updated = 1
    next
  }
  { print }
  END { if (updated == 0) exit 1 }
' "$changelog" >"$changelog_tmp"; then
  rm -f "$changelog_tmp"
  die "could not find '## Unreleased' in $changelog"
fi
mv "$changelog_tmp" "$changelog"

git add "$toc" "$data_toc" "$changelog"
if git diff --cached --quiet; then
  die "release produced no version or changelog changes"
fi

git commit -m "chore: release $tag"
git tag -a "$tag" -m "$tag"

cat <<EOF
Created release commit and tag locally: $tag

Publish with:
  git push origin main
  git push origin $tag
EOF
