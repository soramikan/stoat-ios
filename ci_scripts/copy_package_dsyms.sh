#!/bin/sh
set -eu

if [ "${PLATFORM_NAME:-}" != "iphoneos" ]; then
    echo "Skipping package dSYM copy for PLATFORM_NAME=${PLATFORM_NAME:-unknown}"
    exit 0
fi

if [ "${ACTION:-}" != "install" ]; then
    echo "Skipping package dSYM copy for ACTION=${ACTION:-unknown}"
    exit 0
fi

if [ -z "${DWARF_DSYM_FOLDER_PATH:-}" ]; then
    echo "DWARF_DSYM_FOLDER_PATH is not set; skipping package dSYM copy"
    exit 0
fi

destination_dirs="${DWARF_DSYM_FOLDER_PATH}"

if [ -n "${ARCHIVE_PATH:-}" ]; then
    destination_dirs="${destination_dirs}
${ARCHIVE_PATH}/dSYMs"
fi

if [ -n "${CI_ARCHIVE_PATH:-}" ]; then
    destination_dirs="${destination_dirs}
${CI_ARCHIVE_PATH}/dSYMs"
fi

copy_dsym_to_destinations() {
    dsym_path="$1"

    echo "$destination_dirs" | while IFS= read -r destination_dir; do
        if [ -z "$destination_dir" ]; then
            continue
        fi

        mkdir -p "$destination_dir"
        rm -rf "$destination_dir/$(basename "$dsym_path")"
        cp -R "$dsym_path" "$destination_dir/"
        echo "Copied $(basename "$dsym_path") to $destination_dir"
    done
}

find_framework_binary() {
    framework_name="$1"

    for candidate in \
        "${TARGET_BUILD_DIR:-}/${FULL_PRODUCT_NAME:-}/Frameworks/${framework_name}.framework/${framework_name}" \
        "${TARGET_BUILD_DIR:-}/Frameworks/${framework_name}.framework/${framework_name}" \
        "${BUILT_PRODUCTS_DIR:-}/${framework_name}.framework/${framework_name}" \
        "${CONFIGURATION_BUILD_DIR:-}/${framework_name}.framework/${framework_name}" \
        "${DWARF_DSYM_FOLDER_PATH:-}/../${framework_name}.framework/${framework_name}"
    do
        if [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

generate_framework_dsym() {
    framework_name="$1"
    framework_binary="$(find_framework_binary "$framework_name" || true)"

    if [ -z "$framework_binary" ]; then
        echo "Could not find ${framework_name}.framework binary; skipping"
        return 0
    fi

    generated_dir="${DERIVED_FILE_DIR:-${TMPDIR:-/tmp}}/PackageFrameworkDSYMs"
    generated_dsym="${generated_dir}/${framework_name}.framework.dSYM"

    mkdir -p "$generated_dir"
    rm -rf "$generated_dsym"

    echo "Generating dSYM for $framework_binary"
    if xcrun dsymutil "$framework_binary" -o "$generated_dsym"; then
        copy_dsym_to_destinations "$generated_dsym"
        xcrun dwarfdump --uuid "$generated_dsym" || true
    else
        echo "Failed to generate ${framework_name}.framework.dSYM"
        return 1
    fi
}

generate_framework_dsym "Sentry"
generate_framework_dsym "LiveKitWebRTC"
