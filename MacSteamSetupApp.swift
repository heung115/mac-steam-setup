import AppKit
import Combine
import Foundation
import SwiftUI

struct SteamGame: Identifiable, Equatable {
    let id: String
    let name: String
    let installDirectory: String
    let iconPath: String?
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
    @Published var isSteamRunning = false
    @Published var games: [SteamGame] = []
    @Published var localizedGameNames: [String: String] = [:]
    @Published var shortcutMessage = ""
    @Published private(set) var runtimeStatusTitle: String?

    private var process: Process?
    private var runtimeProcess: Process?
    private var pendingOutput = ""
    private var statusTimer: AnyCancellable?
    private var requestedLocalizedNames: Set<String> = []
    private var pendingGames: [SteamGame]?

    var isBusy: Bool { state == .checking || state == .installing || operationInProgress }

    var primaryTitle: String {
        if state == .ready && isSteamRunning { return "Windows Steam 실행 중" }
        switch state {
        case .ready: return "Windows Steam 열기"
        case .partial: return "설치 이어서 하기"
        case .failed: return "다시 시도"
        default: return "Windows Steam 준비하기"
        }
    }

    var statusTitle: String {
        if state == .ready, let runtimeStatusTitle { return runtimeStatusTitle }
        if state == .ready && isSteamRunning { return "Windows Steam 실행 중" }
        switch state {
        case .checking: return "설치 상태 확인 중"
        case .notInstalled: return "설치 준비 완료"
        case .partial: return "이어서 설치할 수 있어요"
        case .installing: return phase
        case .ready: return "설치는 완료됐어요"
        case .failed: return "설치를 마치지 못했어요"
        }
    }

    init() {
        refresh()
        statusTimer = Timer.publish(every: 2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshRuntimeStatus() }
    }

    func primaryAction() {
        if state == .ready {
            openSteam()
        } else {
            run(mode: "setup")
        }
    }

    func refresh() { run(mode: "check") }

    func openSteam() {
        // Starting or foregrounding Steam is a runtime operation. Keep the
        // installed-game library visible instead of showing installation UI.
        run(mode: "launch", changesMainState: false)
    }

