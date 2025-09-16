#!/bin/bash -i

# This script can be used to build PdfiumAndroid library (libjniPdfium) and its dependent libraries(libpng and libfreetype2).
export JAVA_HOME=$(/usr/libexec/java_home -v 17)

if [ -z "$JAVA_HOME" ]; then
    echo "❌ Java 17 not found. Please install JDK 17 and try again."
    exit 1
else
    echo "✅ JAVA_HOME set to $JAVA_HOME"
fi



# check the lastest ndk 
# or you can hard code the ndk
# export NDK_ROOT=~/Library/Android/sdk/ndk/28.2.13676358
NDK_DIR=~/Library/Android/sdk/ndk
LATEST_NDK=$(ls -1 "$NDK_DIR" | sort -rV | head -n 1)

if [ -z "$LATEST_NDK" ]; then
    echo "❌ No NDK versions found in $NDK_DIR"
    exit 1
else
    export NDK_ROOT="$NDK_DIR/$LATEST_NDK"
    echo "✅ NDK_ROOT set to $NDK_ROOT"
fi





export BUILD_ROOT="builddir"
rm -fr ${BUILD_ROOT}

# LIST OF ARCHS TO BE BUILT.
if [ -z "${BUILD_ARCHS}" ]; then
    # If no environment variable is defined, use all archs.
    BUILD_ARCHS="x86 armeabi-v7a x86_64 arm64-v8a"
fi

check_command_result() {
    local exit_code=$?
    local command=$1
    echo "exit code = ${exit_code}"
    if [ ${exit_code} -ne 0 ]; then
        echo "${command} failed. Exiting."
        exit 1
    fi
}

