#!/bin/sh
# Checks the ref -> chart version rule of deploy.yml's "Chart version" step.
# The rule is run straight from the workflow, between its marker comments.
# Usage: sh scripts/test-chart-version.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
wf="$here/../.github/workflows/deploy.yml"
rule=$(sed -n '/# chart-version-rule:begin/,/# chart-version-rule:end/s/^ *//p' "$wf")
case "$rule" in
  *chart-version-rule:begin*chart-version-rule:end*) ;;
  *) echo "FAIL markers chart-version-rule:begin/end not found in $wf"; exit 1 ;;
esac
fail=0
# $1 ref, $2 expected chart version, $3 expected app version, $4 1 if a warning is expected
run() {
  out=$(GITHUB_REF=$1 GITHUB_RUN_NUMBER=42 sh -c "$rule
echo \"chart_version=\$v app_version=\$app_version\"")
  got=$(printf '%s\n' "$out" | grep '^chart_version=' || true)
  want="chart_version=$2 app_version=$3"
  warned=0; printf '%s\n' "$out" | grep -q '^::warning::' && warned=1
  if [ "$got" != "$want" ] || [ "$warned" != "$4" ]; then
    echo "FAIL $1: got '$got' warning=$warned, want '$want' warning=$4"; fail=1
  else
    echo "ok   $1"
  fi
}

run refs/tags/v1.4.21     1.4.21     v1.4.21     0
run refs/tags/1.4.21      1.4.21     1.4.21      0
run refs/tags/v2.0.0-rc.1 2.0.0-rc.1 v2.0.0-rc.1 0
run refs/tags/release-7   1.0.42     ""          1
run refs/tags/v1.2.3+b5   1.0.42     ""          1
run refs/heads/stage      1.0.42-rc  ""          0
run refs/heads/dev        1.0.42-dev ""          0
run refs/heads/feat/x     1.0.42-dev ""          0

[ "$fail" = 0 ] && echo "all passed"
exit "$fail"
