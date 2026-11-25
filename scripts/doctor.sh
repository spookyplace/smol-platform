#!/usr/bin/env bash
# Checks installed tools against the rules in versions.env. Installs nothing.
# Portable to macOS bash 3.2: no associative arrays, no GNU-only flags.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=versions.env
. "$ROOT/versions.env"

failed=0

# First x.y or x.y.z found on stdin.
ver() { grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1; }
major() { echo "${1%%.*}"; }
minor() { local r="${1#*.}"; echo "${r%%.*}"; }

# ver_ge A B: true if version A >= B.
ver_ge() {
  local i x y
  local -a a b
  IFS=. read -r -a a <<< "$1"
  IFS=. read -r -a b <<< "$2"
  for i in 0 1 2; do
    x="${a[i]:-0}"; y="${b[i]:-0}"
    if (( x > y )); then return 0; fi
    if (( x < y )); then return 1; fi
  done
  return 0
}

# report NAME LEVEL PASSED GOT RULE
#   LEVEL: now (fails the run) or later (needed in a later phase; reported, never fails)
#   PASSED: yes or no
report() {
  local name="$1" level="$2" passed="$3" got="${4:-missing}" rule="$5" status
  if [ "$passed" = yes ]; then status=ok
  elif [ "$level" = later ]; then status=later
  else status=FAIL; failed=1
  fi
  printf '  %-6s %-11s %-12s %s\n' "$status" "$name" "$got" "$rule"
}

passed_if() { if "$@"; then echo yes; else echo no; fi; }
same_major() { [ -n "$1" ] && [ "$(major "$1")" = "$2" ]; }
same_minor() { [ -n "$1" ] && [ "$(major "$1").$(minor "$1")" = "$(major "$2").$(minor "$2")" ]; }

echo "Checking tools against versions.env"
printf '  %-6s %-11s %-12s %s\n' STATUS TOOL INSTALLED RULE

# Docker: query the server, so this also catches a stopped daemon or missing docker group.
if command -v docker >/dev/null 2>&1; then
  got="$(docker version --format '{{.Server.Version}}' 2>/dev/null)"
  if [ -z "$got" ]; then
    report docker now no "no-daemon" "daemon unreachable: is it running, and are you in the docker group?"
  else
    report docker now "$(passed_if ver_ge "$got" "$DOCKER_MIN_VERSION")" "$got" ">= $DOCKER_MIN_VERSION"
  fi
else
  report docker now no "" ">= $DOCKER_MIN_VERSION"
fi

got="$(k3d version 2>/dev/null | ver)"
report k3d now "$(passed_if same_major "$got" "$K3D_MAJOR")" "$got" "major $K3D_MAJOR"

cluster="$(printf '%s' "$K3S_IMAGE" | ver)"
got="$(kubectl version --client 2>/dev/null | ver)"
kubectl_ok() {
  [ -n "$got" ] && [ "$(major "$got")" = "$(major "$cluster")" ] || return 1
  local d=$(( $(minor "$got") - $(minor "$cluster") ))
  (( d < 0 )) && d=$(( -d ))
  (( d <= KUBECTL_MAX_SKEW ))
}
report kubectl now "$(passed_if kubectl_ok)" "$got" "within ±$KUBECTL_MAX_SKEW minor of cluster $cluster"

got="$(helm version --short 2>/dev/null | ver)"
report helm now "$(passed_if same_major "$got" "$HELM_MAJOR")" "$got" "major $HELM_MAJOR"

got="$(argocd version --client --short 2>/dev/null | ver)"
report argocd now "$(passed_if same_minor "$got" "$ARGOCD_VERSION")" "$got" "same minor as server $ARGOCD_VERSION"

got="$(gh --version 2>/dev/null | ver)"
report gh now "$(passed_if ver_ge "${got:-0}" "$GH_MIN_VERSION")" "$got" ">= $GH_MIN_VERSION"

got="$(node --version 2>/dev/null | ver)"
report node now "$(passed_if same_major "$got" "$NODE_MAJOR")" "$got" "major $NODE_MAJOR"

# Corepack must be installed and enabled (enable creates the yarn shim).
got="$(corepack --version 2>/dev/null | ver)"
corepack_ok() { [ -n "$got" ] && command -v yarn >/dev/null 2>&1; }
report corepack now "$(passed_if corepack_ok)" "$got" "installed, and 'corepack enable' run"

got="$(crossplane version --client 2>/dev/null | ver)"
report crossplane later "$(passed_if same_minor "$got" "$CROSSPLANE_VERSION")" "$got" "same minor as server $CROSSPLANE_VERSION (Phase 3)"

got="$(aws --version 2>&1 | ver)"
report aws later "$(passed_if same_major "$got" "$AWSCLI_MAJOR")" "$got" "major $AWSCLI_MAJOR (Phase 3)"

if [ "$failed" -ne 0 ]; then
  echo "doctor: FAILED. See README prerequisites."
  exit 1
fi
echo "doctor: all required tools OK"
