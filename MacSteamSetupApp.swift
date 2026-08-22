import AppKit
import Combine
import SwiftUI

struct SteamGame: Identifiable, Equatable {
    let id: String
    let name: String
    let installDirectory: String
}

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
    @Published var progress = 0.0
    @Published var transferText = ""
    @Published var needsUserAction = false
    @Published var operationInProgress = false
    @Published var games: [SteamGame] = []
    @Published var shortcutMessage = ""

    private var process: Process?
    private var pendingOutput = ""

    var isBusy: Bool { state == .checking || state == .installing || operationInProgress }

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
        run(mode: "launch")
    }

    func openInstallFolder() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Sikarugir")
        NSWorkspace.shared.open(url)
    }

    func repairSteamUI() {
        run(mode: "repair")
    }

    func stopSteam() {
        run(mode: "stop")
    }

    func loadGames() {
        games = []
        shortcutMessage = ""
        run(mode: "list-games", changesMainState: false)
    }

    func createShortcut(for game: SteamGame) {
        shortcutMessage = "\(game.name) 바로가기를 만드는 중입니다"
        run(mode: "create-shortcut", arguments: [game.id], changesMainState: false)
    }

    private func run(mode: String, arguments: [String] = [], changesMainState: Bool = true) {
        guard process == nil else { return }
        guard let script = Bundle.main.path(forResource: "setup", ofType: "sh") else {
            state = .failed
            message = "앱 내부 설치 파일을 찾을 수 없습니다"
            return
        }

        if mode == "check" {
            state = .checking
        } else if changesMainState {
            state = .installing
        }
        operationInProgress = true
        if mode == "setup" {
            log = ""
            progress = 0
            transferText = ""
        }
        needsUserAction = false

        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [script, mode] + arguments
        task.standardOutput = pipe
        task.standardError = pipe
        let inherited = ProcessInfo.processInfo.environment
        task.environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "USER": NSUserName(),
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": inherited["TMPDIR"] ?? "/tmp",
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8"
        ]

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.consumeChunk(text) }
        }

        task.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                if self?.pendingOutput.isEmpty == false {
                    self?.consumeLine(self?.pendingOutput ?? "")
                    self?.pendingOutput = ""
                }
                self?.process = nil
                self?.operationInProgress = false
                if finished.terminationStatus != 0 {
                    if changesMainState { self?.state = .failed }
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

    private func consumeChunk(_ text: String) {
        log += text
        pendingOutput += text
        while let newline = pendingOutput.firstIndex(of: "\n") {
            let line = String(pendingOutput[..<newline])
            pendingOutput.removeSubrange(...newline)
            consumeLine(line)
        }
    }

    private func consumeLine(_ value: String) {
        if value.hasPrefix("@@PHASE|") {
            let rawPhase = String(value.dropFirst(8))
            phase = friendlyPhase(rawPhase)
            if rawPhase != "steam" { needsUserAction = false }
        } else if value.hasPrefix("@@MESSAGE|") {
            message = String(value.dropFirst(10))
        } else if value.hasPrefix("@@ERROR|") {
            message = String(value.dropFirst(8))
        } else if value.hasPrefix("@@PROGRESS|") {
            let parts = value.split(separator: "|", omittingEmptySubsequences: false)
            if parts.count >= 2, let value = Double(parts[1]) {
                progress = min(max(value, 0), 100)
            }
        } else if value.hasPrefix("@@DOWNLOAD|") {
            let parts = value.split(separator: "|", omittingEmptySubsequences: false)
            if parts.count >= 4,
               let current = Int64(parts[2]),
               let total = Int64(parts[3]) {
                transferText = formatTransfer(label: String(parts[1]), current: current, total: total)
            }
        } else if value.hasPrefix("@@GAME|") {
            let parts = value.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
            if parts.count == 4 {
                let game = SteamGame(id: String(parts[1]), name: String(parts[2]), installDirectory: String(parts[3]))
                if !games.contains(game) { games.append(game) }
            }
        } else if value.hasPrefix("@@SHORTCUT|") {
            shortcutMessage = "Mac용 게임 바로가기를 만들었습니다"
        } else if value == "@@STATE|ready" {
            state = .ready
            progress = 100
            needsUserAction = false
            message = "Windows Steam이 준비됐습니다"
        } else if value == "@@STATE|running" {
            state = .ready
            progress = 100
            message = "Windows Steam이 이미 실행 중입니다"
        } else if value == "@@STATE|partial" {
            state = .partial
            message = "중단된 지점부터 안전하게 이어서 설치합니다"
        } else if value == "@@STATE|not_installed" {
            state = .notInstalled
            progress = 0
            message = "버튼을 누르면 필요한 항목만 자동으로 준비합니다"
        } else if value == "@@ACTION|steam_installer" {
            needsUserAction = true
            message = "Steam 설치 창에서 설치 완료까지 진행해 주세요. Steam 실행 여부는 상관없습니다"
        }
    }

    private func formatTransfer(label: String, current: Int64, total: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let currentText = formatter.string(fromByteCount: current)
        guard total > 0 else { return "\(label) · \(currentText)" }
        return "\(label) · \(currentText) / \(formatter.string(fromByteCount: total))"
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
            "launching": "Windows Steam 시작 중",
            "stopping": "Windows Steam 종료 중",
            "ready": "설치 완료"
        ][raw] ?? "설치 중"
    }
}

