#!/bin/bash
# Sync audited code from private dev repo → public repo
# Usage: ./sync-public.sh
# The pre-push hook runs security audit automatically — push is blocked if issues found.

set -e
echo "Syncing to public repo..."
git push public main
echo "✅ Public repo updated: https://github.com/Mineshop007/kratos-mining-monitor"