    func openInstallFolder() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Sikarugir")
        NSWorkspace.shared.open(url)
    }

    func repairSteamUI() {
        run(mode: "repair", changesMainState: false)
    }

    func stopSteam() {
        run(mode: "stop", changesMainState: false)
    }

    private func refreshRuntimeStatus() {
        guard state == .ready, !operationInProgress, runtimeProcess == nil,
              let script = Bundle.main.path(forResource: "setup", ofType: "sh") else { return }

        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [script, "runtime-status"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        task.environment = taskEnvironment()
        task.terminationHandler = { [weak self] _ in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                guard let self else { return }
                self.runtimeProcess = nil
                let running: Bool
                if output.contains("@@RUNTIME|running") {
                    running = true
                } else if output.contains("@@RUNTIME|stopped") {
                    running = false
                } else {
                    return
                }
                guard running != self.isSteamRunning else { return }
                self.isSteamRunning = running
                self.message = running ? "Windows Steam이 실행 중입니다" : "Windows Steam이 종료됐습니다"
            }
        }
        runtimeProcess = task
        do {
            try task.run()
        } catch {
            runtimeProcess = nil
        }
    }

    func loadGames() {
        guard process == nil else { return }
        pendingGames = []
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
            if mode == "list-games" { pendingGames = nil }
            if changesMainState { state = .failed }
            message = "앱 내부 설치 파일을 찾을 수 없습니다"
            return
        }

        if mode == "check" {
            state = .checking
        } else if changesMainState {
            state = .installing
        }
        runtimeStatusTitle = runtimeTitle(for: mode)
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
        task.environment = taskEnvironment()

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.consumeChunk(text) }
        }

        task.terminationHandler = { [weak self] finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
            let remainingText = String(data: remainingData, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                if !remainingText.isEmpty {
                    self?.consumeChunk(remainingText)
                }
                if self?.pendingOutput.isEmpty == false {
                    self?.consumeLine(self?.pendingOutput ?? "")
                    self?.pendingOutput = ""
                }
                self?.process = nil
                self?.operationInProgress = false
                self?.runtimeStatusTitle = nil
                if mode == "list-games" {
                    if finished.terminationStatus == 0, let loadedGames = self?.pendingGames {
                        self?.games = loadedGames
                    }
                    self?.pendingGames = nil
                }
                if finished.terminationStatus != 0 {
                    if changesMainState { self?.state = .failed }
                    if self?.message.isEmpty == true { self?.message = "자세한 내용은 설치 기록에서 확인할 수 있습니다" }
                } else if mode == "setup" {
                    self?.state = .ready
                    self?.phase = "설치 완료"
                }
            }
        }

        process = task
        do {
            try task.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            process = nil
            operationInProgress = false
            runtimeStatusTitle = nil
            if mode == "list-games" { pendingGames = nil }
            if changesMainState { state = .failed }
            message = error.localizedDescription
        }
    }

    private func taskEnvironment() -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        return [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "USER": NSUserName(),
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": inherited["TMPDIR"] ?? "/tmp",
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8"
        ]
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
            if runtimeStatusTitle == nil, parts.count >= 2, let value = Double(parts[1]) {
                progress = min(max(value, 0), 100)
            }
        } else if value.hasPrefix("@@DOWNLOAD|") {
            let parts = value.split(separator: "|", omittingEmptySubsequences: false)
            if parts.count >= 4,
               let current = Int64(parts[2]),
               let total = Int64(parts[3]) {
                transferText = formatTransfer(label: String(parts[1]), current: current, total: total)
            }
        } else if value.hasPrefix("@@GAME64|") {
            let parts = value.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false)
            if parts.count == 5,
               let name = decodeProtocolField(parts[2]),
               let installDirectory = decodeProtocolField(parts[3]),
               let rawIconPath = decodeProtocolField(parts[4]) {
                let game = SteamGame(
                    id: String(parts[1]),
                    name: name,
                    installDirectory: installDirectory,
                    iconPath: rawIconPath.isEmpty ? nil : rawIconPath
                )
                if pendingGames != nil, pendingGames?.contains(game) == false {
                    pendingGames?.append(game)
                    fetchLocalizedName(for: game)
                } else if pendingGames == nil, !games.contains(game) {
                    games.append(game)
                    fetchLocalizedName(for: game)
                }
            }
        } else if value.hasPrefix("@@SHORTCUT|") {
            shortcutMessage = "Mac용 게임 바로가기를 만들었습니다"
        } else if value == "@@STATE|ready" {
            state = .ready
            isSteamRunning = false
            progress = 100
            needsUserAction = false
            message = "Windows Steam이 준비됐습니다"
        } else if value == "@@STATE|running" {
            state = .ready
            isSteamRunning = true
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

    private func decodeProtocolField(_ value: Substring) -> String? {
        guard let data = Data(base64Encoded: String(value)) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func formatTransfer(label: String, current: Int64, total: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let currentText = formatter.string(fromByteCount: current)
        guard total > 0 else { return "\(label) · \(currentText)" }
        return "\(label) · \(currentText) / \(formatter.string(fromByteCount: total))"
    }

    private func fetchLocalizedName(for game: SteamGame) {
        guard game.id.allSatisfy(\.isNumber), !requestedLocalizedNames.contains(game.id) else { return }
        requestedLocalizedNames.insert(game.id)

        let cacheKey = "localizedGameName.ko.\(game.id)"
        if let cached = UserDefaults.standard.string(forKey: cacheKey), !cached.isEmpty {
            if cached.caseInsensitiveCompare(game.name) != .orderedSame {
                localizedGameNames[game.id] = cached
            }
            return
        }

        guard let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(game.id)&l=koreana&cc=KR") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            guard let data,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let app = root[game.id] as? [String: Any],
                  app["success"] as? Bool == true,
                  let details = app["data"] as? [String: Any],
                  let localizedName = details["name"] as? String,
                  !localizedName.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                UserDefaults.standard.set(localizedName, forKey: cacheKey)
                if localizedName.caseInsensitiveCompare(game.name) != .orderedSame {
                    self.localizedGameNames[game.id] = localizedName
                }
            }
        }.resume()
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

    private func runtimeTitle(for mode: String) -> String? {
        [
            "launch": "Windows Steam 시작 중",
            "stop": "Windows Steam 종료 중",
            "repair": "Steam 로그인 화면 복구 중"
        ][mode]
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case games
    case management

    var id: String { rawValue }
    var title: String { self == .games ? "게임" : "설치 및 관리" }
    var icon: String { self == .games ? "gamecontroller.fill" : "gearshape.fill" }
}

struct ContentView: View {
    @StateObject private var model = InstallerModel()
    @State private var selection: AppSection? = .games
    @State private var showStopConfirmation = false

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("Windows Steam")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            switch selection ?? .games {
            case .games:
                GameLibraryView(model: model) {
                    selection = .management
                }
            case .management:
                ManagementView(model: model) {
                    showStopConfirmation = true
                }
            }
        }
        .frame(width: 860, height: 590)
        .onChange(of: selection) { _, section in
            if section == .games, model.state == .ready { model.loadGames() }
        }
        .onChange(of: model.state) { _, state in
            if state == .ready, selection == .games {
                model.loadGames()
            } else if state == .notInstalled || state == .partial || state == .failed {
                selection = .management
            }
        }
        .alert("Windows Steam을 완전히 종료할까요?", isPresented: $showStopConfirmation) {
            Button("취소", role: .cancel) {}
            Button("완전 종료", role: .destructive, action: model.stopSteam)
        } message: {
            Text("실행 중인 Windows 게임과 Steam 다운로드도 함께 종료됩니다.")
        }
    }
}

