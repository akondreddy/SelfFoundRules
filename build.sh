#!/usr/bin/env bash
set -e

# Read the version straight from the .toc so it can't drift
VERSION=$(grep '^## Version:' SelfFoundRules.toc | sed 's/.*: *//')

cd ..
rm -f "SelfFoundRules-v${VERSION}.zip"
zip -r "SelfFoundRules-v${VERSION}.zip" SelfFoundRules \
    -x '*.git*' '*.DS_Store' '*/notes/*' '*/notes/' '*/build.sh' '*/.vscode/*'

echo "Built SelfFoundRules-v${VERSION}.zip"
unzip -l "SelfFoundRules-v${VERSION}.zip"