build_libpng() {
    rm -fr libpng
    git clone https://github.com/pnggroup/libpng
    cd libpng
    git checkout v1.6.44
    cd ..

    for ABI in ${BUILD_ARCHS}; do
        export BUILD_DIR=${BUILD_ROOT}/libpng/${ABI}
        rm -fr ${BUILD_DIR} &&
        cmake -G "Ninja" -B ${BUILD_DIR} -S libpng \
            -DCMAKE_ANDROID_NDK=${NDK_ROOT} \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_ANDROID_ARCH_ABI=${ABI} \
            -DBUILD_SHARED_LIBS:BOOL=true \
            -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON \
            -DANDROID_ABI=${ABI} \
            -DCMAKE_SYSTEM_NAME=Android
        check_command_result "configuring libpng"
        cmake --build ${BUILD_DIR} -j10
        check_command_result "building libpng"

        ls -lh ${BUILD_DIR}/*.so
        cp ${BUILD_DIR}/libpng16.so src/main/jni/lib/${ABI}/libmodpng.so
    done
}


build_libfreetype2() {
    FREETYPE_VERSION=2.13.3
    rm -fr freetype-${FREETYPE_VERSION}.tar.gz freetype-${FREETYPE_VERSION}
    wget https://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VERSION}.tar.gz
    tar -xvzf freetype-${FREETYPE_VERSION}.tar.gz
    export SRC_DIR=freetype-${FREETYPE_VERSION}

    for ABI in ${BUILD_ARCHS}; do
        export BUILD_DIR=${BUILD_ROOT}/${SRC_DIR}/${ABI}
        rm -fr ${BUILD_DIR} &&
        cmake -G "Ninja" -B ${BUILD_DIR} -S ${SRC_DIR} \
            -DCMAKE_ANDROID_NDK=${NDK_ROOT} \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_ANDROID_ARCH_ABI=${ABI} \
            -DBUILD_SHARED_LIBS:BOOL=true \
            -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON \
            -DANDROID_ABI=${ABI} \
            -DCMAKE_SYSTEM_NAME=Android
        check_command_result "configuring freetype"
        cmake --build ${BUILD_DIR} -j10
        check_command_result "building freetype"

        ls -lh ${BUILD_DIR}/*.so
        cp ${BUILD_DIR}/libfreetype.so src/main/jni/lib/${ABI}/libmodft2.so
    done
}
copy_ndk_library_for() {
    local ABI="$1"
    local SO_FIle="$2"
    local DEST="$3"
    local HOST="darwin-x86_64"  # macOS host

    echo "enter copy_ndk_library_for"
    # Map ABI to target triple
    local TRIPLE=""
    case "$ABI" in
        armeabi-v7a) TRIPLE="arm-linux-androideabi" ;;
        arm64-v8a)   TRIPLE="aarch64-linux-android" ;;
        x86)         TRIPLE="i686-linux-android" ;;
        x86_64)      TRIPLE="x86_64-linux-android" ;;
        *) echo "❌ Unsupported ABI: $ABI"; return 1 ;;
    esac
  echo "TRIPLE: $TRIPLE"
    # Construct source and destination paths
    local SRC="$NDK_ROOT/toolchains/llvm/prebuilt/$HOST/sysroot/usr/lib/$TRIPLE/$SO_FIle"
    echo "SRC: $SRC"

    # Copy if exists
    if [ -f "$SRC" ]; then
        mkdir -p "$DEST"
        cp "$SRC" "$DEST/$SO_FIle"
        echo "✅ Copied $SO_FIle for $ABI → $DEST"
    else
        echo "❌ File not found: $SRC"
        return 1
    fi
}


build_pdfiumAndroid() {

    for ABI in ${BUILD_ARCHS}; do
        cmake -G "Ninja" -B ${BUILD_ROOT}/pdfiumAndroid/${ABI}/ \
            -S . \
            -DCMAKE_BUILD_TYPE=Release \
            -DANDROID_NDK=${NDK_ROOT} \
            -DCMAKE_ANDROID_NDK=${NDK_ROOT} \
            -DCMAKE_SYSTEM_NAME=Android \
            -DCMAKE_ANDROID_ARCH_ABI=${ABI} \
            -DANDROID_ABI=${ABI} \
            -DANDROID_PLATFORM=android-21 \
            -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON
        check_command_result "configuring pdfiumAndroid"

        cmake --build ${BUILD_ROOT}/pdfiumAndroid/${ABI}/ -j10
        check_command_result "building pdfiumAndroid"
        
        # Copy the built libjniPdfium.so to the jni/lib directory for packaging
        echo "Copying libjniPdfium.so for ${ABI}"
        cp ${BUILD_ROOT}/pdfiumAndroid/${ABI}/libjniPdfium.so src/main/jni/lib/${ABI}/

        # Copy the correct libc++_shared.so from the NDK for each ABI
        echo "Copying libc++_shared.so for ${ABI}"
#        cp $NDK_ROOT/sources/cxx-stl/llvm-libc++/libs/${ABI}/libc++_shared.so src/main/jni/lib/${ABI}/
        copy_ndk_library_for "${ABI}" "libc++_shared.so" "src/main/jni/lib/${ABI}/"
    done
}

deploy_to_mega() {
    local mega_path=$1
    target_folder=${mega_path}/sdk/src/main/jniLibs
    for ABI in ${BUILD_ARCHS}; do
        cp -fv src/main/jni/lib/${ABI}/libmodpng.so ${target_folder}/${ABI}/
        cp -fv src/main/jni/lib/${ABI}/libmodft2.so ${target_folder}/${ABI}/
        cp -fv src/main/jni/lib/${ABI}/libmodpdfium.so ${target_folder}/${ABI}/
        cp -fv src/main/jni/lib/${ABI}/libmodpdfium.so ${target_folder}/${ABI}/
        cp -fv builddir/pdfiumAndroid/${ABI}/libjniPdfium.so ${target_folder}/${ABI}/
    done
}

print_usage() {
    echo "Build script for PdfiumAndroid library and its dependent libraries(libpng and libfreetype2)."
    echo "    And deploy the library to MEGA code directly."
    echo "Usage: $0 [options]"
    echo "Example 1: build everything and deploy to MEGA code"
    echo "        bash build.sh  --build-png --build-freetype --deploy-to-mega /PATH/TO/MEGA/CODE"
    echo "Example 2: build only pdfiumAndroid and deploy to MEGA code"
    echo "        bash build.sh --deploy-to-mega /PATH/TO/MEGA/CODE"
    echo "Options:"
    echo "  --build-png            [Optional] Build libpng"
    echo "  --build-freetype       [Optional] Build libfreetype2"
    echo "  --deploy-to-mega <path> [Optional] Deploy to the specified MEGA code path"
    echo "  --help                 Display this help message"
}

# Parse optional parameters
BUILD_PNG=false
BUILD_FREETYPE=false
MEGA_CODE_PATH=""

for arg in "$@"; do
    case $arg in
        --build-png)
        BUILD_PNG=true
        shift
        ;;
        --build-freetype)
        BUILD_FREETYPE=true
        shift
        ;;
        --deploy-to-mega)
        MEGA_CODE_PATH="$2"
        shift 2
        ;;
        --help)
        print_usage
        exit 0
        ;;
    esac
done

# Call the functions based on the parameters
if [ "$BUILD_PNG" = true ]; then
    echo "building libpng"
    build_libpng
fi

if [ "$BUILD_FREETYPE" = true ]; then
    echo "building freetype"
    build_libfreetype2
fi

build_pdfiumAndroid

if [ -n "$MEGA_CODE_PATH" ]; then
    if [ -d "$MEGA_CODE_PATH" ]; then
        deploy_to_mega "$MEGA_CODE_PATH"
    else
        echo "Directory $MEGA_CODE_PATH does not exist."
        exit 1
    fi
fi



echo "✅ Build completed successfully!"
echo "📦 To generate the release AAR, run:"
echo "   ./gradlew assembleRelease"
echo "📁 Your output will be located at:"
echo "   build/outputs/aar/PdfiumAndroid-2.0.1-release.aar"



