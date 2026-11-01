#!/usr/bin/env bash
# Builds a signed APK without Gradle: aapt2 -> javac -> d8 -> zipalign -> apksigner.
# Requires: JDK 17 (JAVA_HOME), Android SDK with build-tools;34.0.0 and platforms;android-34.
set -euo pipefail

: "${JAVA_HOME:?set JAVA_HOME to a JDK 17}"
: "${ANDROID_HOME:?set ANDROID_HOME to your Android SDK}"
BT="$ANDROID_HOME/build-tools/34.0.0"
AJAR="$ANDROID_HOME/platforms/android-34/android.jar"
PROJ="$(cd "$(dirname "$0")" && pwd)/app/src/main"
OUT="$(cd "$(dirname "$0")" && pwd)/build"
VERSION="${VERSION:-1.0.0}"
VCODE="${VCODE:-1}"

rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/classes" "$OUT/dex"

"$BT/aapt2" compile --dir "$PROJ/res" -o "$OUT/res.zip" --no-crunch
"$BT/aapt2" link -o "$OUT/base.apk" -I "$AJAR" \
  --manifest "$PROJ/AndroidManifest.xml" -R "$OUT/res.zip" -A "$PROJ/assets" \
  --java "$OUT/gen" --min-sdk-version 24 --target-sdk-version 34 \
  --version-code "$VCODE" --version-name "$VERSION" --auto-add-overlay

javac -nowarn -source 8 -target 8 -bootclasspath "$AJAR" -d "$OUT/classes" \
  $(find "$OUT/gen" "$PROJ/java" -name '*.java')

"$BT/d8" --release --min-api 24 --lib "$AJAR" --output "$OUT/dex" \
  $(find "$OUT/classes" -name '*.class')

python3 - "$OUT/base.apk" "$OUT/dex/classes.dex" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "a", zipfile.ZIP_DEFLATED) as z:
    z.write(sys.argv[2], "classes.dex")
PY

"$BT/zipalign" -f -p 4 "$OUT/base.apk" "$OUT/aligned.apk"

KS="${KEYSTORE:-$HOME/.glass-enhancer-release.keystore}"
if [ ! -f "$KS" ]; then
  echo "No keystore at $KS — creating one. Set KEYSTORE_PASS to control the password."
  PASS="${KEYSTORE_PASS:-$(head -c 18 /dev/urandom | base64 | tr -d '/+=')}"
  keytool -genkeypair -keystore "$KS" -alias glassenhancer -keyalg RSA -keysize 2048 \
    -validity 10000 -storepass "$PASS" -keypass "$PASS" \
    -dname "CN=Glass Enhancer 4K, OU=Apps, O=HubClue, C=IN"
  printf '%s' "$PASS" > "$KS.pass"
  echo "Keystore password saved to $KS.pass — keep both safe."
fi
PASS="${KEYSTORE_PASS:-$(cat "$KS.pass" 2>/dev/null || echo '')}"

"$BT/apksigner" sign --ks "$KS" --ks-key-alias glassenhancer \
  --ks-pass "pass:$PASS" --key-pass "pass:$PASS" \
  --v1-signing-enabled true --v2-signing-enabled true \
  --out "$OUT/GlassEnhancer4K-v$VERSION.apk" "$OUT/aligned.apk"

"$BT/apksigner" verify --print-certs "$OUT/GlassEnhancer4K-v$VERSION.apk" | head -3
echo "Built $OUT/GlassEnhancer4K-v$VERSION.apk"
