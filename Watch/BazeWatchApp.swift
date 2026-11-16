import SwiftUI
import AVFoundation
import Security

@main
struct BazeWatchApp: App {
    var body: some Scene { WindowGroup { ChatView() } }
}

enum KeyStore {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.bazewatch.personal.apikey",
        kSecAttrAccount as String: "baze"
    ]
    static func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        guard !UserDefaults.standard.bool(forKey: "bundledKeyDisabled"),
              let url = Bundle.main.url(forResource: "BazeLocalKey", withExtension: "txt"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, save(value) else { return nil }
        return value
    }
    static func save(_ value: String) -> Bool {
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            UserDefaults.standard.set(true, forKey: "bundledKeyDisabled")
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

struct Reply: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}

@MainActor
final class Chat: ObservableObject {
    @AppStorage("baseURL") var baseURL = "https://api.baze.co/v1/gateway"
    @AppStorage("model") var model = "gpt-6.1-sol"
    @AppStorage("autoSpeak") var autoSpeak = true
    @Published var prompt = ""
    @Published var answer = ""
    @Published var status = ""
    @Published var busy = false
    private let speaker = AVSpeechSynthesizer()

    func send() async {
        guard !busy else { return }
        let question = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { status = "질문을 입력해줘."; return }
        guard let key = KeyStore.load(), !key.isEmpty else { status = "설정에서 API 키를 저장해줘."; return }
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/chat/completions"), url.scheme?.lowercased() == "https", url.host != nil else {
            status = "HTTPS API 주소를 확인해줘."
            return
        }
        busy = true
        status = "답변을 기다리는 중…"
        defer { busy = false }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 60
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "messages": [["role": "user", "content": question]], "stream": false])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { status = "서버 응답이 올바르지 않아."; return }
            guard (200...299).contains(response.statusCode) else { status = "서버 오류 HTTP \(response.statusCode). 주소, 모델, 키를 확인해줘."; return }
            let reply = try JSONDecoder().decode(Reply.self, from: data)
            guard let content = reply.choices.first?.message.content, !content.isEmpty else { status = "답변이 비어 있어."; return }
            answer = content
            status = ""
            if autoSpeak { speak() }
        } catch {
            status = "연결 또는 응답 처리에 실패했어. 네트워크와 API 설정을 확인해줘."
        }
    }
    func speak() {
        guard !answer.isEmpty else { return }
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: answer)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        speaker.speak(utterance)
    }
}

struct ChatView: View {
    @StateObject private var chat = Chat()
    @State private var showSettings = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    TextField("질문 입력 또는 받아쓰기", text: $chat.prompt, axis: .vertical)
                    Text("입력창의 마이크로 말해줘").font(.footnote).foregroundStyle(.secondary)
                    Button(chat.busy ? "답변 기다리는 중…" : "질문 보내기") { Task { await chat.send() } }
                        .disabled(chat.busy)
                    if !chat.status.isEmpty { Text(chat.status).font(.footnote).foregroundStyle(.secondary) }
                    if !chat.answer.isEmpty {
                        Text(chat.answer).frame(maxWidth: .infinity, alignment: .leading)
                        Button("다시 읽기") { chat.speak() }
                    }
                }
            }
            .navigationTitle("BAZE")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showSettings = true } label: { Image(systemName: "gearshape") } } }
            .sheet(isPresented: $showSettings) { SettingsView(chat: chat) }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var chat: Chat
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var message = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("BAZE API 기본 주소", text: $chat.baseURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("모델 이름", text: $chat.model)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("답변 자동 읽기", isOn: $chat.autoSpeak)
                SecureField("API 키", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("API 키 저장") {
                    guard !key.isEmpty else { message = "키를 입력해줘."; return }
                    if KeyStore.save(key) { key = ""; message = "키를 저장했어." } else { message = "키 저장에 실패했어." }
                }
                Button("저장된 키 삭제", role: .destructive) { message = KeyStore.save("") ? "키를 삭제했어." : "키 삭제에 실패했어." }
                if !message.isEmpty { Text(message).font(.footnote) }
            }
            .navigationTitle("설정")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
    }
}
