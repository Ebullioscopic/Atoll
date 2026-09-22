#!/usr/bin/env python3
"""Historical integration is already committed; do not replay it over current source."""
from pathlib import Path
assert (Path(__file__).resolve().parents[1]/"DynamicIsland/ToolIsleFeatures/Gitee/GISettingsView.swift").exists()
print("Gitee integration already committed. No source was modified.")
