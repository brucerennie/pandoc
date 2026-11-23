#!/bin/sh
# Use the latest development version of a dependency from GitHub.
#
# Usage:  tools/usedev.sh REPO [SUBDIR...]
#
# REPO is a GitHub repository name, e.g. typst-hs (taken to be
# jgm/typst-hs) or owner/repo.  The latest commit on the default
# branch is looked up, and cabal.project and stack.yaml are updated
# to use it: the source-repository-package stanza(s) for the
# repository in cabal.project, and the git: entry in the extra-deps
# of stack.yaml, are replaced (or added if they don't exist).
#
# If SUBDIRs are given, they are used as the subdirs: in stack.yaml,
# and as the subdir: in cabal.project (one stanza for each).
#
# Any versioned extra-deps in stack.yaml for the packages provided
# by the repository are removed.  The packages are taken to be the
# SUBDIRs if given, otherwise the repository name minus any -hs suffix.

set -e

case "$1" in
  -h|--help)
    # Print the comment at the top of this file.
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
    exit 0 ;;
esac

if [ $# -lt 1 ]; then
  echo "Usage: $0 REPO [SUBDIR...]  (see --help)" >&2
  exit 1
fi

repo=$1
shift
case "$repo" in
  */*) ;;
  *) repo="jgm/$repo" ;;
esac
name=${repo#*/}
url="https://github.com/$repo.git"

# Disable credential helpers and prompts: no authentication is needed
# for public repositories, and GitHub asks for credentials when a
# repository doesn't exist.
commit=$(GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=false \
  git -c credential.helper= ls-remote "$url" HEAD | cut -f1)
if [ -z "$commit" ]; then
  echo "Could not get latest commit for $url" >&2
  exit 1
fi
echo "Latest commit for $repo is $commit"

subdirs="$*"
if [ -n "$subdirs" ]; then
  pkgs="$subdirs"
else
  pkgs=${name%-hs}
fi

topdir=$(cd "$(dirname "$0")/.." && pwd)
cabalproject="$topdir/cabal.project"
stackyaml="$topdir/stack.yaml"

# Shared awk function: normalize a repository URL for comparison.
normfun='
function norm(u) {
  sub(/^[ \t]+/, "", u); sub(/[ \t]+$/, "", u)
  sub(/^http:/, "https:", u); sub(/\/$/, "", u); sub(/\.git$/, "", u)
  return u
}'

# cabal.project: remove all top-level source-repository-package stanzas
# for the repository, and insert new ones where the first one was (or
# after the last top-level source-repository-package stanza, or at the
# end of the file).
cabalprog="$normfun"'
function stanzas(   i, n, sd, s) {
  n = split(subdirs, sd, " ")
  s = ""
  if (n == 0) {
    s = "source-repository-package\n  type: git\n  location: " url \
        "\n  tag: " commit "\n"
  }
  for (i = 1; i <= n; i++) {
    if (i > 1) s = s "\n"
    s = s "source-repository-package\n  type: git\n  location: " url \
          "\n  tag: " commit "\n  subdir: " sd[i] "\n"
  }
  return s
}
function flush(   i, ours, loc) {
  ours = 0
  for (i = 1; i <= nbuf; i++) {
    if (buf[i] ~ /^[ \t]+location:/) {
      loc = buf[i]
      sub(/^[ \t]+location:/, "", loc)
      if (norm(loc) == norm(url)) ours = 1
    }
  }
  if (ours) {
    if (!ins) { ins = nout + 1; removed = 1 }
    skipblank = 1
  } else {
    for (i = 1; i <= nbuf; i++) out[++nout] = buf[i]
    lastend = nout + 1
  }
  nbuf = 0
  instanza = 0
}
{
  if (instanza) {
    if ($0 ~ /^[ \t]+[^ \t]/) { buf[++nbuf] = $0; next }
    flush()
  }
  if ($0 ~ /^source-repository-package[ \t]*$/) {
    instanza = 1
    buf[++nbuf] = $0
    next
  }
  if (skipblank && $0 ~ /^[ \t]*$/) { skipblank = 0; next }
  skipblank = 0
  out[++nout] = $0
}
END {
  if (instanza) flush()
  block = stanzas()
  if (!ins) ins = lastend ? lastend : nout + 1
  for (i = 1; i <= nout + 1; i++) {
    if (i == ins) {
      if (removed) printf "%s\n", block
      else printf "\n%s", block
    }
    if (i <= nout) print out[i]
  }
}'

# stack.yaml: remove git/github entries for the repository and versioned
# entries for its packages from extra-deps, and insert a new git entry
# where the old one was (or where a removed versioned entry was, or at
# the beginning of extra-deps).
stackprog="$normfun"'
BEGIN {
  npkgs = split(pkgs, pkg, " ")
  nsd = split(subdirs, sd, " ")
}
function isversioned(line,   i, p) {
  for (i = 1; i <= npkgs; i++) {
    p = pkg[i]
    if (substr(line, 1, length(p) + 3) == "- " p "-" &&
        substr(line, length(p) + 4) ~ /^[0-9][0-9.]*([@ \t].*)?$/)
      return 1
  }
  return 0
}
{
  if (skipping) {
    if ($0 ~ /^  /) next
    skipping = 0
  }
  if ($0 ~ /^extra-deps:/) {
    out[++nout] = $0
    if (!extradeps) extradeps = nout + 1
    next
  }
  if ($0 ~ /^- git:/) {
    loc = $0
    sub(/^- git:/, "", loc)
    if (norm(loc) == norm(url)) {
      if (!gitins) gitins = nout + 1
      skipping = 1
      next
    }
  }
  if ($0 ~ /^- github:/) {
    loc = $0
    sub(/^- github:/, "", loc)
    if ("https://github.com/" norm(loc) == norm(url)) {
      if (!gitins) gitins = nout + 1
      skipping = 1
      next
    }
  }
  if (isversioned($0)) {
    if (!verins) verins = nout + 1
    next
  }
  out[++nout] = $0
}
END {
  block = "- git: " url "\n  commit: " commit "\n"
  if (nsd > 0) {
    block = block "  subdirs: ["
    for (i = 1; i <= nsd; i++) block = block (i > 1 ? ", " : "") sd[i]
    block = block "]\n"
  }
  ins = gitins ? gitins : (verins ? verins : extradeps)
  if (!ins) {
    out[++nout] = "extra-deps:"
    ins = nout + 1
  }
  for (i = 1; i <= nout + 1; i++) {
    if (i == ins) printf "%s", block
    if (i <= nout) print out[i]
  }
}'

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

awk -v url="$url" -v commit="$commit" -v subdirs="$subdirs" \
  "$cabalprog" "$cabalproject" > "$tmp"
cat "$tmp" > "$cabalproject"
echo "Updated $cabalproject"

awk -v url="$url" -v commit="$commit" -v subdirs="$subdirs" -v pkgs="$pkgs" \
  "$stackprog" "$stackyaml" > "$tmp"
cat "$tmp" > "$stackyaml"
echo "Updated $stackyaml"
