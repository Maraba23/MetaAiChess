import SwiftUI

struct ContentView: View {
  let glasses: GlassesManager
  let bridge: ChessBridge
  @Bindable var settings: AppSettings
  let watcher: MoveWatcher
  @State private var showSettings = false

  var body: some View {
    VStack(spacing: 0) {
      glassesPanel
      Divider()
      ChessWebView(bridge: bridge)
        .ignoresSafeArea(edges: .bottom)
    }
    .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
    .sheet(isPresented: $showSettings) {
      SettingsView(settings: settings, glasses: glasses)
    }
    .alert(
      "Algo deu errado",
      isPresented: Binding(get: { glasses.errorMessage != nil }, set: { if !$0 { glasses.errorMessage = nil } })
    ) {
      Button("OK") { glasses.errorMessage = nil }
    } message: {
      Text(glasses.errorMessage ?? "")
    }
  }

  private var glassesPanel: some View {
    HStack(alignment: .center, spacing: 12) {
      preview
      VStack(alignment: .leading, spacing: 6) {
        Text(glassesStatus).font(.subheadline.weight(.semibold))
        if glasses.isStreaming {
          Toggle(isOn: Binding(
            get: { watcher.isOn },
            set: { $0 ? watcher.start(glasses: glasses, bridge: bridge, settings: settings) : watcher.stop() }
          )) {
            Text("Ler lances pelo óculos").font(.subheadline)
          }
          if watcher.isOn {
            Text(watcher.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
          }
        } else {
          primaryButton
        }
      }
      Spacer(minLength: 0)
      Button { showSettings = true } label: {
        Image(systemName: "gearshape").font(.title3)
      }
      .accessibilityLabel("Ajustes")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  /// A small view of what the glasses see, to check the board is in frame
  private var preview: some View {
    Group {
      if let frame = glasses.latestFrame {
        Image(uiImage: frame).resizable().scaledToFill()
      } else {
        Image(systemName: "eyeglasses").font(.title2).foregroundStyle(.secondary)
      }
    }
    .frame(width: 54, height: 96)
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  @ViewBuilder private var primaryButton: some View {
    if !glasses.isRegistered {
      Button(glasses.registrationState == .registering ? "Conectando…" : "Conectar óculos") { glasses.connect() }
        .buttonStyle(.borderedProminent)
        .disabled(glasses.registrationState == .registering)
    } else {
      Button(glasses.sessionState == .idle ? "Ligar câmera do óculos" : "Ligando câmera…") { glasses.startCamera() }
        .buttonStyle(.borderedProminent)
        .disabled(glasses.sessionState != .idle || !glasses.hasDevice)
    }
  }

  private var glassesStatus: String {
    if !glasses.isRegistered { return "Óculos não conectado" }
    if !glasses.hasDevice { return "Procurando o óculos…" }
    if glasses.isStreaming { return "Câmera do óculos ligada" }
    return "Óculos conectado"
  }
}

struct SettingsView: View {
  @Bindable var settings: AppSettings
  let glasses: GlassesManager
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          SecureField("sk-ant-…", text: $settings.apiKey)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } header: {
          Text("Chave da API do Claude")
        } footer: {
          Text("Crie em console.anthropic.com › API Keys. Fica guardada só neste iPhone, no Keychain.")
        }

        Section {
          Picker("Modelo", selection: $settings.model) {
            ForEach(AppSettings.models, id: \.id) { Text($0.label).tag($0.id) }
          }
          Stepper(value: $settings.interval, in: 2...8, step: 1) {
            Text("Olhar a cada \(Int(settings.interval)) s")
          }
        } header: {
          Text("Leitura do tabuleiro")
        } footer: {
          Text("O app só olha o tabuleiro na vez do seu amigo. Cada olhada é uma chamada paga à API. Intervalos maiores gastam menos, mas o lance demora mais pra chegar.")
        }

        if glasses.isRegistered {
          Section {
            Button("Desligar câmera do óculos") { glasses.stopCamera() }
            Button("Desconectar óculos", role: .destructive) { glasses.disconnect() }
          }
        }
      }
      .navigationTitle("Ajustes")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
      }
    }
  }
}
