#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export PUB_CACHE="$project_root/.tooling/pub-cache"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
flutter_sdk=${PERSONAS_FLUTTER_SDK:-"$project_root/.tooling/flutter"}
if [ -x "$flutter_sdk/bin/flutter" ]; then
  flutter_executable="$flutter_sdk/bin/flutter"
else
  flutter_executable=$(command -v flutter)
fi
cd "$project_root/flutter_app"
case "${1:-}" in
  run|build)
    if [ -f .env ]; then
      exec "$flutter_executable" "$@" --dart-define-from-file=.env
    fi
    ;;
esac
exec "$flutter_executable" "$@"
