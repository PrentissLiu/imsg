# Changelog

## Unreleased

## 0.5.0 - 2026-02-17

- feat: add typing indicator command + RPC methods with stricter validation
- feat: add `--reactions` flag for `watch` to include tapback add/remove events
- feat: add `imsg react` command for tapback reactions via UI automation
- feat: reaction events now include `is_reaction`, `reaction_type`, `reaction_emoji`, `is_reaction_add`, `reacted_to_guid`
- feat: add `include_reactions` toggle to `watch.subscribe` RPC
- feat: include `thread_originator_guid` in message output
- feat: expose `destination_caller_id` in message output
- fix: flush watch output immediately when stdout is buffered
- fix: detect groups from `;+;` prefix in guid/identifier for RPC payloads
- refactor: consolidate schema detection, stdout writing, and payload mapping paths
- compat: keep fork support for macOS 13 while aligning to upstream v0.5.0 features

## 0.4.0 - 2026-01-07
- feat: surface audio message transcriptions (thanks @antons)
- fix: stage message attachments in Messages attachments directory (thanks @antons)
- fix: prefer chat GUID for `chat_id` sends to avoid 1:1 AppleScript errors (thanks @mshuffett)
- fix: detect python3 in patch-deps script (thanks @visionik)
- build: add universal binary build helper
- ci: switch to make-based lint/test/build
- docs: update build/test/release instructions
- chore: replace pnpm scripts with make targets

## 0.3.0 - 2026-01-02
- feat: JSON-RPC server over stdin/stdout (`imsg rpc`) with chats, history, watch, and send
- feat: group chat metadata in JSON/RPC output (participants, chat identifiers, is_group)
- feat: tapback + emoji reaction support in JSON output (#8) — thanks @tylerwince
- enhancement: custom emoji reactions and tapback removal handling
- feat: include `guid` and `reply_to_guid` metadata in JSON output
- fix: hide reaction rows from history/watch output and improve reaction matching
- fix: fill missing sender handles from `destination_caller_id` for outgoing/group messages
- fix: harden reaction detection
- docs: add RPC + group chat notes
- test: expand RPC/command coverage, add reaction fixtures, drop unused stdout helper
- test: add coverage for sender fallback
- chore: update copyright year to 2026

## 0.2.1 - 2025-12-30
- fix: avoid crash parsing long attributed bodies (>256 bytes) (thanks @tommybananas)

## 0.2.0 - 2025-12-28
- feat: Swift 6 rewrite with reusable IMsgCore library target
- feat: Commander-based CLI with SwiftPM build/test workflow
- feat: event-driven watch using filesystem events (no polling)
- feat: SQLite.swift + PhoneNumberKit + NSAppleScript integration
- fix: ship PhoneNumberKit resource bundle for CLI installs
- fix: embed Info.plist + AppleEvents entitlement for automation prompts
- fix: fall back to osascript when AppleEvents permission is missing
- fix: decode length-prefixed attributed bodies for sent messages
- chore: SwiftLint + swift-format linting
- change: JSON attachment keys now snake_case
- deprecation note: `--interval` replaced by `--debounce` (no compatibility)
- chore: version.env + generated version source for `--version`

## 0.1.1 - 2025-12-27
- feat: `imsg chats --json`
- fix: drop sqlite `immutable` flag so new messages/replies show up (thanks @zleman1593)
- chore: update go dependencies

## 0.1.0 - 2025-12-20
- feat: `imsg chats` list recent conversations
- feat: `imsg history` with filters (`--participants`, `--start`, `--end`) + `--json`
- feat: `imsg watch` polling stream (`--interval`, `--since-rowid`) + filters + `--json`
- feat: `imsg send` text and/or one attachment (`--service imessage|sms|auto`, `--region`)
- feat: attachment metadata output (`--attachments`) incl. resolved path + missing flag
- fix: clearer Full Disk Access error for `~/Library/Messages/chat.db`
