import OSLog
import SwiftUI

/// The golden-task sample: sign in, browse a list, open an item, and crash on purpose for the logs task.
@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                LoginView().tabItem { Label("Login", systemImage: "person") }
                ItemsView().tabItem { Label("Items", systemImage: "list.bullet") }
            }
        }
    }
}

let log = Logger(subsystem: "dev.simtap.demo", category: "login")

/// What the sign-in shows for an email and password: the rule the unit tests check.
func signInMessage(email: String, password: String) -> String {
    email.contains("@") && password.count >= 4 ? "Welcome, \(email)" : "Invalid email or password"
}

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var remember = false
    @State private var message = "Not signed in"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .accessibilityIdentifier("email")
                SecureField("Password", text: $password).accessibilityIdentifier("password")
                Toggle("Remember me", isOn: $remember).accessibilityIdentifier("remember")
                Button("Sign In") {
                    message = signInMessage(email: email, password: password)
                    let ok = message.hasPrefix("Welcome")
                    print("Sign In tapped, ok: \(ok)")
                    if ok { log.info("signed in") } else { log.error("sign-in rejected: invalid email or password") }
                }
                .accessibilityIdentifier("signIn")
                Text(message).accessibilityIdentifier("status")
            }
            .navigationTitle("Sign In")
        }
    }
}

struct ItemsView: View {
    private let items = (1...40).map { "Item \($0)" }

    var body: some View {
        NavigationStack {
            List(items, id: \.self) { item in
                NavigationLink(item) {
                    Text("Details for \(item)")
                        .accessibilityIdentifier("detail")
                        .navigationTitle(item)
                }
            }
            .navigationTitle("Items")
            .toolbar {
                Button("Crash") {
                    print("about to crash on purpose")
                    fatalError("Demo crash for the golden task")
                }
                .accessibilityIdentifier("crash")
            }
        }
    }
}
