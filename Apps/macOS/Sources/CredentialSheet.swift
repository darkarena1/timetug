import CalendarCore
import SwiftUI

/// The sign-in form for a connector kind that asks for a user name and password (iCloud, Other CalDAV): one field per
/// `CredentialField`, the kind's help below, and the last error at the top.
struct CredentialSheet: View {
    let request: CredentialPrompter.Request
    let onSubmit: ([String: String]) -> Void
    let onCancel: () -> Void
    @State private var values: [String: String]

    init(request: CredentialPrompter.Request, onSubmit: @escaping ([String: String]) -> Void, onCancel: @escaping () -> Void) {
        self.request = request
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _values = State(initialValue: request.values)
    }

    /// Sign In needs every field; spaces alone do not count.
    static func isComplete(_ values: [String: String], fields: [CredentialField]) -> Bool {
        fields.allSatisfy { !(values[$0.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.title).font(.headline)
            if let error = request.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Form {
                ForEach(request.fields, id: \.key) { field in
                    if field.isSecret {
                        SecureField(field.label, text: binding(for: field.key))
                    } else {
                        TextField(field.label, text: binding(for: field.key))
                            .autocorrectionDisabled()
                    }
                }
            }
            .formStyle(.columns)
            if let help = request.help {
                VStack(alignment: .leading, spacing: 4) {
                    Text(help.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = help.url {
                        Link(help.linkTitle ?? url.absoluteString, destination: url).font(.footnote)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Sign In") { onSubmit(values) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!Self.isComplete(values, fields: request.fields))
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })
    }
}

/// Shows the credential sheet while `prompter` has a request. Closing it any way other than Sign In cancels the sign-in.
struct CredentialSheetPresenter: ViewModifier {
    @ObservedObject var prompter: CredentialPrompter
    /// The request whose sheet is on screen, so a `nil` written while one sheet is swapped for the next (a retry after
    /// an instant failure) does not cancel the new prompt.
    @State private var shownID: UUID?

    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { prompter.request }, set: { if $0 == nil, prompter.request?.id == shownID { prompter.cancel() } })) { request in
            CredentialSheet(request: request, onSubmit: { prompter.submit($0) }, onCancel: { prompter.cancel() })
                .onAppear { shownID = request.id }
        }
    }
}
