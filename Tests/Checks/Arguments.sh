#!/bin/bash
# ABOUTME: Checks that the canonical check command rejects malformed invocations.
# ABOUTME: Exercises only help and invalid arguments without starting builds or tests.
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .build
reject() {
  if scripts/check "$@" > .build/check-cli-output.log 2>&1; then
    echo "Check CLI accepted invalid arguments: $*" >&2
    exit 1
  fi
  rg -q '^Usage: scripts/check' .build/check-cli-output.log
}
reject --help extra
reject --ci extra
reject --unknown
reject --ci --help
scripts/check --help > .build/check-cli-output.log
rg -q '^--ci:' .build/check-cli-output.log
echo 'Check CLI argument tests passed.'
