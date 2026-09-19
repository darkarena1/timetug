import Foundation
import OSLog
import TimeTugCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The one entry point the app calls.
public enum AppleIntelligence {
    /// nil when this SDK or OS has no on-device Apple model API. A non-nil adjudicator can still report
    /// `.unavailable` (Apple Intelligence off, unsupported hardware, model not ready).
    public static func makeAdjudicator() -> (any DuplicateAdjudicator)? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return FoundationModelsAdjudicator() }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct DuplicateJudgement {
    @Guide(description: "same if both entries are one real-world appointment, different if they are separate, unsure if you cannot tell",
           .anyOf(["same", "different", "unsure"]))
    var answer: String
}

@available(macOS 26.0, *)
struct FoundationModelsAdjudicator: DuplicateAdjudicator {
    static let engine = EngineInfo(id: "apple-intelligence", displayName: "Apple Intelligence", isOnDevice: true)
    private static let log = Logger(subsystem: "com.timetug.app", category: "dedup")

    var availability: AdjudicatorAvailability {
        switch SystemLanguageModel.default.availability {
        case .available: return .available(Self.engine)
        case .unavailable(let reason): return .unavailable(reason: String(describing: reason))
        }
    }

    func judge(_ requests: [AdjudicationRequest]) async -> [AdjudicationVerdict] {
        var verdicts: [AdjudicationVerdict] = []
        for request in requests {
            if Task.isCancelled { break }
            do {
                let session = LanguageModelSession(instructions: PromptBuilder.instructions)
                let response = try await session.respond(
                    to: PromptBuilder.prompt(for: request), generating: DuplicateJudgement.self,
                    options: GenerationOptions(temperature: 0))
                guard let answer = AdjudicationVerdict.Answer(rawValue: response.content.answer) else {
                    Self.log.error("Unexpected answer from the on-device model")
                    continue
                }
                verdicts.append(AdjudicationVerdict(requestID: request.id, answer: answer))
            } catch {
                if error is CancellationError { break }
                // No verdict is cached, so the pair is retried on a later refresh. Only the error type is
                // logged: model errors can embed event content.
                Self.log.error("On-device judgment failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
        return verdicts
    }
}
#endif
