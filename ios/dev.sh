#!/bin/bash
set -euo pipefail

IOS_DEV_ROOT="$(cd "$(dirname "$0")" && pwd)"
IOS_DEV_BUILD="$IOS_DEV_ROOT/.build"
IOS_DEV_PROJECT="$IOS_DEV_ROOT/Vrains.xcodeproj"

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

select_local_xcode() {
    if [ -z "${DEVELOPER_DIR:-}" ]; then
        DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
        if [ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]; then
            DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
        fi
        export DEVELOPER_DIR
    fi
    [ -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ] || fail "请通过 xcode-select 或 DEVELOPER_DIR 选择有效的 Xcode Developer 目录。"
}

require_xcode() {
    select_local_xcode
    xcodebuild -checkFirstLaunchStatus || fail "请先完成 Xcode 首次配置：bash ios/dev.sh setup。"
}

simulator_info() {
    xcrun simctl list --json | python3 -c '
import json, sys

data = json.load(sys.stdin)
runtimes = [r for r in data["runtimes"] if r.get("isAvailable")
            and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
            and int(r["version"].split(".")[0]) >= 17]
if sys.argv[1] == "runtimes":
    for runtime in runtimes:
        print(runtime["name"] + ": " + runtime["identifier"])
    sys.exit(0 if runtimes else 1)
runtime_ids = {r["identifier"] for r in runtimes}
requested = sys.argv[2]
devices = [d for runtime, group in data["devices"].items() if runtime in runtime_ids
           for d in group if d.get("isAvailable")
           and (d["udid"] == requested if requested else d["name"].startswith("iPhone"))]
if not devices:
    sys.exit("没有匹配的 iOS 17+ 模拟器，请检查 UDID 或在 Xcode 中添加 iPhone 模拟器。")
devices.sort(key=lambda d: (d["state"] != "Booted", d["name"], d["udid"]))
print(devices[0]["udid"])
' "$1" "${2:-}"
}

doctor() {
    printf '\nmacOS 与架构\n'
    sw_vers
    uname -m
    printf '\nXcode\n'
    require_xcode
    printf 'Developer directory: %s\n' "$DEVELOPER_DIR"
    xcodebuild -version
    xcrun swift --version
    printf '\niOS SDK\n'
    xcrun --sdk iphoneos --show-sdk-version
    xcrun --sdk iphonesimulator --show-sdk-version
    printf '\n可用的 iOS 模拟器运行时\n'
    simulator_info runtimes || fail "请安装 iOS 17+ 模拟器运行时：bash ios/dev.sh setup。"
    printf '\n可用的模拟器\n'
    xcrun simctl list devices available
}

setup() {
    if [ -n "${1:-}" ]; then
        export DEVELOPER_DIR="${1%/}/Contents/Developer"
    fi
    select_local_xcode
    sudo xcode-select --switch "$DEVELOPER_DIR"
    if ! xcodebuild -checkFirstLaunchStatus; then
        printf '请在本机终端阅读并确认 Xcode 许可协议。\n'
        sudo /usr/bin/env "DEVELOPER_DIR=$DEVELOPER_DIR" xcodebuild -license
        sudo /usr/bin/env "DEVELOPER_DIR=$DEVELOPER_DIR" xcodebuild -runFirstLaunch
    fi
    if ! simulator_info runtimes >/dev/null; then
        xcodebuild -downloadPlatform iOS
    fi
    doctor
}

build_app() {
    local destination="$1" derived_data="$2"
    shift 2
    xcodebuild -project "$IOS_DEV_PROJECT" -scheme Vrains -configuration Debug \
        -destination "$destination" -derivedDataPath "$derived_data" "$@" build
}

build_simulator() {
    build_app "${1:-generic/platform=iOS Simulator}" "$IOS_DEV_BUILD/DerivedData" \
        CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
}

build() {
    require_xcode
    build_simulator
}

run() {
    require_xcode
    local device_id app
    device_id="$(simulator_info device "${1:-}")"
    build_simulator "platform=iOS Simulator,id=$device_id"
    xcrun simctl bootstatus "$device_id" -b
    local simulator_app="$DEVELOPER_DIR/Applications/Simulator.app"
    local device_hub="${DEVELOPER_DIR%/Developer}/Applications/DeviceHub.app"
    if [ -d "$simulator_app" ]; then
        open -a "$simulator_app" --args -CurrentDeviceUDID "$device_id"
    elif [ -d "$device_hub" ]; then
        open -a "$device_hub"
    fi
    app="$IOS_DEV_BUILD/DerivedData/Build/Products/Debug-iphonesimulator/Vrains.app"
    xcrun simctl install "$device_id" "$app"
    xcrun simctl launch "$device_id" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
}

run_device() {
    require_xcode
    local device_id="${1:-}"
    [ -n "$device_id" ] || fail '用法：bash ios/dev.sh run-device <iPhone UDID>。连接并解锁手机后执行。'
    local settings app_bundle_id team_id
    settings="$(xcodebuild -project "$IOS_DEV_PROJECT" -scheme Vrains -configuration Debug \
        -sdk iphoneos -showBuildSettings -json | python3 -c '
import json, sys
settings = next(item["buildSettings"] for item in json.load(sys.stdin) if item["target"] == "Vrains")
print(settings["PRODUCT_BUNDLE_IDENTIFIER"], settings.get("DEVELOPMENT_TEAM", ""))
')"
    read -r app_bundle_id team_id <<< "$settings"
    [ -n "$team_id" ] || fail '请在 config/signing.xcconfig 中填写 Apple Team ID。'
    python3 "$IOS_DEV_ROOT/scripts/device_provisioning.py" prepare \
        --bundle-id "$app_bundle_id" --team-id "$team_id" \
        --backup-dir "$IOS_DEV_BUILD/SigningProfileBackups"
    build_app 'generic/platform=iOS' "$IOS_DEV_BUILD/DeviceDerivedData" \
        -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
        CODE_SIGN_STYLE=Automatic CODE_SIGNING_ALLOWED=YES
    local app="$IOS_DEV_BUILD/DeviceDerivedData/Build/Products/Debug-iphoneos/Vrains.app"
    codesign --verify --deep --strict "$app"
    python3 "$IOS_DEV_ROOT/scripts/device_provisioning.py" verify \
        --bundle-id "$app_bundle_id" --team-id "$team_id" --device "$device_id" \
        --profile "$app/embedded.mobileprovision"
    xcrun devicectl device install app --device "$device_id" "$app"
    xcrun devicectl device process launch --device "$device_id" "$app_bundle_id"
}

case "${1:-help}" in
    doctor) doctor ;;
    setup) setup "${2:-}" ;;
    build) build ;;
    run) run "${2:-}" ;;
    run-device) run_device "${2:-}" ;;
    open) require_xcode; open -a "${DEVELOPER_DIR%/Contents/Developer}" "$IOS_DEV_PROJECT" ;;
    help|-h|--help)
        printf '%s\n' \
            '用法：bash ios/dev.sh <command>' \
            '  doctor                 检查 Xcode、Swift、iOS SDK 和模拟器' \
            '  setup [Xcode.app 路径]  配置 Xcode 并安装 iOS 模拟器运行时' \
            '  build                  构建使用本地签名的模拟器 App' \
            '  run [模拟器 UDID]       构建并在模拟器中启动 App' \
            '  run-device <UDID>      真机自动签名安装与描述文件检查' \
            '  open                   用 Xcode 打开工程'
        ;;
    *) fail "未知命令：$1。运行 bash ios/dev.sh help 查看用法。" ;;
esac
