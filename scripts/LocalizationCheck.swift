// Built into a disposable app by check-localization.py, never shipped.
import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.appearance = NSAppearance(named: .aqua)
var objects: NSArray?
guard Bundle.main.loadNibNamed("MainMenu", owner: app, topLevelObjects: &objects),
      let delegate = app.delegate as? AppDelegate else { fatalError("Cannot load Launcher nib") }
let domain = "AutoRaise.LocalizationCheck.\(ProcessInfo.processInfo.processIdentifier)"
delegate.prefs.removePersistentDomain(forName: domain)
delegate.readPreferences()
delegate.configureLocalizedContent()
precondition(delegate.window.title == "AutoRaise 设置")
precondition(delegate.menuItemPrefs.title == "设置…")
precondition(delegate.menuItemAccessibility.title == "授予辅助功能权限")
precondition(MASLocalizedString("Record Shortcut", "") == "记录快捷键")
for (index, value) in delegate.disableKeyValues.enumerated() {
    delegate.disableKeyBox.selectItem(at: index)
    delegate.disableKey(delegate.disableKeyBox!)
    precondition(delegate.prefs.string(forKey: "disableKey") == value)
    delegate.readPreferences()
    precondition(delegate.disableKeyBox.indexOfSelectedItem == index)
}
delegate.disableKeyBox.selectItem(at: 0)
delegate.disableKey(delegate.disableKeyBox!)
delegate.readPreferences()
precondition(!delegate.autoRaiseService.isRunning)
delegate.window.orderFront(nil)
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
let content = delegate.window.contentView!
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
let tabs = descendants(content).compactMap { $0 as? NSTabView }.first!
let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AUTORAISE_CHECK_OUTPUT"]!)
for (index, name) in ["settings", "about"].enumerated() {
    tabs.selectTabViewItem(at: index)
    content.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-l", String(delegate.window.windowNumber), output.appendingPathComponent(name + ".png").path]
    try! capture.run()
    capture.waitUntilExit()
    precondition(capture.terminationStatus == 0, "Window screenshot failed")
}
delegate.prefs.removePersistentDomain(forName: domain)
print("PASS: nib, Chinese menus, shortcut strings, all disable-key mappings, preferences round-trip, no engine started")
