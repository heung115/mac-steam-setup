import AppKit
import Combine
import Foundation
import SwiftUI

enum L10n {
    static func string(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }

    static var languageCode: String {
        Bundle.main.preferredLocalizations.first == "ko" ? "ko" : "en"
    }
}

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
    @Published var phase = L10n.string("phase.checking")
    @Published var message = L10n.string("message.checkingInstallation")
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
        if state == .ready && isSteamRunning { return L10n.string("steam.running") }
        switch state {
        case .ready: return L10n.string("steam.open")
        case .partial: return L10n.string("setup.resume")
        case .failed: return L10n.string("common.retry")
        default: return L10n.string("setup.prepare")
        }
    }

    var statusTitle: String {
        if state == .ready, let runtimeStatusTitle { return runtimeStatusTitle }
        if state == .ready && isSteamRunning { return L10n.string("steam.running") }
        switch state {
        case .checking: return L10n.string("status.checking")
        case .notInstalled: return L10n.string("status.readyToInstall")
        case .partial: return L10n.string("status.canResume")
        case .installing: return phase
        case .ready: return L10n.string("status.steamReady")
        case .failed: return L10n.string("status.setupFailed")
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
                self.message = running
                    ? L10n.string("message.steamRunning")
                    : L10n.string("message.steamStopped")
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
        shortcutMessage = L10n.format("shortcut.creating", game.name)
        run(mode: "create-shortcut", arguments: [game.id], changesMainState: false)
    }

    private func run(mode: String, arguments: [String] = [], changesMainState: Bool = true) {
        guard process == nil else { return }
        guard let script = Bundle.main.path(forResource: "setup", ofType: "sh") else {
            if mode == "list-games" { pendingGames = nil }
            if changesMainState { state = .failed }
            message = L10n.string("error.internalScriptMissing")
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
                    if self?.message.isEmpty == true { self?.message = L10n.string("error.seeLog") }
                } else if mode == "setup" {
                    self?.state = .ready
                    self?.phase = L10n.string("phase.complete")
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
            "LC_ALL": "en_US.UTF-8",
            "MACSTEAM_UI_LANGUAGE": L10n.languageCode
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
            shortcutMessage = L10n.string("shortcut.created")
        } else if value == "@@STATE|ready" {
            state = .ready
            isSteamRunning = false
            progress = 100
            needsUserAction = false
            message = L10n.string("message.steamReady")
        } else if value == "@@STATE|running" {
            state = .ready
            isSteamRunning = true
            progress = 100
            message = L10n.string("message.steamAlreadyRunning")
        } else if value == "@@STATE|partial" {
            state = .partial
            message = L10n.string("message.resumeSetup")
        } else if value == "@@STATE|not_installed" {
            state = .notInstalled
            progress = 0
            message = L10n.string("message.prepareSetup")
        } else if value == "@@ACTION|steam_installer" {
            needsUserAction = true
            message = L10n.string("message.steamInstallerAction")
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

        guard L10n.languageCode == "ko" else { return }
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
            "checking": L10n.string("phase.macCheck"),
            "rosetta": L10n.string("phase.rosetta"),
            "downloading": L10n.string("phase.downloading"),
            "wrapper": L10n.string("phase.wrapper"),
            "windows": L10n.string("phase.windows"),
            "steam": L10n.string("phase.steam"),
            "configuring": L10n.string("phase.configuring"),
            "repairing": L10n.string("phase.repairing"),
            "launching": L10n.string("phase.launching"),
            "stopping": L10n.string("phase.stopping"),
            "ready": L10n.string("phase.complete")
        ][raw] ?? L10n.string("phase.installing")
    }

    private func runtimeTitle(for mode: String) -> String? {
        [
            "launch": L10n.string("phase.launching"),
            "stop": L10n.string("phase.stopping"),
            "repair": L10n.string("phase.repairing")
        ][mode]
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case games
    case management

    var id: String { rawValue }
    var title: String {
        self == .games ? L10n.string("section.games") : L10n.string("section.management")
    }
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
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 250)
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
        .frame(width: 900, height: 590)
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
        .alert(L10n.string("alert.stop.title"), isPresented: $showStopConfirmation) {
            Button(L10n.string("common.cancel"), role: .cancel) {}
            Button(L10n.string("alert.stop.confirm"), role: .destructive, action: model.stopSteam)
        } message: {
            Text(L10n.string("alert.stop.message"))
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
                    Text(L10n.string("games.title"))
                        .font(.largeTitle.bold())
                    Text(L10n.string("games.subtitle"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.state == .ready {
                    Button {
                        model.openSteam()
                    } label: {
                        Label(
                            model.isSteamRunning
                                ? L10n.string("games.showSteam")
                                : L10n.string("games.startSteam"),
                            systemImage: model.isSteamRunning ? "macwindow" : "play.fill"
                        )
                    }
                    .disabled(model.operationInProgress)

                    Button {
                        model.loadGames()
                    } label: {
                        Label(L10n.string("common.refresh"), systemImage: "arrow.clockwise")
                    }
                    .disabled(model.operationInProgress)
                }
            }
            .padding(.bottom, 22)

            if model.state == .checking {
                Spacer()
                ProgressView(L10n.string("games.loading"))
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if model.state != .ready {
                Spacer()
                ContentUnavailableView {
                    Label(L10n.string("games.setupRequired"), systemImage: "externaldrive.badge.plus")
                } description: {
                    Text(L10n.string("games.setupRequired.detail"))
                } actions: {
                    Button(L10n.string("games.openManagement"), action: openManagement)
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
            } else if model.operationInProgress && model.games.isEmpty {
                Spacer()
                ProgressView(L10n.string("games.finding"))
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if model.games.isEmpty {
                Spacer()
                ContentUnavailableView(
                    L10n.string("games.empty"),
                    systemImage: "gamecontroller",
                    description: Text(L10n.string("games.empty.detail"))
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
                        Button(L10n.string("games.createShortcut")) {
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
                    Text(L10n.string("management.title"))
                        .font(.largeTitle.bold())
                    Text(L10n.string("management.subtitle"))
                        .foregroundStyle(.secondary)
                }

                StatusCard(model: model)

                if model.state == .installing {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(
                                model.needsUserAction
                                    ? L10n.string("management.userAction")
                                    : L10n.string("management.overallProgress")
                            )
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
                    GroupBox(L10n.string("management.tools")) {
                        VStack(spacing: 0) {
                            ManagementRow(
                                title: "Windows Steam",
                                detail: model.isSteamRunning
                                    ? L10n.string("management.steam.stopDetail")
                                    : L10n.string("management.steam.openDetail"),
                                icon: model.isSteamRunning ? "power" : "play.fill",
                                actionTitle: model.isSteamRunning
                                    ? L10n.string("common.stop")
                                    : L10n.string("common.open"),
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
                                title: L10n.string("management.repair.title"),
                                detail: L10n.string("management.repair.detail"),
                                icon: "wrench.and.screwdriver",
                                actionTitle: L10n.string("common.repair"),
                                action: model.repairSteamUI
                            )
                        }
                        .padding(.vertical, 4)
                    }
                }

                HStack {
                    Button(L10n.string("management.openFolder"), action: model.openInstallFolder)
                        .disabled(model.state == .notInstalled || model.state == .checking)
                    Spacer()
                    Button(
                        model.showLog
                            ? L10n.string("management.hideLog")
                            : L10n.string("management.showLog")
                    ) {
                        model.showLog.toggle()
                    }
                }

                if model.showLog {
                    ScrollView {
                        Text(model.log.isEmpty ? L10n.string("management.noLog") : model.log)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 140)
                    .padding(12)
                    .background(.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("disclaimer.compatibility"))
                    Text(L10n.string("disclaimer.unaffiliated"))
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
