# Chat workspace screenshots

These screenshots show the native macOS chat workspace in a separate QA app
configuration, using `tests/chat_fixture_server.py` on loopback port 11436.
They contain only a synthetic conversation and do not use real provider calls,
credentials, or personal chat history. The interface language is Simplified Chinese.

- `chat-workspace.jpg`: empty conversation, persistent composer, window/text zoom,
  and next-message thinking/tool controls.
- `chat-markdown.jpg`: headings, lists, horizontally scrollable code, tables, and
  an explicitly offline test reply rendered by the native Markdown components.

The mocked tool label in the fixture is a presentation test, not evidence of an
external web search. See `DEEPSEEK_SETUP.md` for the real backend configuration
and automated validation entry point.

Fixture events are written to `build/Acceptance/ui-fixture-events.jsonl` inside this repository, independently of the directory used for build products.
