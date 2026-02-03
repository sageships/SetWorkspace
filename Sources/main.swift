import SwiftUI
import AppKit

// MARK: - Models
struct WorkspaceConfig: Codable {
    var workspaces: [Workspace]
}

struct Workspace: Codable, Identifiable {
    var id: String { name }
    var name: String
    var nodeVersion: String?
    var repos: [Repo]
}

struct Repo: Codable, Identifiable {
    var id: String { name }
    var name: String
    var path: String
    var branch: String?
    var install: String?
    var run: String
}

enum RepoStatus: Equatable {
    case stopped
    case settingUp(String)  // Current step
    case running
    case error(String)
    
    var color: Color {
        switch self {
        case .stopped: return .gray
        case .settingUp: return .orange
        case .running: return .green
        case .error: return .red
        }
    }
    
    var label: String {
        switch self {
        case .stopped: return "stopped"
        case .settingUp(let step): return step
        case .running: return "running"
        case .error(let msg): return "error: \(msg)"
        }
    }
}

// MARK: - Workspace Manager
class WorkspaceManager: ObservableObject {
    @Published var config: WorkspaceConfig = WorkspaceConfig(workspaces: [])
    @Published var repoStatuses: [String: RepoStatus] = [:]
    @Published var repoProcesses: [String: Process] = [:]
    
    let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".setworkspace/config.json")
    
    init() {
        loadConfig()
    }
    
    func loadConfig() {
        do {
            let data = try Data(contentsOf: configPath)
            config = try JSONDecoder().decode(WorkspaceConfig.self, from: data)
            // Initialize statuses
            for workspace in config.workspaces {
                for repo in workspace.repos {
                    let key = "\(workspace.name):\(repo.name)"
                    if repoStatuses[key] == nil {
                        repoStatuses[key] = .stopped
                    }
                }
            }
        } catch {
            print("No config found or error loading: \(error)")
            createDefaultConfig()
        }
    }
    
    func createDefaultConfig() {
        let defaultConfig = WorkspaceConfig(workspaces: [
            Workspace(
                name: "peakflo",
                nodeVersion: "20.17.0",
                repos: [
                    Repo(name: "peakflo-web", path: "~/Developer/peakflo-web", branch: "main", install: "yarn", run: "yarn dev"),
                    Repo(name: "billing-api", path: "~/Developer/billing-api", branch: "main", install: "yarn", run: "yarn emulators"),
                    Repo(name: "upload-function", path: "~/Developer/upload-function", branch: "main", install: "yarn", run: "yarn dev")
                ]
            )
        ])
        
        do {
            let dir = configPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(defaultConfig)
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            let prettyData = try JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)
            try prettyData.write(to: configPath)
            config = defaultConfig
            print("Created default config at \(configPath.path)")
        } catch {
            print("Error creating default config: \(error)")
        }
        
        for workspace in config.workspaces {
            for repo in workspace.repos {
                repoStatuses["\(workspace.name):\(repo.name)"] = .stopped
            }
        }
    }
    
    func expandPath(_ path: String) -> String {
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(path.dropFirst(2))).path
        }
        return path
    }
    
    func startWorkspace(_ workspace: Workspace) {
        for repo in workspace.repos {
            startRepo(workspace: workspace, repo: repo)
        }
    }
    
    func stopWorkspace(_ workspace: Workspace) {
        for repo in workspace.repos {
            stopRepo(workspace: workspace, repo: repo)
        }
    }
    
    func startRepo(workspace: Workspace, repo: Repo) {
        let key = "\(workspace.name):\(repo.name)"
        let repoPath = expandPath(repo.path)
        
        // Check if path exists
        guard FileManager.default.fileExists(atPath: repoPath) else {
            DispatchQueue.main.async {
                self.repoStatuses[key] = .error("path not found")
            }
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.runRepoSetup(workspace: workspace, repo: repo, key: key, repoPath: repoPath)
        }
    }
    
    func runRepoSetup(workspace: Workspace, repo: Repo, key: String, repoPath: String) {
        // Build the setup script
        var script = "cd \"\(repoPath)\" && "
        
        // Load nvm and switch node version
        if let nodeVersion = workspace.nodeVersion {
            DispatchQueue.main.async { self.repoStatuses[key] = .settingUp("nvm use \(nodeVersion)") }
            script += "export NVM_DIR=\"$HOME/.nvm\" && [ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\" && nvm use \(nodeVersion) && "
        }
        
        // Git checkout and pull
        if let branch = repo.branch {
            DispatchQueue.main.async { self.repoStatuses[key] = .settingUp("git checkout \(branch)") }
            script += "git checkout \(branch) && git pull && "
        }
        
        // Install dependencies
        if let install = repo.install {
            DispatchQueue.main.async { self.repoStatuses[key] = .settingUp(install) }
            script += "\(install) && "
        }
        
        // Run dev command
        DispatchQueue.main.async { self.repoStatuses[key] = .settingUp(repo.run) }
        script += "exec \(repo.run)"
        
        // Create and run process
        let process = Process()
        process.launchPath = "/bin/zsh"
        process.arguments = ["-c", script]
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        
        // Set up pipes for output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Store process
        DispatchQueue.main.async {
            self.repoProcesses[key] = process
        }
        
        // Monitor for errors in first few seconds
        var hasStarted = false
        
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                if let output = String(data: data, encoding: .utf8) {
                    print("[\(repo.name)] \(output)")
                    if !hasStarted && (output.contains("ready") || output.contains("started") || output.contains("listening") || output.contains("compiled") || output.contains("Local:")) {
                        hasStarted = true
                        DispatchQueue.main.async {
                            self.repoStatuses[key] = .running
                        }
                    }
                }
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                if let output = String(data: data, encoding: .utf8) {
                    print("[\(repo.name) ERR] \(output)")
                }
            }
        }
        
        do {
            try process.run()
            
            // After 5 seconds, if still running assume it's good
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if process.isRunning && self.repoStatuses[key] != .running {
                    self.repoStatuses[key] = .running
                }
            }
            
            // Wait for process to exit (in background)
            process.waitUntilExit()
            
            DispatchQueue.main.async {
                self.repoProcesses.removeValue(forKey: key)
                if process.terminationStatus != 0 && self.repoStatuses[key] != .stopped {
                    self.repoStatuses[key] = .error("exit \(process.terminationStatus)")
                } else {
                    self.repoStatuses[key] = .stopped
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.repoStatuses[key] = .error(error.localizedDescription)
            }
        }
    }
    
    func stopRepo(workspace: Workspace, repo: Repo) {
        let key = "\(workspace.name):\(repo.name)"
        
        if let process = repoProcesses[key] {
            // Kill process group
            let pid = process.processIdentifier
            kill(-pid, SIGTERM)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if process.isRunning {
                    kill(-pid, SIGKILL)
                }
            }
            
            repoProcesses.removeValue(forKey: key)
        }
        
        repoStatuses[key] = .stopped
    }
    
    func isWorkspaceRunning(_ workspace: Workspace) -> Bool {
        for repo in workspace.repos {
            let key = "\(workspace.name):\(repo.name)"
            if case .running = repoStatuses[key] {
                return true
            }
            if case .settingUp = repoStatuses[key] {
                return true
            }
        }
        return false
    }
    
    func openConfig() {
        NSWorkspace.shared.open(configPath)
    }
}

