#!/bin/bash -eu
set -e
source env.sh

#todo
export COMMAND_DIR="$(pwd)/com.unity.webrtc/BuildScripts~"
export WEBRTC_VERSION=5845
export PLATFORM_DIR_NAME="android"
export UWEBRTC_DIR="$(pwd)/com.unity.webrtc"
export PATH="${UWEBRTC_DIR}/depot_tools:$PATH"
export ARTIFACTS_DIR="${UWEBRTC_DIR}/artifacts/${PLATFORM_DIR_NAME}"
export WEBRTC_DIR="$(pwd)/src"

# Add jsoncpp
patch -N "src/BUILD.gn" < "$COMMAND_DIR/patches/add_jsoncpp.patch"

# Add visibility libunwind
patch -N "src/buildtools/third_party/libunwind/BUILD.gn" < "$COMMAND_DIR/patches/add_visibility_libunwind.patch"

# Add deps libunwind
patch -N "src/build/config/BUILD.gn" < "$COMMAND_DIR/patches/add_deps_libunwind.patch"

# Add -mno-outline-atomics flag
patch -N "src/build/config/compiler/BUILD.gn" < "$COMMAND_DIR/patches/add_nooutlineatomics_flag.patch"

# downgrade to JDK8 because Unity supports OpenJDK version 1.8.
# https://docs.unity3d.com/Manual/android-sdksetup.html
patch -N "src/build/android/gyp/compile_java.py" < "$COMMAND_DIR/patches/downgradeJDKto8_compile_java.patch"
patch -N "src/build/android/gyp/turbine.py" < "$COMMAND_DIR/patches/downgradeJDKto8_turbine.patch"

# Fix SetRawImagePlanes() in LibvpxVp8Encoder
patch -N "src/modules/video_coding/codecs/vp8/libvpx_vp8_encoder.cc" < "$COMMAND_DIR/patches/libvpx_vp8_encoder.patch"

pushd src
# Fix AdaptedVideoTrackSource::video_adapter()
patch -p1 < "$COMMAND_DIR/patches/fix_adaptedvideotracksource.patch"
# Fix Android video encoder
patch -p1 < "$COMMAND_DIR/patches/fix_android_videoencoder.patch"
popd

mkdir -p "$ARTIFACTS_DIR/lib"


for target_cpu in "arm64" "x64"
do
  mkdir -p "$ARTIFACTS_DIR/lib/${target_cpu}"

  for is_debug in "true" "false"
  do
    #keeping the build folders in a paltform, arch and debug specific folder
    export OUTPUT_DIR="${UWEBRTC_DIR}/out/${PLATFORM_DIR_NAME}-${target_cpu}-${is_debug}"
    echo "Output to ${OUTPUT_DIR}"

    # generate ninja files
    # use `treat_warnings_as_errors` option to avoid deprecation warnings
    gn gen "$OUTPUT_DIR" --root="src" \
      --args="is_debug=${is_debug} \
      is_java_debug=${is_debug} \
      target_os=\"android\" \
      target_cpu=\"${target_cpu}\" \
      rtc_use_h264=false \
      rtc_include_tests=false \
      rtc_build_examples=false \
      is_component_build=false \
      use_rtti=true \
      use_custom_libcxx=false \
      treat_warnings_as_errors=false \
      use_errorprone_java_compiler=false \
      use_cxx17=true"

    # build static library
    ninja -C "$OUTPUT_DIR" webrtc

    filename="libwebrtc.a"
    if [ $is_debug = "true" ]; then
      filename="libwebrtcd.a"
    fi

    # copy static library
    cp "$OUTPUT_DIR/obj/libwebrtc.a" "$ARTIFACTS_DIR/lib/${target_cpu}/${filename}"
  done
done

pushd src

for is_debug in "true" "false"
do
  # use `treat_warnings_as_errors` option to avoid deprecation warnings
  "$PYTHON3_BIN" tools_webrtc/android/build_aar.py \
    --build-dir $OUTPUT_DIR \
    --output $OUTPUT_DIR/libwebrtc.aar \
    --arch arm64-v8a x86_64 \
    --extra-gn-args "is_debug=${is_debug} \
      is_java_debug=${is_debug} \
      rtc_use_h264=false \
      rtc_include_tests=false \
      rtc_build_examples=false \
      is_component_build=false \
      use_rtti=true \
      use_custom_libcxx=false \
      treat_warnings_as_errors=false \
      use_errorprone_java_compiler=false \
      use_cxx17=true"

  filename="libwebrtc.aar"
  if [ $is_debug = "true" ]; then
    filename="libwebrtc-debug.aar"
  fi
  # copy aar
  cp "$OUTPUT_DIR/libwebrtc.aar" "$ARTIFACTS_DIR/lib/${filename}"
done

popd

"$PYTHON3_BIN" "./src/tools_webrtc/libs/generate_licenses.py" \
  --target :webrtc "$OUTPUT_DIR" "$OUTPUT_DIR"

cd src
find . -name "*.h" -print | cpio -pd "$ARTIFACTS_DIR/include"

cp "$OUTPUT_DIR/LICENSE.md" "$ARTIFACTS_DIR"

# create zip
cd "$ARTIFACTS_DIR"
zip -r webrtc-android.zip lib include LICENSE.md
