/*
 *
 * AutoRaise Launcher
 *
 * Copyright (c) 2024 Stefan Post (sbmpost), Lothar Haeger
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import CoreServices
import Cocoa
import Foundation
import AppKit
import ServiceManagement

class URLButton: NSButton {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    // Settings
    @IBOutlet weak var window: NSWindow!

    @IBOutlet weak var delaySliderLabel: NSTextField!
    @IBOutlet weak var focusDelaySliderLabel: NSTextField!
    @IBOutlet weak var delaySlider: NSSlider!
    @IBOutlet weak var focusDelaySlider: NSSlider!
    @IBOutlet weak var enableWarpButton: NSButton!
    @IBOutlet weak var enableCurserScalingButton: NSButton!
    @IBOutlet weak var enableAltTaskSwitcherButton: NSButton!
    @IBOutlet weak var warpOnlyAcrossScreensButton: NSButton!
    @IBOutlet weak var enableOnLaunchButton: NSButton!
    @IBOutlet weak var launchAtLoginButton: NSButton!
    @IBOutlet weak var hideIconButton: NSButton!
    @IBOutlet weak var shortcutView: MASShortcutView!
    @IBOutlet weak var ignoreAppsEdit: NSTextField!
    @IBOutlet weak var ignoreTitlesEdit: NSTextField!
    @IBOutlet weak var stayFocusedBundleIdsEdit: NSTextFieldCell!
    @IBOutlet weak var invertDisableKeyButton: NSButton!
    @IBOutlet weak var disableKeyBox: NSComboBox!
    @IBOutlet weak var requireMouseStopButton: NSButton!
    @IBOutlet weak var requireMultipleScreensButton: NSButton!
    @IBOutlet weak var requireScreenChangeButton: NSButton!
    @IBOutlet weak var ignoreSpaceChangedButton: NSButton!
    @IBOutlet weak var invertIgnoreAppsButton: NSButton!
    @IBOutlet weak var mouseDeltaEdit: NSTextField!
    @IBOutlet weak var pollMillisEdit: NSTextField!

    // About
    @IBOutlet weak var aboutText: NSTextField!
    @IBOutlet weak var homePage: URLButton!
    @IBOutlet weak var autoRaisePage: URLButton!
    
    let appVersionString: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    let buildNumber: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String

    var appAbout: String {
        "AutoRaise 简体中文版\n版本 \(appVersionString)（构建 \(buildNumber)）\n\n" +
        "©2026 Stefan Post、Lothar Haeger\n汉化：iamzjt-front-end\n" +
        "图标作者：https://www.flaticon.com/authors/fr"
    }

    let homePageUrl = "https://github.com/iamzjt-front-end/AutoRaise"
    let autoRaiseUrl = "https://github.com/sbmpost/AutoRaise"
    // Display labels must never be passed as engine arguments or stored preferences.
    let disableKeyValues = ["control", "option", "disabled"]
    let disableKeyLabels = ["Control（⌃）", "Option（⌥）", "不使用"]

    let prefs = UserDefaults.standard

    var statusBar = NSStatusBar.system
    var menuBarItem : NSStatusItem = NSStatusItem()
    var menu: NSMenu = NSMenu()
    var menuItemPrefs : NSMenuItem = NSMenuItem()
    var menuItemQuit : NSMenuItem = NSMenuItem()
    var menuItemAccessibility : NSMenuItem = NSMenuItem()
    var autoRaiseService: Process = Process()

    var autoRaiseDelay : NSInteger = 0
    var autoFocusDelay : NSInteger = 0
    var mouseDelta : NSInteger = 0
    var pollMillis : NSInteger = 0
    var enableWarp = NSControl.StateValue.off
    var enableCursorScaling = NSControl.StateValue.off
    var enableAltTaskSwitcher = NSControl.StateValue.off
    var warpOnlyAcrossScreens = NSControl.StateValue.off
    var enableOnLaunch = NSControl.StateValue.off
    var hideIcon = NSControl.StateValue.off
    var requireMouseStop = NSControl.StateValue.on
    var requireMultipleScreens = NSControl.StateValue.off
    var requireScreenChange = NSControl.StateValue.off
    var ignoreSpaceChanged = NSControl.StateValue.off
    var invertDisableKey = NSControl.StateValue.off
    var invertIgnoreApps = NSControl.StateValue.off
    var ignoreApps: String = ""
    var ignoreTitles: String = ""
    var stayFocusedBundleIds: String = ""
    var disableKey: String = "control"

    let icon = NSImage(named: "MenuIcon")
    let iconRunning = NSImage(named: "MenuIconRunning")

    override func awakeFromNib() {
        // Build status bar menu
        menuBarItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        menuBarItem.button?.title = ""

        if let button = menuBarItem.button {
            button.action = #selector(menuBarItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.image = icon
        }

        // "授予辅助功能权限" menuItem, only shown when it is missing
        menuItemAccessibility.title = "授予辅助功能权限"
        menuItemAccessibility.action = #selector(requestAccessibility(_:))
        menu.addItem(menuItemAccessibility)

        //"设置…" menuItem
        menuItemPrefs.title = "设置…"
        menuItemPrefs.action = #selector(Preferences(_:))
        menu.addItem(menuItemPrefs)
        
        // Separator
        menu.addItem(NSMenuItem.separator())
        
        // "退出 AutoRaise" menuItem
        menuItemQuit.title = "退出 AutoRaise"
        menuItemQuit.action = #selector(quitApplication(_:))
        menu.addItem(menuItemQuit)
    }

    func updateHotkey() { }

    func toggleService() {
        if autoRaiseService.isRunning {
            self.stopService(self)
        } else {
            self.startService(self)
        }
    }

    // AutoRaise itself runs as a subprocess of this app and inherits its accessibility
    // trust, so asking here answers for the engine as well.
    func updateAccessibilityState() {
        let trusted = AXIsProcessTrusted()
        menuItemAccessibility.isHidden = trusted
        menuBarItem.button?.appearsDisabled = !trusted
        menuBarItem.button?.toolTip = trusted ? nil :
            "AutoRaise 尚未获得辅助功能权限，无法置前或聚焦窗口"
    }

    @objc func requestAccessibility(_ sender: AnyObject) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        updateAccessibilityState()
    }

    @objc func menuBarItemClicked(_ sender: NSStatusBarButton) {
        updateAccessibilityState()
        let event = NSApp.currentEvent!
        if event.type == NSEvent.EventType.rightMouseUp {
            menuBarItem.menu = menu
            menuBarItem.button?.performClick(nil)
            menuBarItem.menu = nil
        } else if AXIsProcessTrusted() {
            toggleService()
        } else {
            requestAccessibility(self)
        }
    }

    @IBAction func enableOnLaunch(_ sender: NSButton) {
        enableOnLaunch = enableOnLaunchButton.state
        self.prefs.set(enableOnLaunch == NSControl.StateValue.on ? "1" : "0", forKey: "enableOnLaunch")
    }

    @IBAction func launchAtLogin(_ sender: NSButton) {
        guard #available(macOS 13.0, *) else {
            syncLaunchAtLoginButton()
            return
        }

        do {
            if sender.state == .on {
                if SMAppService.mainApp.status == .requiresApproval {
                    showLoginItemApproval()
                } else if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                    if SMAppService.mainApp.status == .requiresApproval {
                        showLoginItemApproval()
                    }
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.addButton(withTitle: "好")
            alert.messageText = "无法更新登录项"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }

        syncLaunchAtLoginButton()
    }

    func syncLaunchAtLoginButton() {
        guard #available(macOS 13.0, *) else {
            launchAtLoginButton.state = .off
            launchAtLoginButton.isEnabled = false
            launchAtLoginButton.toolTip = "需要 macOS 13 或更高版本"
            return
        }

        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginButton.state = .on
            launchAtLoginButton.toolTip = nil
        case .requiresApproval:
            launchAtLoginButton.state = .off
            launchAtLoginButton.toolTip = "请在「系统设置 → 通用 → 登录项」中允许"
        case .notRegistered, .notFound:
            launchAtLoginButton.state = .off
            launchAtLoginButton.toolTip = nil
        @unknown default:
            launchAtLoginButton.state = .off
            launchAtLoginButton.toolTip = "未知的登录项状态"
        }
    }

    @available(macOS 13.0, *)
    func showLoginItemApproval() {
        let alert = NSAlert()
        alert.messageText = "需要授权"
        alert.informativeText = "请在「系统设置 → 通用 → 登录项」中允许 AutoRaise，以便登录时自动打开。"
        alert.addButton(withTitle: "打开登录项设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @IBAction func hideIcon(_ sender: NSButton) {
        menuBarItem.isVisible = hideIconButton.state == NSControl.StateValue.off
    }

    @IBAction func autoRaiseDelay(_ sender: Any) {
        autoRaiseDelay = delaySlider.integerValue
        if (autoRaiseDelay == 0) {
            delaySliderLabel.stringValue = "已停用窗口置前"
        } else {
            delaySliderLabel.stringValue = "窗口置前延迟：" + String(
                pollMillis*(autoRaiseDelay/pollMillis - 1)) + " 毫秒"
        }
        self.prefs.set(autoRaiseDelay, forKey: "autoRaiseDelay")
        if autoRaiseService.isRunning {
            self.stopService(self)
            self.startService(self)
        }
    }

    @IBAction func autoFocusDelay(_ sender: Any) {
        autoFocusDelay = focusDelaySlider.integerValue
        if (autoFocusDelay == 0) {
            focusDelaySliderLabel.stringValue = "已停用窗口聚焦"
        } else {
            focusDelaySliderLabel.stringValue = "窗口聚焦延迟：" + String(
                pollMillis*(autoFocusDelay/pollMillis - 1)) + " 毫秒"
        }
        self.prefs.set(autoFocusDelay, forKey: "autoFocusDelay")
        if autoRaiseService.isRunning {
            self.stopService(self)
            self.startService(self)
        }
    }

    @IBAction func mouseDelta(_ sender: Any) {
        mouseDelta = mouseDeltaEdit.integerValue
        if (mouseDelta < 0) {
            mouseDeltaEdit.integerValue = 0
            mouseDelta = mouseDeltaEdit.integerValue
        }
        self.prefs.set(mouseDelta, forKey: "mouseDelta")
        if autoRaiseService.isRunning {
            self.stopService(self)
            self.startService(self)
        }
    }

    @IBAction func enableWarp(_ sender: NSButton) {
        enableWarp = enableWarpButton.state
        enableCurserScalingButton.isEnabled = (enableWarp == NSControl.StateValue.on)
        enableAltTaskSwitcherButton.isEnabled = (enableWarp == NSControl.StateValue.on)
        warpOnlyAcrossScreensButton.isEnabled = (enableWarp == NSControl.StateValue.on)
        self.prefs.set(enableWarp == NSControl.StateValue.on ? "1" : "0", forKey: "enableWarp")
        if autoRaiseService.isRunning {
            self.stopService(self)
            self.startService(self)
        }
    }

    @IBAction func enableCursorScaling(_ sender: NSButton) {
        enableCursorScaling = enableCurserScalingButton.state
        self.prefs.set(enableCursorScaling == NSControl.StateValue.on ? "1" : "0", forKey: "enableCursorScaling")
        if autoRaiseService.isRunning {
            self.stopService(self)
            self.startService(self)
        }
    }

    
    @IBAction func warpOnlyAcrossScreens(_ sender: NSButton) {
        warpOnlyAcrossScreens = warpOnlyAcrossScreensButton.state
        self.prefs.set(warpOnlyAcrossScreens == NSControl.StateValue.on ? "1" : "0",
            forKey: "warpOnlyAcrossScreens")
        if autoRaiseService.isRunning {
            self.stopService(self)
            self.startService(self)
        }
    }

    @IBAction func enableAltTaskSwitcher(_ sender: NSButton) {
        enableAltTaskSwitcher = enableAltTaskSwitcherButton.state
        self.prefs.set(enableAltTaskSwitcher == NSControl.StateValue.on ? "1" : "0", forKey: "enableAltTaskSwitcher")
        if autoRaiseService.isRunning {
            self.stopService(self)
            self.startService(self)
        }
    }
    
    @IBAction func ignoreApps(_ sender: Any) {
        ignoreApps = ignoreAppsEdit.stringValue
        self.prefs.set(ignoreApps, forKey: "ignoreApps")
        if autoRaiseService.isRunning {
            self.stopService(self)
            self.startService(self)
        }
    }

    @IBAction func ignoreTitles(_ sender: Any) {
        ignoreTitles = ignoreTitlesEdit.stringValue
        self.prefs.set(ignoreTitles, forKey: "ignoreTitles")
        if autoRaiseService.isRunning {
            self.stopService(self)
            self.startService(self)
        }
    }

    @IBAction func stayFocusedBundleIds(_ sender: Any) {
        stayFocusedBundleIds = stayFocusedBundleIdsEdit.stringValue
        self.prefs.set(stayFocusedBundleIds, forKey: "stayFocusedBundleIds")
        if autoRaiseService.isRunning {
            self.stopService(self)
            self.startService(self)
        }
    }

    @IBAction func disableKey(_ sender: Any) {
        let index = disableKeyBox.indexOfSelectedItem
        guard disableKeyValues.indices.contains(index) else { return }
        disableKey = disableKeyValues[index]
        self.prefs.set(disableKey, forKey: "disableKey")
        if autoRaiseService.isRunning {
            self.stopService(self)
            self.startService(self)
        }
    }

    @IBAction func requireMouseStop(_ sender: Any) {
        requireMouseStop = requireMouseStopButton.state
        self.prefs.set(requireMouseStop == NSControl.StateValue.on ? "1" : "0",
            forKey: "requireMouseStop")
        if autoRaiseService.isRunning {
            self.stopService(self)
            self.startService(self)
        }
    }

    @IBAction func requireMultipleScreens(_ sender: Any) {
        requireMultipleScreens = requireMultipleScreensButton.state
        self.prefs.set(requireMultipleScreens == NSControl.StateValue.on ? "1" : "0",
            forKey: "requireMultipleScreens")
        if autoRaiseService.isRunning {
            self.stopService(self)
            self.startService(self)
        }
    }

    @IBAction func requireScreenChange(_ sender: Any) {
        requireScreenChange = requireScreenChangeButton.state
        self.prefs.set(requireScreenChange == NSControl.StateValue.on ? "1" : "0",
            forKey: "requireScreenChange")
        if autoRaiseService.isRunning {
            self.stopService(self)
            self.startService(self)
        }
    }

    @IBAction func ignoreSpaceChanged(_ sender: Any) {
        ignoreSpaceChanged = ignoreSpaceChangedButton.state
        self.prefs.set(ignoreSpaceChanged == NSControl.StateValue.on ? "1" : "0",
            forKey: "ignoreSpaceChanged")
        if autoRaiseService.isRunning {
            self.stopService(self)
            self.startService(self)
        }
    }

    @IBAction func invertDisableKey(_ sender: Any) {
        invertDisableKey = invertDisableKeyButton.state
        self.prefs.set(invertDisableKey == NSControl.StateValue.on ? "1" : "0",
            forKey: "invertDisableKey")
        if autoRaiseService.isRunning {
            self.stopService(self)
            self.startService(self)
        }
    }

    @IBAction func invertIgnoreApps(_ sender: Any) {
        invertIgnoreApps = invertIgnoreAppsButton.state
        self.prefs.set(invertIgnoreApps == NSControl.StateValue.on ? "1" : "0",
            forKey: "invertIgnoreApps")
        if autoRaiseService.isRunning {
            self.stopService(self)
            self.startService(self)
        }
    }

    @IBAction func pollMillis(_ sender: Any) {
        let oldPollMillis = pollMillis
        pollMillis = pollMillisEdit.integerValue
        if (pollMillis < 20) {
            pollMillisEdit.integerValue = 50
            pollMillis = pollMillisEdit.integerValue
        }
        self.prefs.set(pollMillis, forKey: "pollMillis")

        delaySlider.maxValue = Double((delaySlider.numberOfTickMarks - 1) * pollMillis)
        focusDelaySlider.maxValue = Double((focusDelaySlider.numberOfTickMarks - 1) * pollMillis)
        delaySlider.integerValue = pollMillis * autoRaiseDelay/oldPollMillis
        focusDelaySlider.integerValue = pollMillis * autoFocusDelay/oldPollMillis

        autoRaiseDelay(sender)
        autoFocusDelay(sender)
        if autoRaiseService.isRunning {
            self.stopService(self)
            self.startService(self)
        }
    }

    func readPreferences() {
        autoRaiseDelay = prefs.integer(forKey: "autoRaiseDelay")
        autoFocusDelay = prefs.integer(forKey: "autoFocusDelay")
        mouseDelta = prefs.integer(forKey: "mouseDelta")
        if (mouseDelta < 0) { mouseDelta = 0 }
        pollMillis = prefs.integer(forKey: "pollMillis")
        if (pollMillis < 20) { pollMillis = 50 }
        if let rawValue = prefs.string(forKey: "enableWarp") {
            enableWarp = NSControl.StateValue(rawValue: Int(rawValue) ?? 0)
        }
        if let rawValue = prefs.string(forKey: "enableCursorScaling") {
            enableCursorScaling = NSControl.StateValue(rawValue: Int(rawValue) ?? 0)
        }
        if let rawValue = prefs.string(forKey: "warpOnlyAcrossScreens") {
            warpOnlyAcrossScreens = NSControl.StateValue(rawValue: Int(rawValue) ?? 0)
        }
        if let rawValue = prefs.string(forKey: "enableAltTaskSwitcher") {
            enableAltTaskSwitcher = NSControl.StateValue(rawValue: Int(rawValue) ?? 0)
        }
        if let rawValue = prefs.string(forKey: "enableOnLaunch") {
            enableOnLaunch = NSControl.StateValue(rawValue: Int(rawValue) ?? 0)
        }
        if let rawValue = prefs.string(forKey: "requireMouseStop") {
            requireMouseStop = NSControl.StateValue(rawValue: Int(rawValue) ?? 0)
        }
        if let rawValue = prefs.string(forKey: "requireMultipleScreens") {
            requireMultipleScreens = NSControl.StateValue(rawValue: Int(rawValue) ?? 0)
        }
        if let rawValue = prefs.string(forKey: "requireScreenChange") {
            requireScreenChange = NSControl.StateValue(rawValue: Int(rawValue) ?? 0)
        }
        if let rawValue = prefs.string(forKey: "ignoreSpaceChanged") {
            ignoreSpaceChanged = NSControl.StateValue(rawValue: Int(rawValue) ?? 0)
        }
        if let rawValue = prefs.string(forKey: "invertDisableKey") {
            invertDisableKey = NSControl.StateValue(rawValue: Int(rawValue) ?? 0)
        }
        if let rawValue = prefs.string(forKey: "invertIgnoreApps") {
            invertIgnoreApps = NSControl.StateValue(rawValue: Int(rawValue) ?? 0)
        }
        ignoreApps = prefs.string(forKey: "ignoreApps") ?? ""
        ignoreTitles = prefs.string(forKey: "ignoreTitles") ?? ""
        stayFocusedBundleIds = prefs.string(forKey: "stayFocusedBundleIds") ?? ""
        disableKey = prefs.string(forKey: "disableKey") ?? "control"

        delaySlider.maxValue = Double(delaySlider.numberOfTickMarks * pollMillis)
        focusDelaySlider.maxValue = Double(focusDelaySlider.numberOfTickMarks * pollMillis)
        if (autoRaiseDelay == 0 && autoFocusDelay == 0 && enableWarp == NSControl.StateValue.off) {
            delaySlider.integerValue = pollMillis
            autoRaiseDelay(self)
        }

        if (autoRaiseDelay == 0) {
            delaySliderLabel.stringValue = "已停用窗口置前"
        } else {
            delaySliderLabel.stringValue = "窗口置前延迟：" + String(
                pollMillis*(autoRaiseDelay/pollMillis - 1)) + " 毫秒"
        }
        if (autoFocusDelay == 0) {
            focusDelaySliderLabel.stringValue = "已停用窗口聚焦"
        } else {
            focusDelaySliderLabel.stringValue = "窗口聚焦延迟：" + String(
                pollMillis*(autoFocusDelay/pollMillis - 1)) + " 毫秒"
        }

        enableOnLaunchButton.state = enableOnLaunch
        enableWarpButton.state = enableWarp
        enableCurserScalingButton.state = enableCursorScaling
        enableAltTaskSwitcherButton.state = enableAltTaskSwitcher
        warpOnlyAcrossScreensButton.state = warpOnlyAcrossScreens
        ignoreAppsEdit.stringValue = ignoreApps
        ignoreTitlesEdit.stringValue = ignoreTitles
        stayFocusedBundleIdsEdit.stringValue = stayFocusedBundleIds
        disableKeyBox.isEditable = false
        disableKeyBox.removeAllItems()
        disableKeyBox.addItems(withObjectValues: disableKeyLabels)
        disableKeyBox.selectItem(at: disableKeyValues.firstIndex(of: disableKey) ?? 0)
        requireMouseStopButton.state = requireMouseStop
        requireMultipleScreensButton.state = requireMultipleScreens
        requireScreenChangeButton.state = requireScreenChange
        ignoreSpaceChangedButton.state = ignoreSpaceChanged
        invertDisableKeyButton.state = invertDisableKey
        invertIgnoreAppsButton.state = invertIgnoreApps
        if enableWarp == NSControl.StateValue.on {
            enableCurserScalingButton.isEnabled = true
            enableAltTaskSwitcherButton.isEnabled = true
            warpOnlyAcrossScreensButton.isEnabled = true
        } else {
            enableCurserScalingButton.isEnabled = false
            enableAltTaskSwitcherButton.isEnabled = false
            warpOnlyAcrossScreensButton.isEnabled = false
        }
        delaySlider.integerValue = autoRaiseDelay
        focusDelaySlider.integerValue = autoFocusDelay
        pollMillisEdit.integerValue = pollMillis
        mouseDeltaEdit.integerValue = mouseDelta
    }

    @IBAction func homePagePressed(_ sender: NSButton) {
        let url = URL(string: homePageUrl)!
        NSWorkspace.shared.open(url)
    }
    
    @IBAction func autoRaisePagePressed(_ sender: NSButton) {
        let url = URL(string: autoRaiseUrl)!
        NSWorkspace.shared.open(url)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(CGWindowLevelKey.floatingWindow)))

        icon?.isTemplate = true
        iconRunning?.isTemplate = true
        menuBarItem.button?.image = icon
        menuBarItem.isVisible = true

        readPreferences()
        syncLaunchAtLoginButton()
        updateAccessibilityState()

        let shortcut = shortcutView.shortcutValue
        shortcutView.associatedUserDefaultsKey = "HotKey"

        shortcutView.shortcutValueChange = { (sender) in
            MASShortcutMonitor.shared()?.unregisterAllShortcuts()
            if shortcut != nil {
                MASShortcutMonitor.shared().register(shortcut, withAction:{
                    self.toggleService()
                })
            }
        }

        if self.shortcutView.shortcutValue != nil {
            MASShortcutMonitor.shared().register(self.shortcutView.shortcutValue, withAction: toggleService)
        }

        configureLocalizedContent()

        let instances = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName == "AutoRaise" && $0 != NSRunningApplication.current
        }

        if (instances.count == 0) {
            if enableOnLaunch == NSControl.StateValue.on {
                startService(self)
            }
        } else {
            window.makeKeyAndOrderFront(self)
            stopAutoRaiseMessage()
        }
    }

    func configureLocalizedContent() {
        // update about tab contents
        aboutText.stringValue = appAbout
        ignoreAppsEdit.placeholderString = "应用1,应用2,...（回车确认）"
        ignoreTitlesEdit.placeholderString = "正则1,正则2,...（回车确认）"
        // homepage link
        let pstyle = NSMutableParagraphStyle()
        pstyle.alignment = NSTextAlignment.center
        let customColor = NSColor(red: 0.5, green: 0.5, blue: 0.9, alpha: 1.0)
        homePage.attributedTitle = NSAttributedString(
            string: "汉化版主页",
            attributes: [ NSAttributedString.Key.font: NSFont.systemFont(ofSize: 13.0),
                          NSAttributedString.Key.foregroundColor: customColor,
                          NSAttributedString.Key.underlineStyle: 1,
                          NSAttributedString.Key.paragraphStyle: pstyle])
        autoRaisePage.attributedTitle = NSAttributedString(
            string: "原版项目主页",
            attributes: [ NSAttributedString.Key.font: NSFont.systemFont(ofSize: 13.0),
                          NSAttributedString.Key.foregroundColor: customColor,
                          NSAttributedString.Key.underlineStyle: 1,
                          NSAttributedString.Key.paragraphStyle: pstyle])

    }

    func applicationWillTerminate(_ aNotification: Notification) {
        stopService(self)
        MASShortcutMonitor.shared().unregisterAllShortcuts()
    }

    func applicationDidBecomeActive(_ aNotification: Notification) {
        if (menuBarItem.isVisible == false && window.isVisible == false) {
            menuBarItem.isVisible = true
            hideIconButton.state = NSControl.StateValue.off
        }
        updateAccessibilityState()
    }

    func stopAutoRaiseMessage() {
        let alert = NSAlert()
        alert.messageText = "另一个 AutoRaise 实例正在运行"
        alert.informativeText = "请先退出另一个实例，再打开此版本。"
        alert.addButton(withTitle: "退出")
        alert.beginSheetModal(for: window, completionHandler: savingHandler)
    }

    func savingHandler(response: NSApplication.ModalResponse) {
        switch(response) {
            case NSApplication.ModalResponse.alertFirstButtonReturn:
                NSRunningApplication.current.terminate()
            break
            default:
                NSRunningApplication.current.terminate()
            break
        }
    }

    @objc func Preferences(_ sender: AnyObject){
        self.window.makeKeyAndOrderFront(self)
    }
    
    @objc func startService(_ sender: AnyObject) {
        if !autoRaiseService.isRunning {
            autoRaiseService = Process()
            let autoRaiseCmd = Bundle.main.url(forResource: "AutoRaise", withExtension: "")
            if FileManager().fileExists(atPath: autoRaiseCmd!.path) {
                autoRaiseService.launchPath = autoRaiseCmd?.path
                autoRaiseService.arguments = ["-delay", String(autoRaiseDelay / pollMillis)]
                autoRaiseService.arguments! += ["-focusDelay", String(autoFocusDelay / pollMillis)]
                autoRaiseService.arguments! += ["-mouseDelta", String(mouseDelta)]
                autoRaiseService.arguments! += ["-pollMillis", String(pollMillis)]
                if ( enableWarp == NSControl.StateValue.on ) {
                    autoRaiseService.arguments! += ["-warpX", "0.5", "-warpY", "0.5"]
                    if ( enableCursorScaling == NSControl.StateValue.on ) {
                        autoRaiseService.arguments! += ["-scale", "2.0"]
                    } else {
                        autoRaiseService.arguments! += ["-scale", "1.0"]
                    }
                    if ( warpOnlyAcrossScreens == NSControl.StateValue.on ) {
                        autoRaiseService.arguments! += ["-warpOnlyAcrossScreens", "true"]
                    }
                }
                if ( enableAltTaskSwitcher == NSControl.StateValue.on ) {
                    autoRaiseService.arguments! += ["-altTaskSwitcher", "true"]
                }
                if ( !ignoreApps.isEmpty ) {
                    autoRaiseService.arguments! += ["-ignoreApps", ignoreApps]
                }
                if ( !ignoreTitles.isEmpty ) {
                    autoRaiseService.arguments! += ["-ignoreTitles", ignoreTitles]
                }
                if ( !stayFocusedBundleIds.isEmpty ) {
                    autoRaiseService.arguments! += ["-stayFocusedBundleIds", stayFocusedBundleIds]
                }
                if ( !disableKey.isEmpty ) {
                    autoRaiseService.arguments! += ["-disableKey", disableKey]
                }
                if ( requireMouseStop == NSControl.StateValue.off ) {
                    autoRaiseService.arguments! += ["-requireMouseStop", "false"]
                }
                if ( requireMultipleScreens == NSControl.StateValue.on ) {
                    autoRaiseService.arguments! += ["-requireMultipleScreens", "true"]
                }
                if ( requireScreenChange == NSControl.StateValue.on ) {
                    autoRaiseService.arguments! += ["-requireScreenChange", "true"]
                }
                if ( ignoreSpaceChanged == NSControl.StateValue.on ) {
                    autoRaiseService.arguments! += ["-ignoreSpaceChanged", "true"]
                }
                if ( invertDisableKey == NSControl.StateValue.on ) {
                    autoRaiseService.arguments! += ["-invertDisableKey", "true"]
                }
                if ( invertIgnoreApps == NSControl.StateValue.on ) {
                    autoRaiseService.arguments! += ["-invertIgnoreApps", "true"]
                }
            }
            autoRaiseService.launch()
        }
        menuBarItem.button?.image = iconRunning
    }

    @objc func stopService(_ sender: AnyObject) {
        if autoRaiseService.isRunning {
            autoRaiseService.terminate()
            autoRaiseService.waitUntilExit()
        }
        menuBarItem.button?.image = icon
    }

    @objc func quitApplication(_ sender: AnyObject) {
        NSApplication.shared.terminate(sender)
    }
}
