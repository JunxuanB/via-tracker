#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mkdir -p build tmp
xcodebuild -project ios/VIATracker.xcodeproj -scheme VIATracker -configuration Release APNS_ENVIRONMENT=development -destination 'generic/platform=iOS' -archivePath build/VIATracker-Development.xcarchive -allowProvisioningUpdates archive > tmp/archive.log 2>&1
xcodebuild -exportArchive -archivePath build/VIATracker-Development.xcarchive -exportPath build/export -exportOptionsPlist ios/Configuration/ExportOptions.plist -allowProvisioningUpdates > tmp/export.log 2>&1
echo "Signed development IPA: build/export/VIATracker.ipa"
