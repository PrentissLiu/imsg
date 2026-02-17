import Commander
import Foundation
import IMsgCore

enum TypingCommand {
  static let spec = CommandSpec(
    name: "typing",
    abstract: "Send typing indicator to a chat",
    discussion: nil,
    signature: CommandSignatures.withRuntimeFlags(
      CommandSignature(
        options: CommandSignatures.baseOptions() + [
          .make(label: "to", names: [.long("to")], help: "phone number or email"),
          .make(label: "chatID", names: [.long("chat-id")], help: "chat rowid"),
          .make(
            label: "chatIdentifier", names: [.long("chat-identifier")],
            help: "chat identifier (e.g. iMessage;-;+14155551212)"),
          .make(label: "chatGUID", names: [.long("chat-guid")], help: "chat guid"),
          .make(
            label: "duration", names: [.long("duration")],
            help: "how long to show typing (e.g. 5s, 3000ms); omit for start-only"),
          .make(
            label: "stop", names: [.long("stop")],
            help: "stop typing indicator instead of starting"),
          .make(
            label: "service", names: [.long("service")],
            help: "service to use: imessage|sms|auto"),
        ]
      )
    ),
    usageExamples: [
      "imsg typing --to +14155551212",
      "imsg typing --to +14155551212 --duration 5s",
      "imsg typing --to +14155551212 --stop true",
      "imsg typing --chat-identifier \"iMessage;-;+14155551212\"",
    ]
  ) { values, runtime in
    try await run(values: values, runtime: runtime)
  }

  static func run(
    values: ParsedValues,
    runtime: RuntimeOptions,
    storeFactory: @escaping (String) throws -> MessageStore = { try MessageStore(path: $0) },
    startTyping: @escaping (String) throws -> Void = {
      try TypingIndicator.startTyping(chatIdentifier: $0)
    },
    stopTyping: @escaping (String) throws -> Void = {
      try TypingIndicator.stopTyping(chatIdentifier: $0)
    },
    typeForDuration: @escaping (String, TimeInterval) async throws -> Void = {
      try await TypingIndicator.typeForDuration(chatIdentifier: $0, duration: $1)
    }
  ) async throws {
    let dbPath = values.option("db") ?? MessageStore.defaultPath
    let input = ChatTargetInput(
      recipient: values.option("to") ?? "",
      chatID: values.optionInt64("chatID"),
      chatIdentifier: values.option("chatIdentifier") ?? "",
      chatGUID: values.option("chatGUID") ?? ""
    )
    let stopFlag = try parseStopFlag(values.option("stop"))
    let durationRaw = values.option("duration") ?? ""
    let serviceRaw = values.option("service") ?? "imessage"

    try ChatTargetResolver.validateRecipientRequirements(
      input: input,
      mixedTargetError: ParsedValuesError.invalidOption("to"),
      missingRecipientError: ParsedValuesError.missingOption("to")
    )

    let resolvedTarget = try await ChatTargetResolver.resolveChatTarget(
      input: input,
      lookupChat: { chatID in
        let store = try storeFactory(dbPath)
        return try store.chatInfo(chatID: chatID)
      },
      unknownChatError: { chatID in
        IMsgError.invalidChatTarget("Unknown chat id \(chatID)")
      }
    )
    let candidates: [String]
    if input.hasChatTarget {
      candidates = ChatTargetResolver.chatTypingCandidates(
        chatIdentifier: resolvedTarget.chatIdentifier,
        chatGUID: resolvedTarget.chatGUID
      )
      if candidates.isEmpty {
        throw IMsgError.invalidChatTarget("Missing chat identifier or guid")
      }
    } else {
      candidates = try ChatTargetResolver.directTypingIdentifierCandidates(
        recipient: input.recipient,
        serviceRaw: serviceRaw,
        invalidServiceError: { IMsgError.invalidService($0) }
      )
    }
    let fallbackLookup = typingFallbackLookup(input: input, resolved: resolvedTarget)
    let fallbackChatGUID = resolvedTarget.chatGUID.isEmpty ? nil : resolvedTarget.chatGUID

    if stopFlag {
      do {
        try applyTypingAction(candidates: candidates) { candidate in
          try stopTyping(candidate)
        }
      } catch {
        try simulateTypingFallback(
          chatGUID: fallbackChatGUID,
          lookup: fallbackLookup,
          mode: .stop
        )
      }
      if runtime.jsonOutput {
        try JSONLines.print(["status": "stopped"])
      } else {
        Swift.print("typing indicator stopped")
      }
      return
    }

    if !durationRaw.isEmpty {
      let seconds = try parseDurationToSeconds(durationRaw)
      do {
        try await applyTypingDuration(candidates: candidates, seconds: seconds) { candidate, duration in
          try await typeForDuration(candidate, duration)
        }
      } catch {
        try simulateTypingFallback(
          chatGUID: fallbackChatGUID,
          lookup: fallbackLookup,
          mode: .duration(seconds: seconds)
        )
      }
      if runtime.jsonOutput {
        try JSONLines.print(["status": "completed", "duration_s": "\(seconds)"])
      } else {
        Swift.print("typing indicator shown for \(durationRaw)")
      }
      return
    }

    do {
      try applyTypingAction(candidates: candidates) { candidate in
        try startTyping(candidate)
      }
    } catch {
      try simulateTypingFallback(
        chatGUID: fallbackChatGUID,
        lookup: fallbackLookup,
        mode: .start
      )
    }
    if runtime.jsonOutput {
      try JSONLines.print(["status": "started"])
    } else {
      Swift.print("typing indicator started")
    }
  }

