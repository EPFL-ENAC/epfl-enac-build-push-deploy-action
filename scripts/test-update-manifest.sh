#!/bin/sh
# Runs update-manifest.sh against a fake GitHub API: a `curl` first on PATH
# that answers from a fixture overlay and records every request. Needs jq
# and yq v4. Usage: sh scripts/test-update-manifest.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
fake=$(mktemp -d)
mkdir -p "$fake/bin"
cat > "$fake/bin/curl" <<'EOF'
#!/bin/sh
method=GET; url=""; data=""
while [ $# -gt 0 ]; do
  case "$1" in -X) method=$2; shift ;; -d) data=$2; shift ;; https://*) url=$1 ;; esac
  shift
done
n=$(wc -l < "$FAKE/calls" | tr -d ' ')
echo "$method $url" >> "$FAKE/calls"
[ -z "$data" ] || printf '%s' "$data" > "$FAKE/body-$n.json"
case "$method $url" in
  "GET "*/git/ref/heads/main) echo '{"object": {"sha": "head1"}}' ;;
  "GET "*/contents/*) [ -f "$FAKE/overlay.yaml" ] || exit 22
    jq -n --rawfile c "$FAKE/overlay.yaml" '{content: ($c | @base64)}' ;;
  "POST "*/git/refs) echo '{}' ;;
  "POST "*/pulls) echo '{"html_url": "https://example/pull/1"}' ;;
  "POST https://api.github.com/graphql")
    if [ -f "$FAKE/fail-once" ]; then rm "$FAKE/fail-once"; echo '{"errors": [{"message": "expectedHeadOid"}]}'; exit 0; fi
    echo '{"data": {"createCommitOnBranch": {"commit": {"url": "https://example/commit"}}}}' ;;
  *) echo "fake curl: unexpected $method $url" >&2; exit 22 ;;
esac
EOF
chmod +x "$fake/bin/curl"

overlay='images:
  - name: ghcr.io/org/app/frontend
    newTag: dev
    digest: sha256:old-frontend
  - name: ghcr.io/org/app/backend
    newTag: dev
    digest: sha256:old-backend
helmCharts:
  - name: app
    version: 1.0.1-dev
'
fail=0
# $1 name, $2 expected exit; the rest are VAR=value for the script
run() {
  name=$1; want=$2; shift 2
  rm -f "$fake"/calls "$fake"/body-*.json; : > "$fake/calls"
  got=0
  env -i PATH="$fake/bin:$PATH" HOME="$fake" FAKE="$fake" GH_TOKEN=t TARGET_REPO=EPFL-ENAC/argo \
    OVERLAY=org/app/overlays/dev/kustomization.yaml MESSAGE="update org/app (dev)" "$@" \
    sh "$here/update-manifest.sh" > "$fake/out" 2>&1 || got=$?
  if { [ "$want" = 0 ] && [ "$got" != 0 ]; } || { [ "$want" != 0 ] && [ "$got" = 0 ]; }; then
    echo "FAIL $name: exit $got, want $want"; sed 's/^/  /' "$fake/out"; fail=1; return 0
  fi
  echo "ok   $name"
}
committed() { jq -r '.variables.contents | @base64d' "$fake/body-$1.json"; }
check() { eval "$2" || { echo "FAIL $1"; sed 's/^/  /' "$fake/calls"; fail=1; }; }

printf '%s' "$overlay" > "$fake/overlay.yaml"
run "images + chart" 0 IMAGES='[{"name":"ghcr.io/org/app/frontend","digest":"sha256:new","ref_name":"dev"},{"name":"ghcr.io/org/app/docs","digest":"sha256:x","ref_name":"dev"}]' \
  CHART_NAME=app CHART_VERSION=1.0.9-dev
check "  commits frontend, skips docs, bumps chart" '[ "$(committed 2 | yq ".images[0].digest, .images[1].digest, .helmCharts[0].version" | tr "\n" " ")" = "sha256:new sha256:old-backend 1.0.9-dev " ] && grep -q "docs is not in" "$fake/out"'

run "legacy digest" 0 LEGACY_DIGEST=sha256:legacy LEGACY_REF_NAME=dev
check "  sets images[0]" '[ "$(committed 2 | yq ".images[0].digest")" = sha256:legacy ]'

run "no image matches" 1 IMAGES='[{"name":"ghcr.io/org/other","digest":"sha256:x","ref_name":"dev"}]'
check "  commits nothing" '! grep -q graphql "$fake/calls"'

run "nothing to deploy" 1 IMAGES='[]'

printf 'images:\n  - name: ghcr.io/org/app/frontend\n    digest: sha256:old\n' > "$fake/overlay.yaml"
run "chart-less overlay" 0 IMAGES='[{"name":"ghcr.io/org/app/frontend","digest":"sha256:new","ref_name":"dev"}]' \
  CHART_NAME=app CHART_VERSION=1.0.9-dev
check "  adds no helmCharts key" '[ "$(committed 2 | yq "has(\"helmCharts\")")" = false ]'

printf '%s' "$overlay" > "$fake/overlay.yaml"
run "already up to date" 0 IMAGES='[{"name":"ghcr.io/org/app/frontend","digest":"sha256:old-frontend","ref_name":"dev"}]'
check "  commits nothing" '! grep -q graphql "$fake/calls"'

touch "$fake/fail-once"
run "main moved once" 0 IMAGES='[{"name":"ghcr.io/org/app/backend","digest":"sha256:new","ref_name":"dev"}]'
check "  retries on a fresh head" '[ "$(grep -c graphql "$fake/calls")" = 2 ]'

run "pull request mode" 0 CREATE_PULL_REQUEST=true IMAGES='[{"name":"ghcr.io/org/app/backend","digest":"sha256:new","ref_name":"v1.0.0"}]'
check "  branch, commit on it, PR" 'grep -q "POST .*/git/refs" "$fake/calls" && grep -q "POST .*/pulls" "$fake/calls" && case "$(jq -r .variables.branch "$fake/body-3.json")" in update-org-app-dev-*) true ;; *) false ;; esac'

rm -rf "$fake"
[ "$fail" = 0 ] && echo "all passed"
exit "$fail"
