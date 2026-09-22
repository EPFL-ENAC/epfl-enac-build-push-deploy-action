#!/bin/sh
# Point an Argo overlay at new image digests and chart version, then commit
# it on main or open a PR. The one writer of the overlays: the Argo repos'
# update_manifest workflow and the GitLab build-push-deploy component both
# run this file, pinned by commit SHA. Needs curl, jq and yq v4.
#
#   GH_TOKEN             Contents write on TARGET_REPO (and Pull requests for PR mode)
#   TARGET_REPO          EPFL-ENAC/enack8s-app-config
#   OVERLAY              epfl/co2-calculator/overlays/dev/kustomization.yaml
#   IMAGES               JSON [{"name", "digest", "ref_name"}]; may be empty
#   LEGACY_DIGEST        payloads without IMAGES: digest for images[0]
#   LEGACY_REF_NAME      ... and its newTag (optional)
#   CHART_NAME, CHART_VERSION  optional, both or neither
#   MESSAGE              commit headline, PR title
#   CREATE_PULL_REQUEST  "true": commit on a new branch and open a PR
set -eu

API="https://api.github.com/repos/$TARGET_REPO"
MUTATION='mutation($repo:String!,$branch:String!,$headline:String!,$oid:GitObjectID!,$path:String!,$contents:Base64String!) {
  createCommitOnBranch(input: {branch: {repositoryNameWithOwner: $repo, branchName: $branch},
    message: {headline: $headline}, expectedHeadOid: $oid,
    fileChanges: {additions: [{path: $path, contents: $contents}]}}) { commit { url } } }'
work=$(mktemp -d)

api() { curl -fsS -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" "$@"; }

# $1 overlay file, edited in place
edit() {
  printf '%s' "${IMAGES:-}" | jq -c '.[]?' > "$work/images"
  matched=0
  while read -r image; do
    export N="$(echo "$image" | jq -r .name)" D="$(echo "$image" | jq -r .digest)" T="$(echo "$image" | jq -r .ref_name)"
    if [ "$(yq '[.images[] | select(.name == strenv(N))] | length' "$1")" = 0 ]; then
      echo "$N is not in $OVERLAY, skipped"; continue
    fi
    yq -i '(.images[] | select(.name == strenv(N))) |= (.digest = strenv(D) | .newTag = strenv(T))' "$1"
    matched=$((matched + 1))
  done < "$work/images"
  # a renamed image path would otherwise commit nothing and look deployed
  if [ -s "$work/images" ] && [ "$matched" = 0 ]; then
    echo "none of the images is in $OVERLAY: check their names" >&2; return 1
  fi
  if [ ! -s "$work/images" ] && [ -n "${LEGACY_DIGEST:-}" ]; then
    export D="$LEGACY_DIGEST" T="${LEGACY_REF_NAME:-}"
    yq -i '.images[0].digest = strenv(D)' "$1"
    [ -z "$T" ] || yq -i '.images[0].newTag = strenv(T)' "$1"
  fi
  if [ ! -s "$work/images" ] && [ -z "${LEGACY_DIGEST:-}" ] && [ -z "${CHART_VERSION:-}" ]; then
    echo "nothing to deploy: no images, no digest, no chart version" >&2; return 1
  fi
  [ -n "${CHART_VERSION:-}" ] || return 0
  export C="${CHART_NAME:?CHART_VERSION needs CHART_NAME}" V="$CHART_VERSION"
  # assigning through a missing helmCharts would add `helmCharts: []`
  if [ "$(yq '[.helmCharts[]? | select(.name == strenv(C))] | length' "$1")" = 0 ]; then
    echo "chart $C is not in $OVERLAY, skipped"; return 0
  fi
  yq -i '(.helmCharts[] | select(.name == strenv(C))).version = strenv(V)' "$1"
}

# $1 branch, $2 expected head; prints the commit URL
commit() {
  body=$(jq -n --arg q "$MUTATION" --arg repo "$TARGET_REPO" --arg branch "$1" --arg oid "$2" \
    --arg path "$OVERLAY" --arg msg "$MESSAGE" --arg c "$(jq -Rrs @base64 < "$work/k.yaml")" \
    '{query: $q, variables: {repo: $repo, branch: $branch, headline: $msg, oid: $oid, path: $path, contents: $c}}')
  # called from `if`, where set -e is off: check each step
  out=$(api -X POST https://api.github.com/graphql -d "$body") || return 1
  if [ -n "$(echo "$out" | jq -r '.errors // empty')" ]; then
    echo "rejected: $(echo "$out" | jq -c .errors)" >&2; return 1
  fi
  echo "$out" | jq -r .data.createCommitOnBranch.commit.url
}

for attempt in 1 2 3; do
  head=$(api "$API/git/ref/heads/main")
  head=$(echo "$head" | jq -r .object.sha)
  api "$API/contents/$OVERLAY?ref=$head" > "$work/content.json" \
    || { echo "cannot read $OVERLAY in $TARGET_REPO: app not onboarded, or token lacks access" >&2; exit 1; }
  jq -j '.content | gsub("\n"; "") | @base64d' "$work/content.json" > "$work/k.yaml"
  cp "$work/k.yaml" "$work/k.orig"
  edit "$work/k.yaml"
  # compare content, not text: yq -i may reformat a file it did not change
  if [ "$(yq -o=json -I=0 . "$work/k.orig")" = "$(yq -o=json -I=0 . "$work/k.yaml")" ]; then
    echo "$TARGET_REPO: $OVERLAY already up to date"; exit 0
  fi
  diff "$work/k.orig" "$work/k.yaml" || true

  if [ "${CREATE_PULL_REQUEST:-false}" = true ]; then
    branch="update-$(echo "$OVERLAY" | cut -d/ -f1,2,4 | tr / -)-$(date +%s)"
    api -X POST "$API/git/refs" -d "$(jq -n --arg r "refs/heads/$branch" --arg s "$head" '{ref: $r, sha: $s}')" > /dev/null
    commit "$branch" "$head" > /dev/null
    pr=$(api -X POST "$API/pulls" -d "$(jq -n --arg t "$MESSAGE" --arg h "$branch" \
      '{title: $t, head: $h, base: "main", body: "Opened by scripts/update-manifest.sh."}')")
    echo "$TARGET_REPO: opened $(echo "$pr" | jq -r .html_url)"; exit 0
  fi
  if url=$(commit main "$head"); then
    echo "$TARGET_REPO: committed $url"; exit 0
  fi
  echo "$TARGET_REPO: attempt $attempt rejected (main moved?)"
  sleep 1
done
echo "$TARGET_REPO: gave up after 3 attempts" >&2
exit 1
