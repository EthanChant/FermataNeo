#!/bin/bash
# Builds build/FermataNeo.app (arm64, ad-hoc signed). Needs only the Command Line Tools.
# Calls swiftc directly, so it does not depend on SwiftPM or Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."

OBJ=build/obj
APP=build/FermataNeo.app
FLAGS=(-O -swift-version 5 -target arm64-apple-macos13.0 -I Sources/PowerSPI/include -I "$OBJ" -L "$OBJ")

rm -rf "$APP" "$OBJ"
mkdir -p "$OBJ" "$APP/Contents/MacOS" "$APP/Contents/Resources"

# XPC protocol shared by the app and the helper.
swiftc "${FLAGS[@]}" -parse-as-library -static -emit-library -emit-module \
    -module-name FermataNeoShared \
    -emit-module-path "$OBJ/FermataNeoShared.swiftmodule" \
    -o "$OBJ/libFermataNeoShared.a" \
    Sources/FermataNeoShared/*.swift

swiftc "${FLAGS[@]}" -lFermataNeoShared -module-name FermataNeo \
    -o "$APP/Contents/MacOS/FermataNeo" Sources/FermataNeo/*.swift

swiftc "${FLAGS[@]}" -lFermataNeoShared -module-name FermataNeoHelper \
    -o "$APP/Contents/MacOS/FermataNeoHelper" Sources/FermataNeoHelper/*.swift

cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns Resources/local.FermataNeo.Helper.plist Resources/install-helper.sh Resources/uninstall-helper.sh \
   "$APP/Contents/Resources/"

codesign --force --sign - --identifier local.FermataNeo.Helper "$APP/Contents/MacOS/FermataNeoHelper"
codesign --force --sign - "$APP"

echo "Built $APP"
