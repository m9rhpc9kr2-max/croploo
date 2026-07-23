#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/website"
firebase deploy --only hosting --project croploo-website
