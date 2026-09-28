import CalendarCore
import Foundation

/// The model behind the credential sheet. A `.password` connector kind's `promptCredentials` waits in `prompt` until the
/// user signs in or cancels. Before each attempt the accounts controller prepares the title, help, prefilled values and
/// the last error; the sheet shows `request` and answers with `submit` or `cancel`.
@MainActor
final class CredentialPrompter: ObservableObject {
    struct Request: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var fields: [CredentialField]
        var help: CredentialHelp?
        /// Prefilled values, non-secret fields only.
        var values: [String: String]
        var error: String?
    }

    @Published private(set) var request: Request?
    /// The non-secret values of the form submitted since the last `prepare`; nil when none was submitted.
    private(set) var lastNonSecretValues: [String: String]?

    private var prepared: (title: String, help: CredentialHelp?, values: [String: String], error: String?) = ("", nil, [:], nil)
    private var continuation: CheckedContinuation<[String: String], Error>?

    func prepare(title: String, help: CredentialHelp?, values: [String: String] = [:], error: String? = nil) {
        prepared = (title, help, values, error)
        lastNonSecretValues = nil
    }

    /// Shows the sheet for `fields` and returns what the user entered. Throws `CancellationError` on Cancel, or when the
    /// calling task is cancelled (which also closes the sheet).
    func prompt(_ fields: [CredentialField]) async throws -> [String: String] {
        cancel()   // never leave an earlier prompt waiting
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { return continuation.resume(throwing: CancellationError()) }
                self.continuation = continuation
                let nonSecret = Set(fields.filter { !$0.isSecret }.map(\.key))
                request = Request(title: prepared.title, fields: fields, help: prepared.help,
                                  values: prepared.values.filter { nonSecret.contains($0.key) }, error: prepared.error)
            }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }

    func submit(_ values: [String: String]) {
        guard let shown = request, let waiting = continuation else { return }
        let nonSecret = Set(shown.fields.filter { !$0.isSecret }.map(\.key))
        lastNonSecretValues = values.filter { nonSecret.contains($0.key) }
        request = nil
        continuation = nil
        waiting.resume(returning: values)
    }

    func cancel() {
        request = nil
        guard let waiting = continuation else { return }
        continuation = nil
        waiting.resume(throwing: CancellationError())
    }
}
