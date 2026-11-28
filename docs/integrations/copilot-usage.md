# GitHub Copilot usage monitor

The optional GitHub Copilot card lives alongside Claude, Codex, Cursor and other
providers in Atoll's Usage panel. Enable it in Settings → Stats → LLM Providers.
It displays account-wide billing quota, shared across Copilot Desktop and IDEs.
It does not monitor individual task activity and requires no repository hooks.

## Connection

Enter `github.com` or a GitHub Enterprise data-residency host such as
`your-company.ghe.com`, and a GitHub token authorized for Copilot on that host.
Save connection stores the token only in Atoll's own macOS Keychain item, scoped
to the host. No Copilot Desktop credential is extracted or changed. Tokens and
HTTP response bodies are never logged. Disconnect, or turning the provider off,
deletes the saved token for the configured host. Existing saved credentials for
other hosts are separate Keychain items.

This implementation uses GitHub's **undocumented** account endpoint
`GET https://api.<host>/copilot_internal/user`. Authentication requirements and
payloads can change. Not every GitHub token has permission to read this endpoint;
401/403 is shown as access denied, not as zero usage. There is no automatic
account login or credential reuse in this first implementation.

Quota parsing is based on the quota types bundled with the Copilot app SDK
(`CopilotUserResponseQuotaSnapshotsPremiumInteractions`, app 1.4.3) and the
account API used by the GitHub Copilot runtime. The endpoint is listed in
[GitHub's Copilot allowlist](https://docs.github.com/en/copilot/reference/copilot-allowlist-reference).

## Display semantics

- Percentage is **consumed**: `100 - percent_remaining`.
- Entitlements accept JSON numbers or numeric strings. Older Free accounts use
  `monthly_quotas` and `limited_user_quotas` for chat/completions, with
  `limited_user_reset_date` for their reset. New snapshots take precedence per category.
- When percentage is absent, precise `quota_remaining` or `remaining` and a
  positive entitlement provide the fallback.
- Premium requests, chat, and completions have separate entries when reported.
- Token-based premium quota is labeled AI credits, not a token count or dollar cost.
- Unlimited entitlements are labeled Unlimited with no percentage gauge.
- Missing counters and zero-entitlement placeholders show quota unavailable.
- Reset dates accept epoch seconds, ISO 8601 dates, and UTC calendar dates.
- Plan comes directly from `copilot_plan`. No daily token totals, spend estimates,
  or fictitious five-hour/weekly windows are inferred.

Requests use ephemeral networking without cookies, response caching or automatic credential storage, a 15-second timeout and the existing manager's
60-second refresh throttle. A forced refresh requested while one is running is
queued and repeated requests are coalesced, so saved credentials are fetched
after the active request completes. Redirects are refused. The token is sent only to
`api.github.com` or the validated `api.<tenant>.ghe.com` host. Other GitHub
Enterprise server/custom-domain deployments are not supported yet.

## Security review

Bearer tokens are validated before Keychain storage and request construction.
Control characters, whitespace, non-token characters and inputs over 8192 bytes
are rejected. The secure entry field is cleared when its host changes, the
provider is disabled, or its settings leave the screen. Stored Keychain items
explicitly opt out of synchronization.

The URLSession delegate rejects redirects. Successful responses must match the
requested URL; JSON decoding is limited to a 1 MiB response body. This is a
parsing limit, not a streaming download-memory limit. Low-level transport errors
are replaced with a generic message, so their diagnostic strings cannot disclose
credentials. HTTP errors do not expose the response body. No TLS validation is
disabled and no external commands are executed by the provider.

These controls and local checks are not a security certification. Live account
authentication, real Keychain behavior, enterprise policy compatibility and
upstream CI still require validation.

## Validation

`DynamicIslandTests/CopilotUsageTests.swift` covers quota parsing, host and
token validation and error handling, and `LLMUsageManagerTests.swift` covers
refresh coalescing. Both are part of the `DynamicIslandTests` target:

```sh
xcodebuild test -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  -only-testing:DynamicIslandTests/CopilotUsageTests \
  -only-testing:DynamicIslandTests/LLMUsageManagerTests
```

An authenticated request to a real Copilot quota endpoint and rendering with
live quota data still need to be checked on a real account.
