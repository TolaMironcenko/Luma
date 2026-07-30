#!/usr/bin/env bash
set -euo pipefail

exec "$(dirname "$0")/Scripts/regenerate-project.command"
