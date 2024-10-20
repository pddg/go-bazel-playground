#!/bin/bash
set -e

# Calculate version
VERSION_WITH_HASH=$(git describe \
  --tags \
  --long \
  --match="[0-9][0-9][0-9][0-9].[0-9][0-9]" \
  | sed -e 's/-/./;s/-g/+/')

# Show version with git hash
echo "VERSION_WITH_HASH ${VERSION_WITH_HASH}"
# Show version only
echo "VERSION $(echo ${VERSION_WITH_HASH} | cut -d+ -f1)"
# Show git hash only
echo "GIT_SHA $(echo ${VERSION_WITH_HASH} | cut -d+ -f2)"

BUILD_TIMESTAMP=${BUILD_TIMESTAMP:-$(date +%s)}

# Show build timestamp in ISO8601 format
if [ "$(uname)" == "Darwin" ]; then
  BUILD_ISO8601=$(date -u -r "$BUILD_TIMESTAMP" +"%Y-%m-%dT%H:%M:%SZ")
else
  BUILD_ISO8601=$(date -u -d "@$BUILD_TIMESTAMP" +"%Y-%m-%dT%H:%M:%SZ")
fi
echo "BUILD_TIMESTAMP_ISO8601 $BUILD_ISO8601"
