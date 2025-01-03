#!/bin/bash -eu
set -e
source env.sh
cd ./com.unity.webrtc

export ARTIFACTS_DIR="$(pwd)/artifacts/android"
export SOLUTION_DIR=$(pwd)/Plugin~
export WEBRTC_FRAMEWORK_DIR=$(pwd)/Runtime/Plugins/Android
export BINARY_DIR="${SOLUTION_DIR}/out/build/android"

echo "ARTIFACTS_DIR: $ARTIFACTS_DIR"
echo "SOLUTION_DIR: $SOLUTION_DIR"
rsync -rav --delete ${ARTIFACTS_DIR}/ $SOLUTION_DIR/webrtc
cp -f $SOLUTION_DIR/webrtc/lib/libwebrtc.aar $WEBRTC_FRAMEWORK_DIR

# Build webrtc Unity plugin
cd "$SOLUTION_DIR"
echo "Building WebRTCPlugin"
#rm -rf ${BINARY_DIR}
for ARCH_ABI in "arm64-v8a" "x86_64"
do
  cmake . \
    -B build \
    -D CMAKE_SYSTEM_NAME=Android \
    -D CMAKE_ANDROID_API_MIN=24 \
    -D CMAKE_ANDROID_API=24 \
    -D CMAKE_ANDROID_ARCH_ABI=$ARCH_ABI \
    -D CMAKE_ANDROID_NDK=$ANDROID_NDK \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_ANDROID_STL_TYPE=c++_static

  cmake \
    --build build \
    --target WebRTCPlugin

  # libwebrtc.so move into libwebrtc.aar
  pushd $PLUGIN_DIR
  mkdir -p jni/$ARCH_ABI
  mv libwebrtc.so jni/$ARCH_ABI
  zip -g libwebrtc.aar jni/$ARCH_ABI/libwebrtc.so
  rm -r jni
  popd
  rm -rf build
done
