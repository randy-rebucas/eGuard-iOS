import SwiftUI

/// Asks for the confirmation a deletion needs: the parent's password, or typing DELETE for
/// Apple/Google accounts that never set one. The server enforces the same rule.
private struct DeletionConfirmationAlert: ViewModifier {
    let title: String
    let message: String
    let confirmTitle: String
    @Binding var isPresented: Bool
    let user: APIUser?
    let onConfirm: (DeletionConfirmation) -> Void

    @State private var input = ""
    @State private var isShowingInvalid = false

    private var usesPassword: Bool { user?.canUsePassword ?? true }

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $isPresented) {
                if usesPassword {
                    SecureField("Your password", text: $input)
                } else {
                    TextField("Type DELETE", text: $input)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Button(confirmTitle, role: .destructive) {
                    if let confirmation = DeletionConfirmation.make(user: user, input: input) {
                        onConfirm(confirmation)
                    } else {
                        isShowingInvalid = true
                    }
                    input = ""
                }
                Button("Cancel", role: .cancel) { input = "" }
            } message: {
                Text(message + (usesPassword ? " Enter your password to confirm." : " Type DELETE to confirm."))
            }
            .alert(usesPassword ? "Password needed" : "Type DELETE", isPresented: $isShowingInvalid) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(usesPassword ? "Enter your eGuard password to confirm." : "Type the word DELETE in capital letters to confirm.")
            }
    }
}

extension View {
    func deletionConfirmation(
        _ title: String,
        message: String,
        confirmTitle: String = "Delete",
        isPresented: Binding<Bool>,
        user: APIUser?,
        onConfirm: @escaping (DeletionConfirmation) -> Void
    ) -> some View {
        modifier(DeletionConfirmationAlert(title: title, message: message, confirmTitle: confirmTitle, isPresented: isPresented, user: user, onConfirm: onConfirm))
    }
}
