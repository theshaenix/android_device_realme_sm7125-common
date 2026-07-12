#!/bin/bash
#
# Copyright (C) 2016 The CyanogenMod Project
# Copyright (C) 2017-2021 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

ONLY_COMMON=
ONLY_TARGET=
KANG=
SECTION=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        --only-common )
                ONLY_COMMON=true
                ;;
        --only-target )
                ONLY_TARGET=true
                ;;
        -n | --no-cleanup )
                CLEAN_VENDOR=false
                ;;
        -k | --kang )
                KANG="--kang"
                ;;
        -s | --section )
                SECTION="${2}"; shift
                CLEAN_VENDOR=false
                ;;
        * )
                SRC="${1}"
                ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

function blob_fixup() {
    case "${1}" in
        vendor/etc/seccomp_policy/atfwd@2.0.policy)
            grep -q '^gettid:' "${2}" || sed -i '/^getuid:/a gettid: 1' "${2}"
            ;;
        odm/lib/libgf_hal_G3.so | odm/lib64/libgf_hal_G3.so)
            sed -i 's/ro.boot.flash.locked/ro.boot.flash.fucked/g' "${2}"
            ;;
        system_ext/lib64/lib-imsvideocodec.so)
            "${PATCHELF}" --replace-needed libgui.so libxxx.so "${2}"
            ;;
        vendor/lib64/hw/camera.qcom.so)
            grep -q libcamera_metadata_shim.so "${2}" || "${PATCHELF}" --add-needed "libcamera_metadata_shim.so" "${2}"
	    ;;
        vendor/lib/libsnsdiaglog.so | vendor/lib/libssc.so | vendor/lib/libsnsapi.so | vendor/lib/libsensorcal.so | vendor/lib64/libsnsdiaglog.so | vendor/lib64/libssc.so | vendor/lib64/libsnsapi.so | vendor/lib64/libsensorcal.so | vendor/bin/sensors.qti | vendor/lib/sensors.ssc.so | vendor/lib64/sensors.ssc.so | odm/lib64/libwvhidl.so | odm/lib/mediadrm/libwvdrmengine.so | odm/lib64/mediadrm/libwvdrmengine.so)
            "${PATCHELF}" --replace-needed "libprotobuf-cpp-lite-3.9.1.so" "libprotobuf-cpp-full-3.9.1.so" "${2}"
            ;;
    esac
}

if [ -z "${ONLY_TARGET}" ]; then
    # Initialize the helper for common device
    setup_vendor "${DEVICE_COMMON}" "${VENDOR}" "${ANDROID_ROOT}" true "${CLEAN_VENDOR}"

    extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"
fi

if [ -z "${ONLY_COMMON}" ] && [ -s "${MY_DIR}/../${DEVICE}/proprietary-files.txt" ]; then
    # Reinitialize the helper for device
    source "${MY_DIR}/../${DEVICE}/extract-files.sh"
    setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

    extract "${MY_DIR}/../${DEVICE}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"
fi

"${MY_DIR}/setup-makefiles.sh"
