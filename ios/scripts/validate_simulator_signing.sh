#!/bin/sh
set -eu
# Simulator Keychain still requires an application identifier in the local signature.
# Reject unsigned application builds before they can replace a working installation.
if [ "${PLATFORM_NAME:-}" = "iphonesimulator" ] && [ "${CODE_SIGNING_ALLOWED:-YES}" != "YES" ]; then
    echo 'error: Vrains simulator builds require local signing for login and JHS Keychain access. Use CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- (or bash dev.sh run). Unsigned builds cause -34018.' >&2
    exit 1
fi
