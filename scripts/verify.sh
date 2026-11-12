#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
mkdir -p tmp
(cd packages/TrackerCore && swift test) > tmp/swift-tests.log 2>&1
(cd backend && npm run check && npm test) > tmp/backend-tests.log 2>&1
xcodebuild -project ios/VIATracker.xcodeproj -scheme VIATracker -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build > tmp/build-simulator.log 2>&1
echo "Swift, API contract/domain tests, and simulator build passed. Logs: tmp/"
