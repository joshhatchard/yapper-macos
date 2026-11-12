import Foundation
import FoundationModels

/// `TranscriptFormatting` over Apple's on-device Foundation Models (Apple Intelligence). Nothing is
/// sent off the Mac. A fresh session per transcript, so earlier dictations never leak into later ones.
/// Greedy sampling keeps rewrites deterministic and close to what was said.
@MainActor
final class FoundationModelsFormatter: TranscriptFormatting {
    private let model: SystemLanguageModel

    init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    func availability() -> FormattingAvailability {
        Self.availability(from: model.availability)
    }

    func format(_ text: String, as mode: TranscriptMode) async throws(FormattingError) -> String {
        guard let instructions = FormattingInstructions.instructions(for: mode),
            FormattingInstructions.isWorthFormatting(text)
        else { return text }
        let availability = availability()
        guard availability == .ready else { throw .unavailable(availability) }

        let session = LanguageModelSession(model: model, instructions: instructions)
        let output: String
        do {
            output = try await session.respond(
                to: FormattingInstructions.prompt(for: text),
                options: GenerationOptions(
                    samplingMode: .greedy,
                    maximumResponseTokens: FormattingInstructions.maximumResponseTokens(for: text))
            ).content
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.formattingError(for: error)
        } catch {
            throw .failed(String(describing: error))
        }
        let cleaned = FormattingInstructions.cleaned(output)
        guard !cleaned.isEmpty else { throw .emptyResult }
        guard !FormattingInstructions.looksLikeAnAnswer(cleaned, to: text) else { throw .notARewrite }
        return cleaned
    }

    nonisolated static func availability(from availability: SystemLanguageModel.Availability) -> FormattingAvailability
    {
        switch availability {
        case .available:
            .ready
        case .unavailable(.appleIntelligenceNotEnabled):
            .appleIntelligenceNotEnabled
        case .unavailable(.deviceNotEligible):
            .deviceNotEligible
        case .unavailable(.modelNotReady):
            .modelNotReady
        case .unavailable:
            .unavailable
        }
    }

    nonisolated static func formattingError(for error: LanguageModelSession.GenerationError) -> FormattingError {
        switch error {
        case .exceededContextWindowSize: .tooLong
        case .guardrailViolation, .refusal: .refused
        default: .failed(error.localizedDescription)
        }
    }
}
