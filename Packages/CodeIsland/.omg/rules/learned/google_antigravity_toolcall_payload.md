---
name: google_antigravity_toolcall_payload
description: Specification of Google Antigravity (agy CLI / Gemini CLI) toolCall JSON format for hook event payload parsing.
globs: Sources/**/*.swift
---

# Google Antigravity toolCall Payload Specification

Google Antigravity/Gemini CLI structures its tool hook payloads with a nested `toolCall` key.

### Payload Structure
- Outer container: `toolCall`
- Tool Name: `toolCall.name`
- Tool Input Arguments: `toolCall.args`

### Argument Keys Mapping
- `CommandLine` / `command` -> Command script for `run_command` / `Bash`
- `AbsolutePath` / `file_path` -> Target file path for `view_file` / `Read`
- `TargetFile` -> Target file path for `replace_file_content` / `multi_replace_file_content` / `write_to_file`
- `Query` / `SearchPath` -> Query and path for `grep_search` / `Grep`

Always check `toolCall` nesting when resolving tool parameters in hooks and notch integrations to prevent empty descriptions or "Unknown" tool display cards.
