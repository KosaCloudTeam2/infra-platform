#!/bin/bash
set -euo pipefail

npx @marp-team/marp-cli docs/presentation/presentation.md --pdf --allow-local-files
