#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
test_dir=$(mktemp -d /tmp/atoll-chat-checks.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
swift_check() {
    local suite="$1"
    shift
    xcrun swiftc -module-cache-path "$test_dir/cache" "$@" "$project_dir/tests/$suite/main.swift" -o "$test_dir/$suite"
    "$test_dir/$suite"
}
models="$project_dir/DynamicIsland/models"
swift_check deepseek "$models/DeepSeekConfiguration.swift"
swift_check images "$models/ImageAttachment.swift"
swift_check chat_attachments "$models/ImageAttachment.swift" "$models/ChatAttachmentImport.swift"
swift_check chat_protocol "$models/ImageAttachment.swift" "$models/ChatRequestBuilder.swift"
swift_check notch_compatibility "$models/NotchCompatibilityPolicy.swift"
swift_check chat_presentation "$models/ChatPresentation.swift"
swift_check markdown "$models/ChatMarkdown.swift"
swift_check chat_transport "$models/ImageAttachment.swift" "$models/ChatRequestBuilder.swift" "$models/ChatTransport.swift"
python3 -m unittest discover -s "$project_dir/tests" -p 'test_*.py' -v
python3 -m unittest discover -s "$project_dir/deepseek-bridge" -v
node "$project_dir/deepseek-bridge/test_extension.mjs"
python3 -m json.tool "$project_dir/DynamicIsland/Localizable.xcstrings" > "$test_dir/localization.json"
git -C "$project_dir" diff --check
