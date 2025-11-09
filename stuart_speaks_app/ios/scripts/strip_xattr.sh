#!/bin/bash
# Strip extended attributes from Flutter framework to fix code signing issues

set -e

# Strip attributes from the Flutter framework in the build directory
if [ -d "${BUILT_PRODUCTS_DIR}" ]; then
    find "${BUILT_PRODUCTS_DIR}" -name "Flutter.framework" -type d -exec xattr -cr {} \; 2>/dev/null || true
    find "${BUILT_PRODUCTS_DIR}" -name "Flutter" -type f -exec xattr -cr {} \; 2>/dev/null || true
fi

# Also strip from the source build directory
if [ -d "${SOURCE_ROOT}/build/ios" ]; then
    find "${SOURCE_ROOT}/build/ios" -name "Flutter.framework" -type d -exec xattr -cr {} \; 2>/dev/null || true
    find "${SOURCE_ROOT}/build/ios" -name "Flutter" -type f -exec xattr -cr {} \; 2>/dev/null || true
fi

exit 0
