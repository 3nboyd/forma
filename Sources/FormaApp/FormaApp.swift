import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO
import FormaCore

@main
struct FormaLauncher {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = FormaApplicationDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) { }
    }
}

@MainActor
final class FormaApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let model = WorkspaceModel()
    private var workspace: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenus()
        showWorkspace()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWorkspace()
        return true
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        model.add(urls)
        showWorkspace()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func addFiles() { showWorkspace(); model.importFiles() }
    @objc private func runWorkflow() { model.requestRun() }
    @objc private func showAbout() { NSApp.orderFrontStandardAboutPanel(nil) }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(runWorkflow) { return model.canRun }
        if menuItem.action == #selector(addFiles) { return true }
        return true
    }
    private func configureMenus() {
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let child = NSMenu(title: title); item.submenu = child; main.addItem(item); return child
        }
        let appMenu = menu("Forma")
        let about = appMenu.addItem(withTitle: "About Forma", action: #selector(showAbout), keyEquivalent: ""); about.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Forma", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Forma", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = menu("File")
        let add = file.addItem(withTitle: "Add Files…", action: #selector(addFiles), keyEquivalent: "o"); add.target = self
        let run = file.addItem(withTitle: "Convert", action: #selector(runWorkflow), keyEquivalent: "\r"); run.target = self
        file.addItem(.separator())
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let edit = menu("Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let window = menu("Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }

    private func showWorkspace() {
        if workspace == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 740),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Forma"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 900, height: 640)
            window.contentView = NSHostingView(rootView: WorkspaceView(model: model).frame(minWidth: 900, minHeight: 640))
            window.delegate = self
            window.center()
            workspace = window
        }
        workspace?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
