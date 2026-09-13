import Foundation

class AerospaceSpacesProvider: SpacesProvider, SwitchableSpacesProvider {
    typealias SpaceType = AeroSpace
    let executablePath = ConfigManager.shared.config.aerospace.path
    private let lockMarkerPath = "/tmp/aerospace-lock-active"
    private let modeStateQueue = DispatchQueue(label: "barik.aerospace.mode-state")
    private var lastKnownLockedMode = false

    func shouldFreezeUpdates() -> Bool {
        // The marker is created before the lock workspace transition, so it
        // closes the small race before AeroSpace has applied `mode locked`.
        if FileManager.default.fileExists(atPath: lockMarkerPath) {
            modeStateQueue.sync { lastKnownLockedMode = true }
            return true
        }

        guard
            let data = runAerospaceCommand(arguments: ["list-modes", "--current"]),
            let output = String(data: data, encoding: .utf8)
        else {
            // If the mode query briefly fails during a lock, fail closed and
            // keep the last stable workspace model instead of flashing `L`.
            return modeStateQueue.sync { lastKnownLockedMode }
        }

        let modes = output.split(whereSeparator: { $0.isWhitespace })
        guard !modes.isEmpty else {
            return modeStateQueue.sync { lastKnownLockedMode }
        }

        let isLocked = modes.contains("locked")
        modeStateQueue.sync { lastKnownLockedMode = isLocked }
        return isLocked
    }

    func getSpacesWithWindows() -> [AeroSpace]? {
        guard var spaces = fetchSpaces(), let windows = fetchWindows() else {
            return nil
        }
        if let focusedSpace = fetchFocusedSpace() {
            for i in 0..<spaces.count {
                spaces[i].isFocused = (spaces[i].id == focusedSpace.id)
            }
        }
        let focusedWindow = fetchFocusedWindow()
        var spaceDict = Dictionary(
            uniqueKeysWithValues: spaces.map { ($0.id, $0) })
        for window in windows {
            var mutableWindow = window
            if let focused = focusedWindow, window.id == focused.id {
                mutableWindow.isFocused = true
            }
            if let ws = mutableWindow.workspace, !ws.isEmpty {
                if var space = spaceDict[ws] {
                    space.windows.append(mutableWindow)
                    spaceDict[ws] = space
                }
            } else if let focusedSpace = fetchFocusedSpace() {
                if var space = spaceDict[focusedSpace.id] {
                    space.windows.append(mutableWindow)
                    spaceDict[focusedSpace.id] = space
                }
            }
        }
        var resultSpaces = Array(spaceDict.values)
        for i in 0..<resultSpaces.count {
            resultSpaces[i].windows.sort { $0.id < $1.id }
        }
        return resultSpaces.filter { !$0.windows.isEmpty }
    }

    func focusSpace(spaceId: String, needWindowFocus: Bool) {
        guard !shouldFreezeUpdates() else { return }
        _ = runAerospaceCommand(arguments: ["workspace", spaceId])
    }

    func focusWindow(windowId: String) {
        guard !shouldFreezeUpdates() else { return }
        _ = runAerospaceCommand(arguments: ["focus", "--window-id", windowId])
    }

    private func runAerospaceCommand(arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        
        let timeout: TimeInterval = 2.0
        let group = DispatchGroup()
        var data: Data?
        
        do {
            try process.run()
            group.enter()
            DispatchQueue.global().async {
                data = pipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
        } catch {
            print("Aerospace error: \(error)")
            return nil
        }
        
        let result = group.wait(timeout: DispatchTime.now() + timeout)
        
        if result == .timedOut {
            print("Aerospace command timed out: \(arguments.joined(separator: " "))")
            process.terminate()
            return nil
        }
        
        process.waitUntilExit()
        return data
    }

    private func fetchSpaces() -> [AeroSpace]? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-workspaces", "--all", "--json",
            ])
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AeroSpace].self, from: data)
        } catch {
            print("Decode spaces error: \(error)")
            return nil
        }
    }

    private func fetchWindows() -> [AeroWindow]? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-windows", "--all", "--json", "--format",
                "%{window-id} %{app-name} %{window-title} %{workspace}",
            ])
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AeroWindow].self, from: data)
        } catch {
            print("Decode windows error: \(error)")
            return nil
        }
    }

    private func fetchFocusedSpace() -> AeroSpace? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-workspaces", "--focused", "--json",
            ])
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AeroSpace].self, from: data).first
        } catch {
            print("Decode focused space error: \(error)")
            return nil
        }
    }

    private func fetchFocusedWindow() -> AeroWindow? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-windows", "--focused", "--json",
            ])
        else {
            return nil
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([AeroWindow].self, from: data).first
        } catch {
            print("Decode focused window error: \(error)")
            return nil
        }
    }
}
