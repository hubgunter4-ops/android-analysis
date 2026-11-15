#!/usr/bin/env bash
# build-local.sh — compilación manual de DeviceCrypt sin Gradle.
#
# El daemon de Gradle no arranca en esta VM (el cliente no lee el
# primer mensaje del daemon por el socket local), así que la APK debug
# se construye con las herramientas del SDK: aapt2 + javac + d8 +
# zipalign + apksigner. El job de CI (android-app) compila lo mismo
# con Gradle/AGP; esta vía solo existe para construir en local.
#
# Requisitos: JDK 17 y Android SDK con build-tools 34 y la plataforma
# android-35 (o 34, ajustando PLATFORM). La firma es con el keystore
# debug local (~/.android/debug.keystore, se crea si no existe).
# Salida: android-app/app-debug.apk
set -Eeuo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BT="${ANDROID_HOME:-$HOME/android/sdk}/build-tools/34.0.0"
AJ="${ANDROID_HOME:-$HOME/android/sdk}/platforms/android-35/android.jar"
JAVA_HOME="${JAVA_HOME:-$HOME/android/jdk17}"
export PATH="$JAVA_HOME/bin:$PATH"

WORK="$(mktemp -d /dev/shm/dcrypt.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/classes" "$WORK/dex"

"$BT/aapt2" compile --dir "$APP_DIR/app/src/main/res" -o "$WORK/compiled-res.zip"
"$BT/aapt2" link -o "$WORK/base.apk" -I "$AJ" \
    --manifest "$APP_DIR/app/src/main/AndroidManifest.xml" \
    --min-sdk-version 26 --target-sdk-version 34 \
    "$WORK/compiled-res.zip" --java "$WORK/gen" --auto-add-overlay
find "$APP_DIR/app/src/main/java" "$WORK/gen" -name "*.java" > "$WORK/sources.txt"
javac -encoding UTF-8 -source 17 -target 17 -cp "$AJ" -d "$WORK/classes" @"$WORK/sources.txt"
"$BT/d8" --output "$WORK/dex" --lib "$AJ" "$WORK/classes/com/zapia/devicecrypt/"*.class
cp "$WORK/base.apk" "$WORK/unsigned.apk"
(cd "$WORK/dex" && zip -q "$WORK/unsigned.apk" classes.dex)
"$BT/zipalign" -f 4 "$WORK/unsigned.apk" "$WORK/aligned.apk"
if [[ ! -f ~/.android/debug.keystore ]]; then
    mkdir -p ~/.android
    keytool -genkeypair -keystore ~/.android/debug.keystore -storepass android \
        -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 \
        -validity 10000 -dname "CN=Android Debug,O=Android,C=US" -noprompt
fi
"$BT/apksigner" sign --ks ~/.android/debug.keystore --ks-pass pass:android \
    --key-pass pass:android --ks-key-alias androiddebugkey \
    --out "$APP_DIR/app-debug.apk" "$WORK/aligned.apk"
"$BT/apksigner" verify "$APP_DIR/app-debug.apk"
ls -la "$APP_DIR/app-debug.apk"
sha256sum "$APP_DIR/app-debug.apk"
