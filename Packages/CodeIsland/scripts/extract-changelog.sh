#!/bin/bash

set -euo pipefail

# Script to extract release notes for a specific version from CHANGELOG.md
# Usage: ./scripts/extract-changelog.sh <version> [changelog_path]
# Example: ./scripts/extract-changelog.sh 1.0.6

version="${1:-}"
changelog_path="${2:-CHANGELOG.md}"

# Validate inputs
if [[ -z "$version" ]]; then
    echo "Error: Version argument required" >&2
    echo "Usage: $0 <version> [changelog_path]" >&2
    exit 1
fi

if [[ ! -f "$changelog_path" ]]; then
    echo "Error: Changelog file not found: $changelog_path" >&2
    exit 1
fi

# Normalize version: add v prefix if not present
if [[ ! "$version" =~ ^v ]]; then
    version="v$version"
fi

# Check if version exists first
if ! grep -q "## \[$version\]" "$changelog_path"; then
    echo "Error: Version $version not found in $changelog_path" >&2
    exit 1
fi

# Extract content between "## [$version]" and the next "## [" header
# Using awk to find the version header and extract until the next header
awk -v version="$version" '
    BEGIN { found = 0; in_section = 0 }

    # Check if this is the version header we are looking for
    /^## \[/ {
        if (found) {
            # We have reached the next version header, stop
            exit 0
        }
        if ($0 ~ "## \\[" version "\\]") {
            found = 1
            in_section = 1
            next  # Skip the header line itself
        }
    }

    # If we found our section, print lines until the next header
    in_section { print }
' "$changelog_path"
