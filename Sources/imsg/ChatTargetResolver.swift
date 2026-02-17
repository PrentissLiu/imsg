import IMsgCore

struct ChatTargetInput: Sendable {
  let recipient: String
  let chatID: Int64?
  let chatIdentifier: String
  let chatGUID: String

  var hasChatTarget: Bool {
    chatID != nil || !chatIdentifier.isEmpty || !chatGUID.isEmpty
  }
}

struct ResolvedChatTarget: Sendable {
  let chatIdentifier: String
  let chatGUID: String

  var preferredIdentifier: String? {
    if !chatGUID.isEmpty { return chatGUID }
    if !chatIdentifier.isEmpty { return chatIdentifier }
    return nil
  }
}

enum ChatTargetResolver {
  static func validateRecipientRequirements(
    input: ChatTargetInput,
    mixedTargetError: Error,
    missingRecipientError: Error
  ) throws {
    if input.hasChatTarget && !input.recipient.isEmpty {
      throw mixedTargetError
    }
    if !input.hasChatTarget && input.recipient.isEmpty {
      throw missingRecipientError
    }
  }

  static func resolveChatTarget(
    input: ChatTargetInput,
    lookupChat: (Int64) async throws -> ChatInfo?,
    unknownChatError: (Int64) -> Error
  ) async throws -> ResolvedChatTarget {
    var resolvedIdentifier = input.chatIdentifier
    var resolvedGUID = input.chatGUID

    if let chatID = input.chatID {
      guard let info = try await lookupChat(chatID) else {
        throw unknownChatError(chatID)
      }
      resolvedIdentifier = info.identifier
      resolvedGUID = info.guid
    }

    return ResolvedChatTarget(
      chatIdentifier: resolvedIdentifier,
      chatGUID: resolvedGUID
    )
  }

  static func directTypingIdentifier(
    recipient: String,
    serviceRaw: String,
    invalidServiceError: (String) -> Error
  ) throws -> String {
    guard let service = MessageService(rawValue: serviceRaw.lowercased()) else {
      throw invalidServiceError(serviceRaw)
    }
    let prefix = service == .sms ? "SMS" : "iMessage"
    return "\(prefix);-;\(recipient)"
  }

  static func directTypingIdentifierCandidates(
    recipient: String,
    serviceRaw: String,
    invalidServiceError: (String) -> Error
  ) throws -> [String] {
    let base = try directTypingIdentifier(
      recipient: recipient,
      serviceRaw: serviceRaw,
      invalidServiceError: invalidServiceError
    )
    return normalizedTypingCandidates([base] + typingVariants(for: base))
  }

  static func chatTypingCandidates(chatIdentifier: String, chatGUID: String) -> [String] {
    var candidates: [String] = []
    if !chatGUID.isEmpty {
      candidates.append(chatGUID)
      candidates += typingVariants(for: chatGUID)
    }
    if !chatIdentifier.isEmpty {
      candidates.append(chatIdentifier)
      candidates += typingVariants(for: chatIdentifier)
    }
    return normalizedTypingCandidates(candidates)
  }

  private static func typingVariants(for value: String) -> [String] {
    var variants: [String] = []
    if value.contains(";-;") {
      variants.append(value.replacingOccurrences(of: ";-;", with: ";+;"))
    }
    if value.contains(";+;") {
      variants.append(value.replacingOccurrences(of: ";+;", with: ";-;"))
    }
    if let token = chatToken(from: value) {
      variants.append(token)
      variants.append("iMessage;-;\(token)")
      variants.append("iMessage;+;\(token)")
      variants.append("SMS;-;\(token)")
      variants.append("SMS;+;\(token)")
    }
    return variants
  }

  private static func chatToken(from raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.contains(";") else { return nil }
    let parts = trimmed.split(separator: ";", omittingEmptySubsequences: false)
    guard let tail = parts.last else { return nil }
    let token = String(tail).trimmingCharacters(in: .whitespacesAndNewlines)
    return token.isEmpty ? nil : token
  }

  private static func normalizedTypingCandidates(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var output: [String] = []
    for item in values {
      let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      if seen.insert(trimmed).inserted {
        output.append(trimmed)
      }
    }
    return output
  }
}
