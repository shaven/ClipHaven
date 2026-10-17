#!/bin/bash
# The test entry point gt's checks look for; runs the Swift package's tests.
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
