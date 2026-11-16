import SwiftUI

@main
struct BazeWatchApp: App {
    var body: some Scene {
        WindowGroup { InstallationCheckView() }
    }
}

struct InstallationCheckView: View {
    @State private var count = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle).foregroundStyle(.green)
                Text("Baze Watch").font(.headline)
                Text("워치 앱 실행 성공!").multilineTextAlignment(.center)
                Button("버튼 테스트 \(count)") { count += 1 }
                Text("다음 단계에서 음성 질문과 AI 답변을 연결합니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(.horizontal, 8)
        }
    }
}
