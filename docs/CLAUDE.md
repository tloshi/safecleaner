# Claude review

Implemented in 0.4 as an optional advisor over the existing scanner. It neither expands scan
coverage nor makes an unsafe candidate safe. Manual selection and the existing confirmation,
exclusions, running-owner and snapshot checks still govern every Trash operation.

## Data and credentials

The app sends one compact summary directly to `https://api.anthropic.com/v1/messages` when the
user clicks **Send summary to Claude**. The preview shows all scan-derived fields that leave:
fixed group types, anonymous group IDs, item counts, rounded-down allocated MB, scan-only status,
and counts of omitted groups and scan issues. The fixed instructions and response schema are also
part of the request. No filenames, paths, project names, file contents, scan error messages,
owner IDs or metadata hashes are sent. Claude's reply is untrusted plain text, never executable.

The API key is stored under `com.loshi.safecleaner.claude` / `anthropic-api-key` in Keychain,
not UserDefaults or files. It is sent only in the authentication header to Anthropic. Redirects
are refused. Network sessions are ephemeral, with no cookie store or URL cache. The app does not
log the key, request or response.

**Test key** sends one `GET https://api.anthropic.com/v1/models/{model}` with the key and nothing
else: no scan data, no message, no tokens. A 200 proves Anthropic accepts the key and that the
chosen model exists for that account; it does not prove there are credits. Only a real review
request does that. Requests are never retried automatically.

When Anthropic answers with an error, its `error.type` and `error.message` are shown after
sanitizing (control characters removed, at most 240 characters), prefixed by a plain-language
hint and a next step, for example *Anthropic rejected the API key (authentication_error: invalid
x-api-key). Check the key in Settings.* Network failures name their cause (offline, unknown host,
timeout). Nothing in these messages contains the key. Anthropic processes the submitted summary under the user's API
account; its policies apply. The privacy manifest declares this optional aggregate data for app
functionality, linked to the API account and not used for tracking. No claim of entirely on-device operation is made for this feature.

## Key status

The key indicator in Settings and on the Claude review page has five states: no key saved;
saved but not tested; testing; accepted (by Test key or by a successful review request, with the
model and time); and failed (with Anthropic's reason). A review request that Anthropic rejects
for authentication marks the key failed; a rate limit or an outage does not, because it says
nothing about the key. The state lives in memory only and restarts as “not tested” after a
relaunch, since a check is a fact about one moment. Opening Settings or Claude review re-reads
whether a key exists, so a key added or removed in Keychain Access while the app runs is noticed
without a relaunch. When “Send summary to Claude” is disabled, a line under it says why.

## Token control

- Haiku 5.5 is the default; Sonnet 5.5 is an explicit choice. No silent escalation. Both models
  reason before answering (adaptive thinking) and that reasoning counts toward `max_tokens`, so
  requests set `output_config.effort` to `low` and `max_tokens` to 4,000. The plan itself is still
  bounded by validation: summary ≤ 600 characters, at most 6 recommendations, each ≤ 240 characters.
- Requests send `anthropic-version: 2026-10-21` and no sampling parameters.
- Up to 16 groups sorted by allocated size, independent of the number of files or projects.
- Request JSON capped at 12,000 bytes.
- One turn, no chat history, tools, agent loops or automatic retries.
- The most recent successful result is cached in memory for the same model and local snapshot.
  Candidate order alone does not invalidate it; metadata changes do. Model/key changes or quitting
  may require another paid request. Failed requests are not cached or retried.
- The UI shows actual input/output usage returned by Anthropic on successful responses. A timeout,
  cancellation or invalid response may still consume credits; the app does not claim zero cost.
- This is not a hard dollar or monthly budget. Input tokenization and provider-added structured
  output instructions are not covered by the application byte estimate. Use API account spending
  limits for a billing ceiling.

## Reliability

Only `end_turn` with a valid JSON plan is accepted. Content blocks are read by type: thinking
blocks are ignored and exactly one text block must remain. Truncation, refusal, malformed plans,
unknown or repeated IDs, excessive text and promotion of scan-only groups are rejected. At most six advice
rows are shown. “Review these items” applies a local filter and never changes the selection.
Unknown age, last use, file contents and process activity remain unknown to the model.

Tests use synthetic candidates, fake credentials and an injected HTTP transport. No test contacts
Anthropic, uses a real API key or cleans personal files. Live account authorization, credit billing
and Keychain persistence in the final signed distribution require manual verification.

## Official references checked 3 and 30 October 2026

- [Claude model IDs and capabilities](https://platform.claude.com/docs/en/models/overview)
- [Models API, used by Test key](https://platform.claude.com/docs/en/api/models-list)
- [API versions and the 2026-10-21 migration](https://platform.claude.com/docs/en/api/migration-2026-10-21)
- [Messages API](https://platform.claude.com/docs/en/api/messages)
- [Structured JSON output](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)
- [API pricing](https://platform.claude.com/docs/en/about-claude/pricing)
- [Apple Keychain password storage](https://developer.apple.com/documentation/security/adding-a-password-to-the-keychain)
- [Apple HTTP redirect delegate](https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/urlsession(_:task:willperformhttpredirection:newrequest:completionhandler:))
