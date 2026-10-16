import SwiftUI
import OrbitalModels

/// Entrar con tu cuenta de Stremio (el eje de todo): lo que ves aquí aparece en Orbital y al revés.
struct LoginView: View {
    let session: SessionModel
    @StateObject private var observer: ModelObserver<SessionModel>
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?
    enum Field { case email, password }

    init(session: SessionModel) {
        self.session = session
        _observer = StateObject(wrappedValue: ModelObserver(session))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Image("Logo").resizable().frame(width: DS.Size.logo, height: DS.Size.logo)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)).accessibilityHidden(true)
                        .padding(.bottom, DS.Space.s2)
                    Text("Orbital").font(DS.TextRecipe.display.font.weight(.bold)).foregroundStyle(DS.text)
                    Text("Entra con tu cuenta de Stremio. Lo que veas aquí aparece en Orbital y al revés.")
                        .font(DS.TextRecipe.secondary.font).foregroundStyle(DS.textMuted)
                }
                VStack(spacing: DS.Space.s3) {
                    TextField("Correo de Stremio", text: $email)
                        .textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus, equals: .email).submitLabel(.next).onSubmit { focus = .password }
                        .padding(DS.Space.s3).background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
                    SecureField("Contraseña", text: $password)
                        .textContentType(.password).focused($focus, equals: .password).submitLabel(.go).onSubmit(signIn)
                        .padding(DS.Space.s3).background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
                if case .failed(let message) = observer.model.state { DSNotice(text: AppEnvironment.shared.message(message), tone: .error) }
                Button(action: signIn) {
                    HStack { if observer.model.state == .signingIn { ProgressView() }; Text("Entrar") }.frame(maxWidth: .infinity)
                }
                .dsPrimaryButton().controlSize(.large)
                .disabled(observer.model.state == .signingIn || email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                Text("Tu contraseña no se guarda: solo la clave de sesión, en el Keychain de tu iPhone.")
                    .font(DS.TextRecipe.caption.font).foregroundStyle(DS.textFaint)
            }
            .padding(DS.Space.s6)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Backdrop())
    }

    private func signIn() { Task { await session.signIn(email: email, password: password) } }
}