struct ContentView: View {
    @StateObject private var model = InstallerModel()
    @State private var showStopConfirmation = false
    @State private var showGameShortcuts = false

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
                if model.state == .checking { ProgressView().controlSize(.large) }
            }
            .padding(18)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 20))

            if model.state == .installing {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(model.needsUserAction ? "사용자 작업 필요" : "전체 진행률")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(model.needsUserAction ? .orange : .secondary)
                        Spacer()
                        Text("\(Int(model.progress))%")
                            .font(.system(.callout, design: .rounded).monospacedDigit().weight(.semibold))
                    }
                    ProgressView(value: model.progress, total: 100)
                        .tint(model.needsUserAction ? .orange : .blue)
                    if !model.transferText.isEmpty {
                        Text(model.transferText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

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

            HStack(spacing: 12) {
                if model.state == .ready {
                    Button("게임 바로가기") {
                        showGameShortcuts = true
                        model.loadGames()
                    }
                    .disabled(model.isBusy)
                    Button("로그인 화면 복구", action: model.repairSteamUI)
                        .disabled(model.isBusy)
                    Button("Windows Steam 완전 종료") {
                        showStopConfirmation = true
                    }
                    .disabled(model.isBusy)
                }
                Spacer(minLength: 0)
            }

            HStack {
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
        .frame(
            width: 620,
            height: model.showLog ? 720 : (model.state == .installing ? 570 : 500)
        )
        .alert("Windows Steam을 완전히 종료할까요?", isPresented: $showStopConfirmation) {
            Button("취소", role: .cancel) {}
            Button("완전 종료", role: .destructive, action: model.stopSteam)
        } message: {
            Text("실행 중인 Windows 게임과 Steam 다운로드도 함께 종료됩니다.")
        }
        .sheet(isPresented: $showGameShortcuts) {
            GameShortcutSheet(model: model)
        }
    }
}

struct GameShortcutSheet: View {
    @ObservedObject var model: InstallerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("게임 바로가기")
                        .font(.title2.bold())
                    Text("Steam을 전면에 열지 않고 선택한 게임을 바로 시작하는 Mac 앱을 만듭니다.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("닫기", action: dismiss.callAsFunction)
            }

            if model.operationInProgress && model.games.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("설치된 게임을 찾는 중입니다")
                }
            } else if model.games.isEmpty {
                ContentUnavailableView(
                    "설치된 게임이 없습니다",
                    systemImage: "gamecontroller",
                    description: Text("Windows Steam에서 게임을 설치한 다음 다시 확인해 주세요.")
                )
            } else {
                List(model.games) { game in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(game.name).fontWeight(.semibold)
                            Text("Steam App ID \(game.id)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Mac 앱 만들기") {
                            model.createShortcut(for: game)
                        }
                        .disabled(model.operationInProgress)
                    }
                    .padding(.vertical, 4)
                }
            }

            if !model.shortcutMessage.isEmpty {
                Label(model.shortcutMessage, systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 560, height: 420)
    }
}

@main
struct MacSteamSetupApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .windowResizability(.contentSize)
    }
}
