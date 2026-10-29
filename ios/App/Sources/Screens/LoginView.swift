import SwiftUI
import OrbitalModels

/// Conectar tu cuenta de Stremio como respaldo (Ajustes › Cuenta): lo que ves también se guarda ahí, como copia, y lo que
/// tenías en Stremio pasa una vez al teléfono.
struct LoginView: View {
    @State private var signingIn = false
    let session: SessionModel
    @State private var observer: ModelObserver<SessionModel>
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss
    enum Field { case email, password }

    init(session: SessionModel) {
        self.session = session
        _observer = State(wrappedValue: ModelObserver(session))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    // La marca de la TV: el anillo se dibuja y la luna cae en su lugar, como al arrancar Orbital.
                    OrbitalWordmark(size: DS.Size.wordmark, animated: true).foregroundStyle(DS.text)
                        .padding(.bottom, DS.Space.s2)
                    Text("Conecta tu cuenta de Stremio como respaldo: lo que veas también se guarda ahí, como copia.")
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
                if case .failed(let message) = observer.model.state { DSNotice(verbatim: AppEnvironment.shared.message(message), tone: .error) }
                Button(action: signIn) {
                    HStack { if observer.model.state == .signingIn { ProgressView() }; Text("Conectar") }.frame(maxWidth: .infinity)
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
        .onChange(of: observer.model.state) { _, state in if state == .signedIn { dismiss() } }   // conectado: de vuelta a Ajustes
    }

    /// Una vez: dar Enter dos veces mientras entra no manda dos inicios de sesión.
    private func signIn() {
        guard !signingIn else { return }
        signingIn = true
        Task { await session.signIn(email: email, password: password); signingIn = false }
    }
}