struct GameLibraryView: View {
    @ObservedObject var model: InstallerModel
    let openManagement: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("내 게임")
                        .font(.largeTitle.bold())
                    Text("Windows Steam에 설치된 게임을 바로 실행할 수 있게 준비합니다.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.state == .ready {
                    Button {
                        model.openSteam()
                    } label: {
                        Label(
                            model.isSteamRunning ? "Steam 창 보기" : "Steam 시작",
                            systemImage: model.isSteamRunning ? "macwindow" : "play.fill"
                        )
                    }
                    .disabled(model.operationInProgress)

                    Button {
                        model.loadGames()
                    } label: {
                        Label("새로고침", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.operationInProgress)
                }
            }
            .padding(.bottom, 22)

            if model.state == .checking {
                Spacer()
                ProgressView("게임을 불러오는 중입니다")
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if model.state != .ready {
                Spacer()
                ContentUnavailableView {
                    Label("Windows Steam 준비가 필요합니다", systemImage: "externaldrive.badge.plus")
                } description: {
                    Text("설치 및 관리에서 처음 한 번만 준비해 주세요.")
                } actions: {
                    Button("설치 및 관리로 이동", action: openManagement)
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
            } else if model.operationInProgress && model.games.isEmpty {
                Spacer()
                ProgressView("설치된 게임을 찾는 중입니다")
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if model.games.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "설치된 게임이 없습니다",
                    systemImage: "gamecontroller",
                    description: Text("Windows Steam에서 게임을 설치한 다음 새로고침해 주세요.")
                )
                Spacer()
            } else {
                List(model.games) { game in
                    HStack(spacing: 14) {
                        GameIconView(game: game)
                        VStack(alignment: .leading, spacing: 3) {
                            let localizedName = model.localizedGameNames[game.id]
                            Text(localizedName ?? game.name).fontWeight(.semibold)
                            Text(localizedName == nil ? "Steam App ID \(game.id)" : "\(game.name) · Steam App ID \(game.id)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("바로가기 만들기") {
                            model.createShortcut(for: game)
                        }
                        .disabled(model.operationInProgress)
                    }
                    .padding(.vertical, 7)
                }
                .listStyle(.inset)
            }

            if !model.shortcutMessage.isEmpty {
                Label(model.shortcutMessage, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .padding(.top, 12)
            }
        }
        .padding(28)
        .onAppear {
            if model.state == .ready { model.loadGames() }
        }
    }
}

struct GameIconView: View {
    let game: SteamGame

    var body: some View {
        Group {
            if let path = game.iconPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "gamecontroller.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
        }
        .frame(width: 40, height: 40)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct ManagementView: View {
    @ObservedObject var model: InstallerModel
    let confirmStop: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("설치 및 관리")
                        .font(.largeTitle.bold())
                    Text("Windows Steam 실행 환경과 문제 해결 도구를 관리합니다.")
                        .foregroundStyle(.secondary)
                }

                StatusCard(model: model)

                if model.state == .installing {
                    VStack(alignment: .leading, spacing: 9) {
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
                    .padding(16)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                }

                if model.state != .ready {
                    Button(action: model.primaryAction) {
                        Text(model.primaryTitle)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isBusy)
                }

                if model.state == .ready {
                    GroupBox("관리 도구") {
                        VStack(spacing: 0) {
                            ManagementRow(
                                title: "Windows Steam",
                                detail: model.isSteamRunning
                                    ? "Steam과 실행 중인 Windows 게임을 모두 종료합니다."
                                    : "설치된 Windows Steam을 시작합니다.",
                                icon: model.isSteamRunning ? "power" : "play.fill",
                                actionTitle: model.isSteamRunning ? "종료" : "열기",
                                isDisabled: model.isBusy,
                                action: {
                                    if model.isSteamRunning {
                                        confirmStop()
                                    } else {
                                        model.openSteam()
                                    }
                                }
                            )
                            Divider().padding(.leading, 42)
                            ManagementRow(
                                title: "로그인 화면 복구",
                                detail: "로그인 창이 비어 있거나 깨졌을 때 임시 데이터를 초기화합니다.",
                                icon: "wrench.and.screwdriver",
                                actionTitle: "복구",
                                action: model.repairSteamUI
                            )
                        }
                        .padding(.vertical, 4)
                    }
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
                    .frame(height: 140)
                    .padding(12)
                    .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("일부 게임과 안티치트는 호환되지 않을 수 있습니다.")
                    Text("Valve, Apple 또는 Sikarugir와 제휴·승인·후원 관계가 없는 비공식 프로젝트입니다.")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .padding(28)
        }
    }
}

struct StatusCard: View {
    @ObservedObject var model: InstallerModel

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: model.state == .ready ? "checkmark.circle.fill" : "externaldrive.fill")
                .font(.system(size: 30))
                .foregroundStyle(model.state == .ready ? .green : .blue)
                .frame(width: 58, height: 58)
                .background(
                    (model.state == .ready ? Color.green : Color.blue).opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(model.statusTitle).font(.headline)
                Text(model.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if model.state == .checking || model.runtimeStatusTitle != nil { ProgressView() }
        }
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ManagementRow: View {
    let title: String
    let detail: String
    let icon: String
    let actionTitle: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(actionTitle, action: action)
                .disabled(isDisabled)
        }
        .padding(.vertical, 10)
    }
}

@main
struct MacSteamSetupApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .windowResizability(.contentSize)
    }
}
