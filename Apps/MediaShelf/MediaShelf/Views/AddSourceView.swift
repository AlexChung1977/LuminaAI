import SwiftUI
import MediaShelfCore

struct AddSourceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: SourceKind = .smb
    @State private var rootURI = "smb://nas.local/media"
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("基本") {
                    TextField("顯示名稱", text: $name)
                    Picker("類型", selection: $kind) {
                        Text("本機資料夾").tag(SourceKind.localFolder)
                        Text("SMB（區網）").tag(SourceKind.smb)
                        Text("WebDAV（外出）").tag(SourceKind.webdav)
                    }
                    #if os(macOS)
                    .pickerStyle(.radioGroup)
                    #endif
                }

                Section("連線") {
                    TextField(uriPlaceholder, text: $rootURI)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                        #if os(macOS)
                        .font(.body.monospaced())
                        #endif
                    if kind != .localFolder {
                        TextField("帳號", text: $username)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                        SecureField("密碼", text: $password)
                    }
                }

                Section {
                    Text(helpText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("新增來源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("新增") {
                        Task {
                            await model.addSource(
                                name: name.isEmpty ? defaultName : name,
                                kind: kind,
                                rootURI: rootURI,
                                username: username,
                                password: password
                            )
                        }
                    }
                    .disabled(rootURI.isEmpty)
                }
            }
            .onChange(of: kind) { _, newValue in
                switch newValue {
                case .smb:
                    if rootURI.hasPrefix("http") || rootURI.hasPrefix("/") {
                        rootURI = "smb://nas.local/media"
                    }
                case .webdav:
                    if rootURI.hasPrefix("smb:") || (!rootURI.hasPrefix("http") && !rootURI.isEmpty && kind == .webdav) {
                        rootURI = "https://nas.example.com/webdav/media"
                    }
                    if !rootURI.hasPrefix("http") {
                        rootURI = "https://nas.example.com/webdav/media"
                    }
                case .localFolder:
                    rootURI = ""
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    private var uriPlaceholder: String {
        switch kind {
        case .localFolder: return "本機路徑，例如 /Users/me/Pictures"
        case .smb: return "smb://host/share/path"
        case .webdav: return "https://host/webdav/path"
        }
    }

    private var defaultName: String {
        switch kind {
        case .localFolder: return "本機資料夾"
        case .smb: return "NAS · LAN"
        case .webdav: return "NAS · Away"
        }
    }

    private var helpText: String {
        switch kind {
        case .localFolder:
            return "直接掃描本機磁碟上的圖片與影片。"
        case .smb:
            return "家用區網建議使用 SMB。初版內建模擬 transport，接上 AMSMB2 後即可打真 NAS。"
        case .webdav:
            return "外出備援。請優先 HTTPS WebDAV；外網不建議裸奔 SMB。"
        }
    }
}
