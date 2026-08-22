import AppKit
import Combine
import SwiftUI

@MainActor
final class InstallerModel: ObservableObject {
    enum State {
        case checking, notInstalled, partial, installing, ready, failed
    }

    @Published var state: State = .checking
    @Published var phase = "확인 중"
    @Published var message = "현재 설치 상태를 확인하고 있습니다"
    @Published var log = ""
    @Published var showLog = false

    private var process: Process?

    var isBusy: Bool { state == .checking || state == .installing }

    var primaryTitle: String {
        switch state {
        case .ready: return "Windows Steam 열기"
        case .partial: return "설치 이어서 하기"
        case .failed: return "다시 시도"
        default: return "Windows Steam 준비하기"
        }
    }

    var statusTitle: String {
        switch state {
        case .checking: return "설치 상태 확인 중"
        case .notInstalled: return "설치 준비 완료"
        case .partial: return "이어서 설치할 수 있어요"
        case .installing: return phase
        case .ready: return "설치는 완료됐어요"
        case .failed: return "설치를 마치지 못했어요"
        }
    }

    init() { refresh() }

    func primaryAction() {
        if state == .ready {
            openSteam()
        } else {
            run(mode: "setup")
        }
    }

    func refresh() { run(mode: "check") }

    func openSteam() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Sikarugir/Steam.app")
        NSWorkspace.shared.open(url)
    }

    func openInstallFolder() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Sikarugir")
        NSWorkspace.shared.open(url)
    }

    func repairSteamUI() {
        run(mode: "repair")
    }

    private func run(mode: String) {
        guard process == nil else { return }
        guard let script = Bundle.main.path(forResource: "setup", ofType: "sh") else {
            state = .failed
            message = "앱 내부 설치 파일을 찾을 수 없습니다"
            return
        }

        state = mode == "check" ? .checking : .installing
        if mode == "setup" { log = "" }

        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [script, mode]
        task.standardOutput = pipe
        task.standardError = pipe
        let inherited = ProcessInfo.processInfo.environment
        task.environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "USER": NSUserName(),
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": inherited["TMPDIR"] ?? "/tmp",
            "LANG": "ko_KR.UTF-8",
            "LC_ALL": "ko_KR.UTF-8"
        ]

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.consume(text) }
        }

        task.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                self?.process = nil
                if finished.terminationStatus != 0 {
                    self?.state = .failed
                    if self?.message.isEmpty == true { self?.message = "자세한 내용은 설치 기록에서 확인할 수 있습니다" }
                } else if mode == "setup" {
                    self?.state = .ready
                    self?.phase = "설치 완료"
                }
            }
        }

        do {
            try task.run()
            process = task
        } catch {
            state = .failed
            message = error.localizedDescription
        }
    }

    private func consume(_ text: String) {
        log += text
        for line in text.split(separator: "\n") {
            let value = String(line)
            if value.hasPrefix("@@PHASE|") {
                phase = friendlyPhase(String(value.dropFirst(8)))
            } else if value.hasPrefix("@@MESSAGE|") {
                message = String(value.dropFirst(10))
            } else if value.hasPrefix("@@ERROR|") {
                message = String(value.dropFirst(8))
            } else if value == "@@STATE|ready" {
                state = .ready
                message = "Windows Steam이 준비됐습니다"
            } else if value == "@@STATE|partial" {
                state = .partial
                message = "중단된 지점부터 안전하게 이어서 설치합니다"
            } else if value == "@@STATE|not_installed" {
                state = .notInstalled
                message = "버튼을 누르면 필요한 항목만 자동으로 준비합니다"
            } else if value == "@@ACTION|steam_installer" {
                message = "열린 Steam 설치 창에서 기본 경로 그대로 설치해 주세요"
            }
        }
    }

    private func friendlyPhase(_ raw: String) -> String {
        [
            "checking": "Mac 확인 중",
            "rosetta": "Apple 실행 환경 준비 중",
            "downloading": "실행 엔진 다운로드 중",
            "wrapper": "Steam 앱 만드는 중",
            "windows": "Windows 환경 준비 중",
            "steam": "Windows Steam 설치 중",
            "configuring": "게임 실행 설정 적용 중",
            "repairing": "Steam 로그인 화면 복구 중",
            "ready": "설치 완료"
        ][raw] ?? "설치 중"
    }
}

struct ContentView: View {
    @StateObject private var model = InstallerModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Mac에서 Windows Steam")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("영상의 Sikarugir 방식을 복잡한 설정 없이 준비합니다.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 15) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(model.state == .ready ? Color.green.opacity(0.14) : Color.blue.opacity(0.12))
                    Image(systemName: model.state == .ready ? "checkmark.circle.fill" : "gamecontroller.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(model.state == .ready ? .green : .blue)
                }
                .frame(width: 68, height: 68)

                VStack(alignment: .leading, spacing: 5) {
                    Text(model.statusTitle).font(.title3.bold())
                    Text(model.message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if model.isBusy { ProgressView().controlSize(.large) }
            }
            .padding(18)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 10) {
                Label("Sikarugir 공식 실행 엔진과 앱 틀만 사용", systemImage: "checkmark.shield")
                Label("Steam 로그인과 게임 설치는 평소처럼 Steam에서 진행", systemImage: "person.crop.circle")
                Label("기존 Steam 앱이나 Porting Kit는 변경하지 않음", systemImage: "externaldrive")
            }
            .font(.callout)

            Button(action: model.primaryAction) {
                Text(model.primaryTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isBusy)

            HStack {
                if model.state == .ready {
                    Button("로그인 화면 복구", action: model.repairSteamUI)
                        .disabled(model.isBusy)
                }
                Button("설치 폴더 열기", action: model.openInstallFolder)
                    .disabled(model.state == .notInstalled || model.state == .checking)
                Spacer()
                Button(model.showLog ? "설치 기록 숨기기" : "설치 기록 보기") {
                    model.showLog.toggle()
                }
            }

            if model.showLog {
                ScrollView {
                    Text(model.log.isEmpty ? "아직 기록이 없습니다." : model.log)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 150)
                .padding(10)
                .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }

            Text("일부 게임과 안티치트는 호환되지 않을 수 있습니다. 이 앱은 게임이나 Windows를 포함하지 않습니다.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 620, height: model.showLog ? 650 : 500)
    }
}

@main
struct MacSteamSetupApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .windowResizability(.contentSize)
    }
}