// MARK: - Views
struct MenuView: View {
    @ObservedObject var manager: WorkspaceManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("⚡")
                Text("SetWorkspace")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: { manager.loadConfig() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Reload config")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            if manager.config.workspaces.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No workspaces configured")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Button("Open Config") {
                        manager.openConfig()
                    }
                    .font(.system(size: 11))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(manager.config.workspaces) { workspace in
                            WorkspaceView(workspace: workspace, manager: manager)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 400)
            }
            
            Divider()
            
            // Footer buttons
            HStack {
                Button(action: { manager.openConfig() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "gear")
                            .font(.system(size: 11))
                        Text("Config")
                            .font(.system(size: 12))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Text("Quit")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 300)
    }
}

struct WorkspaceView: View {
    let workspace: Workspace
    @ObservedObject var manager: WorkspaceManager
    @State private var isExpanded = true
    
    var isRunning: Bool {
        manager.isWorkspaceRunning(workspace)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Workspace header
            HStack {
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                
                Text(workspace.name)
                    .font(.system(size: 13, weight: .medium))
                
                if let nodeVersion = workspace.nodeVersion {
                    Text("node \(nodeVersion)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                }
                
                Spacer()
                
                // Start/Stop buttons
                if isRunning {
                    Button(action: { manager.stopWorkspace(workspace) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9))
                            Text("Stop")
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: { manager.startWorkspace(workspace) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9))
                            Text("Start")
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            
            // Repos list
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(workspace.repos) { repo in
                        RepoRowView(workspace: workspace, repo: repo, manager: manager)
                    }
                }
                .padding(.leading, 28)
            }
        }
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
        .padding(.horizontal, 8)
    }
}

struct RepoRowView: View {
    let workspace: Workspace
    let repo: Repo
    @ObservedObject var manager: WorkspaceManager
    @State private var isHovering = false
    
    var status: RepoStatus {
        manager.repoStatuses["\(workspace.name):\(repo.name)"] ?? .stopped
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(repo.name)
                    .font(.system(size: 12))
                Text(status.label)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isHovering {
                if case .running = status {
                    Button(action: { manager.stopRepo(workspace: workspace, repo: repo) }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                } else if case .stopped = status {
                    Button(action: { manager.startRepo(workspace: workspace, repo: repo) }) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                } else if case .error = status {
                    Button(action: { manager.startRepo(workspace: workspace, repo: repo) }) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovering ? Color.primary.opacity(0.05) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let manager = WorkspaceManager()
    var eventMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "SetWorkspace")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MenuView(manager: manager))
        
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Stop all processes on quit
        for workspace in manager.config.workspaces {
            manager.stopWorkspace(workspace)
        }
        
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }
}

// MARK: - Main
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
