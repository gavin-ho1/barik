import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var backgroundPanel: NSPanel?
    private var menuBarPanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let error = ConfigManager.shared.initError {
            showFatalConfigError(message: error)
            return
        }
        
        // Show "What's New" banner if the app version is outdated
        if !VersionChecker.isLatestVersion() {
            VersionChecker.updateVersionFile()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NotificationCenter.default.post(
                    name: Notification.Name("ShowWhatsNewBanner"), object: nil)
            }
        }
        
        MenuBarPopup.setup()
        setupPanels()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        setupPanels()
    }

    /// Configures and displays the background and menu bar panels.
    private func setupPanels() {
        guard let screenFrame = NSScreen.main?.frame else { return }
        let position = ConfigManager.shared.config.experimental.foreground.position
        let panelFrame = calculatePanelFrame(screenFrame: screenFrame, position: position)
        
        setupPanel(
            &backgroundPanel,
            frame: screenFrame,
            panelFrame: screenFrame,
            level: NSWindow.Level.statusBar.rawValue - 1,
            hostingRootView: AnyView(BackgroundView()))
        setupPanel(
            &menuBarPanel,
            frame: screenFrame,
            panelFrame: panelFrame,
            level: NSWindow.Level.statusBar.rawValue,
            hostingRootView: AnyView(MenuBarView()))
    }

    /// Calculates the panel frame based on position configuration
    private func calculatePanelFrame(screenFrame: CGRect, position: BarPosition) -> CGRect {
        let foregroundHeight = ConfigManager.shared.config.experimental.foreground.resolveHeight()
        let topPadding = ConfigManager.shared.config.experimental.foreground.topPadding
        
        switch position {
        case .top:
            return CGRect(x: screenFrame.minX, y: screenFrame.maxY - foregroundHeight - topPadding, width: screenFrame.width, height: foregroundHeight)
        case .bottom:
            return CGRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: foregroundHeight)
        }
    }

    /// Sets up an NSPanel with the provided parameters.
    private func setupPanel(
        _ panel: inout NSPanel?, 
        frame: CGRect, 
        panelFrame: CGRect,
        level: Int,
        hostingRootView: AnyView
    ) {
        if let existingPanel = panel {
            existingPanel.setFrame(panelFrame, display: true)
            return
        }

        let newPanel = NSPanel(
            contentRect: panelFrame,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false)
        newPanel.level = NSWindow.Level(rawValue: level)
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        newPanel.setAccessibilityRole(.popover)
        newPanel.setAccessibilityElement(false)
        newPanel.contentView = NSHostingView(rootView: hostingRootView)
        newPanel.orderFront(nil)
        panel = newPanel
    }
    
    private func showFatalConfigError(message: String) {
        let alert = NSAlert()
        alert.messageText = "Configuration Error"
        alert.informativeText = "\(message)\n\nPlease double check ~/.barik-config.toml and try again."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        
        alert.runModal()
        NSApplication.shared.terminate(nil)
    }
}