  private static func parseStopFlag(_ raw: String?) throws -> Bool {
    guard let raw else { return false }
    if raw == "true" { return true }
    if raw == "false" { return false }
    throw ParsedValuesError.invalidOption("stop")
  }

  private static func parseDurationToSeconds(_ raw: String) throws -> TimeInterval {
    guard let seconds = DurationParser.parse(raw), seconds > 0 else {
      throw IMsgError.typingIndicatorFailed(
        "Invalid duration: \(raw). Use e.g. 5s, 3000ms, 1m, or 1h")
    }
    return seconds
  }

  private static func typingFallbackLookup(input: ChatTargetInput, resolved: ResolvedChatTarget) -> String {
    if !input.recipient.isEmpty { return input.recipient }
    if let token = chatToken(from: resolved.chatIdentifier) { return token }
    if let token = chatToken(from: resolved.chatGUID) { return token }
    if !resolved.chatIdentifier.isEmpty { return resolved.chatIdentifier }
    return resolved.chatGUID
  }

  private static func chatToken(from raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.contains(";") else { return nil }
    let parts = trimmed.split(separator: ";", omittingEmptySubsequences: false)
    guard let tail = parts.last else { return nil }
    let token = String(tail).trimmingCharacters(in: .whitespacesAndNewlines)
    return token.isEmpty ? nil : token
  }

  private enum TypingFallbackMode {
    case start
    case stop
    case duration(seconds: TimeInterval)
  }

  private static func simulateTypingFallback(chatGUID: String?, lookup: String, mode: TypingFallbackMode)
    throws
  {
    let effectiveLookup = lookup.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !effectiveLookup.isEmpty || (chatGUID?.isEmpty == false) else {
      throw IMsgError.typingIndicatorFailed("Unable to resolve chat for typing fallback")
    }
    let guidArg = (chatGUID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    let (modeRaw, durationRaw): (String, String) = {
      switch mode {
      case .start: return ("start", "0")
      case .stop: return ("stop", "0")
      case .duration(let seconds): return ("duration", String(max(1, Int(seconds.rounded()))))
      }
    }()

    let script = """
      on run argv
        set chatGUID to item 1 of argv
        set chatLookup to item 2 of argv
        set modeName to item 3 of argv
        set durationSeconds to item 4 of argv as integer

        if chatLookup is not \"\" then
          set the clipboard to chatLookup
        end if

        tell application \"Messages\"
          activate
          if chatGUID is not \"\" then
            try
              set targetChat to chat id chatGUID
            end try
          end if
        end tell

        delay 0.25

        tell application \"System Events\"
          tell process \"Messages\"
            if chatLookup is not \"\" then
              keystroke \"f\" using command down
              delay 0.12
              keystroke \"a\" using command down
              keystroke \"v\" using command down
              delay 0.2
              key code 36
              delay 0.2
            end if

            if modeName is \"stop\" then
              keystroke \"a\" using command down
              delay 0.05
              key code 51
              return
            end if

            if modeName is \"start\" then
              keystroke \" \"
              return
            end if

            repeat durationSeconds times
              keystroke \" \"
              delay 0.15
              key code 51
              delay 0.85
            end repeat
          end tell
        end tell
      end run
      """
    try runAppleScript(script, arguments: [guidArg, effectiveLookup, modeRaw, durationRaw])
  }

  private static func runAppleScript(_ source: String, arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-l", "AppleScript", "-"] + arguments

    let stdinPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardError = stderrPipe

    try process.run()
    if let data = source.data(using: .utf8) {
      stdinPipe.fileHandleForWriting.write(data)
    }
    stdinPipe.fileHandleForWriting.closeFile()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
      let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
      let message = String(data: data, encoding: .utf8) ?? "Unknown AppleScript error"
      throw IMsgError.appleScriptFailure(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }

  private static func applyTypingAction(
    candidates: [String],
    action: (String) throws -> Void
  ) throws {
    var lastError: Error?
    for candidate in candidates {
      do {
        try action(candidate)
        return
      } catch {
        lastError = error
      }
    }
    if let lastError { throw lastError }
    throw IMsgError.typingIndicatorFailed("No typing target candidates available")
  }

  private static func applyTypingDuration(
    candidates: [String],
    seconds: TimeInterval,
    action: (String, TimeInterval) async throws -> Void
  ) async throws {
    var lastError: Error?
    for candidate in candidates {
      do {
        try await action(candidate, seconds)
        return
      } catch {
        lastError = error
      }
    }
    if let lastError { throw lastError }
    throw IMsgError.typingIndicatorFailed("No typing target candidates available")
  }
}
