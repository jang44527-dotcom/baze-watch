import SwiftUI

@main
struct BazeWatchPhoneApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 20) {
                Image(systemName: "applewatch").font(.system(size: 56))
                Text("Baze Watch").font(.largeTitle.bold())
                Text("설치 확인용 앱입니다. 애플워치에서도 Baze Watch를 열어주세요.")
                    .multilineTextAlignment(.center)
                Text("이 버전은 API 키나 네트워크를 사용하지 않습니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(28)
        }
    }
}
