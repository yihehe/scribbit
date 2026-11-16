import AppKit
import ServiceManagement
import SwiftUI
import ScribbitCore

final class NotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private let model = NoteModel()
    private let isolated: Bool
    private let settings: AppSettings
    init(isolated: Bool = false) {
        self.isolated = isolated
        settings = AppSettings(isolated: isolated)
        super.init()
        model.animationSpeed = settings.animationSpeed
    }
    private var panel: NotePanel!
    private var presenter: NotchPresenter!
    private var closing = false
    private var openedByHover = false
    private var pointerInsideSurface = true
    private var exitWork: DispatchWorkItem?
    private var statusItem: NSStatusItem!
    private var indicators: [NSPanel] = []
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var hover = HoverGate()
    private var dwell: DispatchWorkItem?
    private var accessedURL: URL?
    private var presentingDialog = false
    private var trackingMenu = false
    private var testPointer: CGPoint?
    private var pointerLocation: CGPoint { isolated ? testPointer ?? NSEvent.mouseLocation : NSEvent.mouseLocation }
    private var bookmark: Data? { settings.bookmark }
    private var indicatorEnabled: Bool { settings.indicator }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createPanel()
        createMenus()
        installMonitors()
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensChanged() }
            })
        // Isolated tests drive this same handler explicitly. Ambient desktop
        // activation changes must not race their controlled open/close steps.
        if !isolated {
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.applicationDeactivated() }
                })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in Task { await self?.closeNote() } })
        refreshIndicators()
        // Register once, not on every launch: honor later user changes in System Settings.
        if !isolated, !settings.didOfferLogin {
            settings.didOfferLogin = true
            setLogin(enabled: true, reportError: true)
        }
        if !isolated, bookmark == nil { Task { await chooseFile() } }
    }

    private func applicationDeactivated() {
        guard !presentingDialog, !trackingMenu, NSApp.modalWindow == nil, !model.pinned else { return }
        Task { await closeNote() }
    }

    private func createPanel() {
        panel = NotePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        let content = NSHostingView(rootView: NoteView(model: model,
            choose: { [weak self] in Task { await self?.chooseFile() } },
            close: { [weak self] in Task { await self?.closeNote() } },
            saveCopy: { [weak self] in Task { await self?.saveCopy() } },
            reload: { [weak self] in Task { await self?.confirmReload() } },
            speedChanged: { [weak self] rate in self?.setAnimationSpeed(rate) }))
        presenter = NotchPresenter(panel: panel, content: content)
        presenter.animationSpeed = settings.animationSpeed
        panel.setAccessibilityLabel("Scribbit editor")
    }

    private func createMenus() {
        let main = NSMenu()
        let appRoot = NSMenuItem()
        let app = NSMenu()
        app.addItem(item("Quit Scribbit", #selector(quit), key: "q"))
        appRoot.submenu = app
        main.addItem(appRoot)
        let fileRoot = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let file = NSMenu(title: "File")
        file.addItem(item("Choose Note…", #selector(chooseAction), key: "o"))
        file.addItem(item("Save", #selector(saveAction), key: "s"))
        file.addItem(item("Close Note", #selector(closeAction), key: "w"))
        file.addItem(item("Done", #selector(closeAction), key: "\r"))
        file.addItem(item("Toggle Note Controls", #selector(toggleControlsAction), key: ","))
        fileRoot.submenu = file
        main.addItem(fileRoot)
        let editRoot = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", #selector(undoAction), key: "z"))
        edit.addItem(item("Redo", #selector(redoAction), key: "Z"))
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"),
            ("Select All", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        let find = NSMenuItem(title: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        edit.addItem(find)
        editRoot.submenu = edit
        main.addItem(editRoot)
        NSApp.mainMenu = main

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = BrandAssets.menuBar
        statusItem.button?.toolTip = "Scribbit — hover at the top center of a display"
        let menu = NSMenu()
        menu.addItem(item("Open Note", #selector(openAction)))
        menu.addItem(item("Choose Note File…", #selector(chooseAction)))
        menu.addItem(item("Create Note File…", #selector(createAction)))
        menu.addItem(.separator())
        menu.addItem(item("Launch at Login", #selector(toggleLogin)))
        menu.addItem(item("Show Frog in Left Notch Wing", #selector(toggleIndicator)))
        let speed = NSMenuItem(title: "Animation Speed", action: nil, keyEquivalent: "")
        let rates = NSMenu(title: "Animation Speed")
        for (index, rate) in (2...8).map({ Double($0) / 4 }).enumerated() {
            let choice = item(AnimationSpeed.label(rate), #selector(selectAnimationSpeed(_:)))
            choice.tag = index
            choice.representedObject = rate
            rates.addItem(choice)
        }
        speed.submenu = rates
        menu.addItem(speed)
        menu.addItem(item("About Scribbit", #selector(about)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Scribbit", #selector(quit), key: "q"))
        menu.delegate = self
        statusItem.menu = menu
        updateMenuStates()
    }
    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
    func menuWillOpen(_ menu: NSMenu) {
        trackingMenu = true
        exitWork?.cancel(); exitWork = nil
        updateMenuStates()
    }
    func menuDidClose(_ menu: NSMenu) {
        trackingMenu = false
        if panel.isVisible { trackOpenPointer() }
    }
    private func updateMenuStates() {
        statusItem.menu?.items.first(where: { $0.action == #selector(toggleLogin) })?.state =
            SMAppService.mainApp.status == .enabled ? .on : .off
        statusItem.menu?.items.first(where: { $0.action == #selector(toggleIndicator) })?.state = indicatorEnabled ? .on : .off
        for choice in statusItem.menu?.items.first(where: { $0.title == "Animation Speed" })?.submenu?.items ?? [] {
            choice.state = (choice.representedObject as? Double) == settings.animationSpeed ? .on : .off
        }
    }

    private func geometry(_ screen: NSScreen) -> NotchGeometry {
        var camera: CGFloat = 0
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            camera = max(0, right.minX - left.maxX)
        }
        return NotchGeometry(screen: screen.frame, cameraWidth: camera, topInset: screen.safeAreaInsets.top)
    }
    private func target(at point: CGPoint) -> Int? {
        NSScreen.screens.indices.first { index in
            let g = geometry(NSScreen.screens[index])
            return g.triggerContains(point) || (indicatorEnabled && g.indicatorContains(point))
        }
    }
    private func installMonitors() {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp], handler: { [weak self] _ in self?.pointerMoved() }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp, .leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            guard let self else { return event }
            if [.mouseMoved, .leftMouseDragged, .leftMouseUp].contains(event.type) { self.pointerMoved() }
            if event.type == .keyDown, event.keyCode == 53, self.panel.isVisible, !self.presentingDialog {
                Task { await self.closeNote() }; return nil
            }
            if event.type == .leftMouseDown || event.type == .rightMouseDown { self.outsideClick() }
            return event
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in self?.outsideClick() }) {
            monitors.append(monitor)
        }
    }
    private func pointerMoved() {
        guard !presentingDialog, !trackingMenu, !model.isBusy, !closing else { return }
        if panel.isVisible { trackOpenPointer(); return }
        let candidate = target(at: self.pointerLocation)
        if candidate != hover.target { dwell?.cancel(); dwell = nil }
        guard hover.move(to: candidate), let candidate else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hover.canOpen(candidate),
                  self.target(at: self.pointerLocation) == candidate,
                  NSScreen.screens.indices.contains(candidate) else { return }
            let screen = NSScreen.screens[candidate]
            Task { await self.openNote(on: screen, fromHover: true) }
        }
        dwell = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.hoverDelay, execute: work)
    }
    private func trackOpenPointer() {
        guard !presenter.isTransitioning else { return }
        let inside = presenter.contains(self.pointerLocation)
        if inside { exitWork?.cancel(); exitWork = nil }
        let changed = inside != pointerInsideSurface
        pointerInsideSurface = inside
        guard changed || exitWork == nil,
              NotchInteraction.closesOnExit(openedByHover: openedByHover, pinned: model.pinned, inside: inside,
                heldByUI: presentingDialog || trackingMenu, busy: model.isBusy || closing,
                dragging: NSEvent.pressedMouseButtons != 0) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, NotchInteraction.closesOnExit(openedByHover: self.openedByHover,
                pinned: self.model.pinned, inside: self.presenter.contains(self.pointerLocation),
                heldByUI: self.presentingDialog || self.trackingMenu, busy: self.model.isBusy || self.closing,
                dragging: NSEvent.pressedMouseButtons != 0) else { return }
            Task { await self.closeNote() }
        }
        if exitWork == nil {
            exitWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.exitDelay, execute: work)
        }
    }

    private func outsideClick() {
        if statusItem.button?.window?.frame.contains(self.pointerLocation) == true { return }
        guard panel.isVisible, !model.pinned, !presentingDialog, !trackingMenu, NSApp.modalWindow == nil,
              !presenter.contains(self.pointerLocation) else { return }
        Task { await closeNote() }
    }

    private func resolveFile() throws -> URL? {
        guard let bookmark else { return nil }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withSecurityScope],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale { try remember(url) }
        return url
    }
    private func remember(_ url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        settings.bookmark = data
    }
    private func openNote(on screen: NSScreen? = nil, fromHover: Bool = false) async {
        guard !presentingDialog, !model.isBusy, !closing, presenter?.isTransitioning != true else { return }
        if panel.isVisible {
            openedByHover = false
            exitWork?.cancel(); exitWork = nil
            NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
            focusEditor(in: panel.contentView)
            return
        }
        do {
            guard let url = try resolveFile() else { await chooseFile(); return }
            await openFile(url, on: screen, fromHover: fromHover)
        } catch { showError("Cannot locate the selected note", error.localizedDescription + " Choose the file again from the menu bar.") }
    }
    private func openFile(_ selected: URL, on screen: NSScreen? = nil, fromHover: Bool = false) async {
        guard !closing, presenter.isTransitioning == false else { return }
        let url = selected.resolvingSymlinksInPath()
        let scoped = selected.startAccessingSecurityScopedResource()
        guard await model.open(url) else {
            if scoped { selected.stopAccessingSecurityScopedResource() }
            showError("Cannot open note", model.error ?? "Unknown error")
            return
        }
        accessedURL = scoped ? selected : nil
        do { try remember(selected) }
        catch { model.error = "The file opened, but its location could not be remembered: \(error.localizedDescription)" }
        let destination = screen ?? NSScreen.screens.first(where: { $0.frame.contains(self.pointerLocation) }) ?? NSScreen.main
        if fromHover, let destination {
            let current = geometry(destination)
            let stillInside = current.triggerContains(self.pointerLocation)
                || (indicatorEnabled && current.indicatorContains(self.pointerLocation))
            if !stillInside {
                _ = await model.close()
                accessedURL?.stopAccessingSecurityScopedResource(); accessedURL = nil
                return
            }
        }
        presenter.showsRestingWing = indicatorEnabled
        if let destination { presenter.configure(geometry(destination)) }
        indicators.forEach { $0.orderOut(nil) }
        openedByHover = fromHover
        pointerInsideSurface = true
        // A completed hover is an editing intent: focus without a click that
        // would otherwise move the just-restored insertion point.
        await presenter.reveal(takeFocus: true)
        panel.contentView?.layoutSubtreeIfNeeded()
        if !closing { focusEditor(in: panel.contentView) }
        trackOpenPointer()
    }
    private func focusEditor(in view: NSView?) {
        guard let view else { return }
        if let text = view as? NSTextView {
            let origin = text.enclosingScrollView?.contentView.bounds.origin
            panel.makeFirstResponder(text)
            if model.editorScrollOrigin != nil, let origin, let editor = text as? NoteTextView {
                editor.restoreViewport(origin)
                editor.layoutSubtreeIfNeeded()
            } else {
                text.scrollRangeToVisible(text.selectedRange())
            }
            return
        }
        for child in view.subviews { focusEditor(in: child) }
    }
    private func commitComposition(in view: NSView?) {
        guard let view else { return }
        if let editor = view as? NSTextView {
            let origin = editor.enclosingScrollView?.contentView.bounds.origin
            // Use AppKit's acceptance operation, never reconstruct preedit.
            editor.unmarkText()
            if editor is NoteTextView {
                model.rememberEditorSelection(editor.selectedRange())
                if let origin { model.rememberEditorScrollOrigin(origin) }
            }
            return
        }
        for child in view.subviews { commitComposition(in: child) }
    }
    @discardableResult private func closeNote() async -> Bool {
        guard !model.isBusy, !closing else { return false }
        guard model.isOpen else { return true }
        guard !presentingDialog else { return false }
        closing = true
        defer { closing = false }
        exitWork?.cancel(); exitWork = nil
        await presenter.waitUntilSettled()
        commitComposition(in: panel.contentView)
        let previousResponder = panel.firstResponder
        panel.makeFirstResponder(nil)
        guard await model.close(keepPresentation: true) else {
            if panel.isKeyWindow { panel.makeFirstResponder(previousResponder) }
            return false
        }
        await presenter.dismiss()
        model.clearClosedPresentation()
        accessedURL?.stopAccessingSecurityScopedResource(); accessedURL = nil
        dwell?.cancel(); dwell = nil
        hover.suppressUntilExit()
        if target(at: self.pointerLocation) == nil { _ = hover.move(to: nil) }
        refreshIndicators()
        return true
    }

    private func chooseFile() async {
        guard !presentingDialog, !model.isBusy, !closing, presenter?.isTransitioning != true else { return }
        guard await closeNote() else { return }
        presentingDialog = true
        NSApp.activate(ignoringOtherApps: true)
        let picker = NSOpenPanel()
        picker.title = "Choose a UTF-8 text or Markdown note"
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        let response = picker.runModal()
        presentingDialog = false
        if response == .OK, let url = picker.url { await openFile(url) }
    }
    private func createFile() async {
        guard !presentingDialog, !model.isBusy, !closing, presenter?.isTransitioning != true else { return }
        guard await closeNote() else { return }
        presentingDialog = true
        NSApp.activate(ignoringOtherApps: true)
        let picker = NSSavePanel()
        picker.title = "Create a note"
        picker.nameFieldStringValue = "Notes.md"
        let response = picker.runModal()
        presentingDialog = false
        guard response == .OK, let url = picker.url else { return }
        guard await model.createIfMissing(url) else {
            showError("Cannot create note", model.error ?? "A file operation is already in progress.")
            return
        }
        await openFile(url)
    }
    private func saveCopy() async {
        guard !presentingDialog, !model.isBusy, !closing, presenter?.isTransitioning != true else { return }
        presentingDialog = true
        let picker = NSSavePanel()
        picker.title = "Save a copy — the current note stays open"
        picker.nameFieldStringValue = "\(model.url?.deletingPathExtension().lastPathComponent ?? "Note") copy.md"
        let response = picker.runModal()
        presentingDialog = false
        guard response == .OK, let url = picker.url else { return }
        guard url.resolvingSymlinksInPath() != model.url else {
            model.error = "Choose a different path for the copy. The original was not overwritten."; return
        }
        await model.saveCopy(to: url)
    }
    private func confirmReload() async {
        guard !presentingDialog, !model.isBusy, !closing, presenter?.isTransitioning != true else { return }
        presentingDialog = true
        let alert = NSAlert()
        alert.messageText = "Discard your edits and reload from disk?"
        alert.informativeText = "Save a copy first if you want to keep these edits. This cannot be undone."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard and Reload")
        let response = alert.runModal()
        presentingDialog = false
        if response == .alertSecondButtonReturn {
            commitComposition(in: panel.contentView)
            await model.reload()
        }
    }
    private func showError(_ title: String, _ detail: String) {
        presentingDialog = true
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
        presentingDialog = false
    }
    private func setLogin(enabled: Bool, reportError: Bool) {
        guard !isolated else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            if enabled, SMAppService.mainApp.status == .requiresApproval {
                showError("Allow Scribbit at login", "Approve Scribbit in System Settings → General → Login Items. The app cannot approve itself.")
            }
        } catch {
            if reportError { showError("Could not change Launch at Login", error.localizedDescription + " Install the bundled app in Applications, then try the menu option again.") }
        }
        updateMenuStates()
    }
    @objc private func toggleLogin() {
        guard !isolated else { return }
        let state = SMAppService.mainApp.status
        if state == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        else { setLogin(enabled: state != .enabled, reportError: true) }
    }
    @objc private func toggleIndicator() {
        settings.indicator = !indicatorEnabled
        updateMenuStates(); refreshIndicators()
    }
    private func refreshIndicators() {
        indicators.forEach { $0.orderOut(nil) }; indicators.removeAll()
        presenter.showsRestingWing = indicatorEnabled
        guard indicatorEnabled, !panel.isVisible else { return }
        for screen in NSScreen.screens {
            let layout = geometry(screen)
            let indicator = NSPanel(contentRect: layout.indicator, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            indicator.level = .statusBar
            indicator.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            indicator.backgroundColor = .clear
            indicator.isOpaque = false
            indicator.hasShadow = false
            indicator.appearance = NSAppearance(named: .darkAqua)
            indicator.ignoresMouseEvents = true
            indicator.isReleasedWhenClosed = false
            indicator.contentView = RestingNotchView(geometry: layout)
            indicator.orderFrontRegardless()
            indicators.append(indicator)
        }
    }
    private func setAnimationSpeed(_ rate: Double) {
        settings.animationSpeed = rate
        model.animationSpeed = settings.animationSpeed
        presenter.animationSpeed = settings.animationSpeed
        updateMenuStates()
    }
    @objc private func selectAnimationSpeed(_ item: NSMenuItem) {
        if let rate = item.representedObject as? Double { setAnimationSpeed(rate) }
    }
    @objc private func toggleControlsAction() { model.controlsExpanded.toggle() }
    private func screensChanged() {
        dwell?.cancel(); dwell = nil; hover = HoverGate()
        exitWork?.cancel(); exitWork = nil
        if panel.isVisible, let screen = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) }) ?? NSScreen.main {
            presenter.configure(geometry(screen))
        }
        refreshIndicators()
    }
    @objc private func openAction() { Task { await openNote() } }
    @objc private func chooseAction() { Task { await chooseFile() } }
    @objc private func createAction() { Task { await createFile() } }
    @objc private func saveAction() {
        commitComposition(in: panel.contentView)
        Task { await model.save() }
    }
    private var editableResponder: NSTextView? {
        guard !model.isBusy, let editor = panel?.firstResponder as? NSTextView,
              editor.isEditable else { return nil }
        return editor
    }
    @objc private func undoAction() {
        guard let editor = editableResponder else { return }
        editor.breakUndoCoalescing()
        editor.undoManager?.undo()
    }
    @objc private func redoAction() {
        guard let editor = editableResponder else { return }
        editor.breakUndoCoalescing()
        editor.undoManager?.redo()
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(undoAction) { return editableResponder?.undoManager?.canUndo == true }
        if menuItem.action == #selector(redoAction) { return editableResponder?.undoManager?.canRedo == true }
        return true
    }
    @objc private func closeAction() { Task { await closeNote() } }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func about() {
        guard !presentingDialog else { return }
        showError("Scribbit", "Hover at the top center of any display for 250 ms. Edits save on Done, Escape, outside click, app deactivation, sleep, or normal quit. Every new opening reads the file again.\n\nUTF-8 text only, up to 2 MiB. Markdown preview supports inline formatting. No network, telemetry, polling, or Accessibility permission.\n\nIf a save fails, the editor stays open. Force Quit and power loss cannot save unsaved edits.")
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !presentingDialog, !model.isBusy else { return .terminateCancel }
        Task { NSApp.reply(toApplicationShouldTerminate: await closeNote()) }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        dwell?.cancel()
        exitWork?.cancel()
        monitors.forEach(NSEvent.removeMonitor)
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        accessedURL?.stopAccessingSecurityScopedResource()
    }
}

// Explicitly opt-in integration entry used by the GUI harness. All preference
// storage is RAM-only and every login mutation is disabled for this instance.
extension AppDelegate {
    func runIsolatedShellChecks(file: URL) async throws {
        precondition(isolated)
        applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        updateMenuStates()
        defer {
            panel.orderOut(nil)
            indicators.forEach { $0.orderOut(nil) }
            NSStatusBar.system.removeStatusItem(statusItem)
            applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        func check(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "ShellSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        try check(statusItem.button?.image === BrandAssets.menuBar,
                  "Menu bar did not use the bundled frog template")
        try check(BrandAssets.notch.isTemplate && BrandAssets.notch.representations.count == 2,
                  "Notch template is missing its scale representations")
        if Bundle.main.bundleURL.pathExtension == "app" {
            try check(BrandAssets.resourceBundle.bundleURL.path.hasPrefix(Bundle.main.bundleURL.path + "/Contents/Resources/"),
                      "Brand assets were loaded from build cache instead of the app")
        }
        await openFile(file)
        try check(panel.isVisible && model.isOpen, "Shell open failed")
        try check(bookmark != nil, "Isolated bookmark could not be created")
        try check(EditorProbe.find(in: panel.contentView!)?.view is NoteTextView,
                  "Shell did not use the native note editor")
        try check(!statusItem.menu!.items.contains(where: { $0.title == "Editor Engine" }),
                  "Retired editor-engine selector is still present")
        guard let editor = EditorProbe.find(in: panel.contentView!) else { throw CocoaError(.featureUnsupported) }
        let beforeComposition = model.text
        editor.setSelectedRange(NSRange(location: beforeComposition.utf16.count, length: 0))
        editor.view.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0),
                                  replacementRange: NSRange(location: NSNotFound, length: 0))
        saveAction()
        try await waitForSmoke {
            !self.model.isBusy && !self.model.isDirty && !editor.view.hasMarkedText() && editor.isEditable
        }
        try check(panel.isVisible && model.text == beforeComposition + "か" &&
                  (try String(contentsOf: file, encoding: .utf8)) == model.text,
                  "Save failed to accept and persist native composition")
        panel.makeKeyAndOrderFront(nil)
        try check(panel.makeFirstResponder(editor.view), "Native editor did not take editing focus")
        func performEditMenu(_ title: String) -> Bool {
            guard let item = NSApp.mainMenu?.items.first(where: { $0.title == "Edit" })?
                .submenu?.items.first(where: { $0.title == title }), let action = item.action else { return false }
            return NSApp.sendAction(action, to: item.target, from: item)
        }
        try check(performEditMenu("Undo"),
                  "Native menu Undo was not handled")
        try await waitForSmoke { editor.string == beforeComposition && self.model.text == beforeComposition }
        try check(performEditMenu("Redo"),
                  "Native menu Redo was not handled")
        try await waitForSmoke {
            editor.string == beforeComposition + "か" && self.model.text == beforeComposition + "か"
        }
        print("NATIVE_HISTORY_SMOKE_PASS: composition Undo/Redo through responder menu actions updates source and binding")
        editor.setSelectedRange(NSRange(location: model.text.utf16.count, length: 0))
        editor.view.setMarkedText("な", selectedRange: NSRange(location: 1, length: 0),
                                  replacementRange: NSRange(location: NSNotFound, length: 0))
        let compositionClosed = await closeNote()
        try check(compositionClosed &&
                  (try String(contentsOf: file, encoding: .utf8)) == beforeComposition + "かな",
                  "Close failed to accept and persist native composition")
        await openNote()
        print("COMPOSITION_SAVE_SMOKE_PASS: Save/Close accept native preedit before persisting; reopen reads it")
        let doneItem = NSApp.mainMenu?.items.first(where: { $0.title == "File" })?.submenu?.items.first(where: { $0.title == "Done" })
        try check(doneItem?.keyEquivalent == "\r", "Collapsed controls lost Command-Return close")
        setAnimationSpeed(1.75)
        try check(settings.animationSpeed == 1.75 && model.animationSpeed == 1.75 && presenter.animationSpeed == 1.75,
                  "Animation speed setting was not synchronized")
        let rates = statusItem.menu?.items.first(where: { $0.title == "Animation Speed" })?.submenu?.items ?? []
        try check(rates.filter { $0.state == .on }.count == 1, "Speed menu did not reflect selected rate")
        setAnimationSpeed(1)
        model.text = "Shell edited note"
        let closed = await closeNote()
        try check(closed && !panel.isVisible && !model.isOpen,
                  "Shell save and hide failed: closed=\(closed), visible=\(panel.isVisible), open=\(model.isOpen), busy=\(model.isBusy), closing=\(closing), error=\(String(describing: model.error))")
        try check(try String(contentsOf: file, encoding: .utf8) == "Shell edited note", "Shell did not save")
        try Data("Shell external edit".utf8).write(to: file, options: .atomic)
        await openNote()
        try check(model.text == "Shell external edit", "Bookmark reopen did not refresh")
        model.text = "Shell conflicting edit"
        try Data("Shell other writer".utf8).write(to: file, options: .atomic)
        let conflict = await closeNote()
        try check(!conflict && panel.isVisible && model.isOpen, "Shell hid after failed save")
        await model.reload()
        _ = await closeNote()
        toggleIndicator()
        try check(indicators.count == NSScreen.screens.count, "Indicator count did not follow displays")
        for (indicator, display) in zip(indicators, NSScreen.screens) {
            try check(indicator.frame == geometry(display).indicator && indicator.ignoresMouseEvents,
                      "Left wing did not follow display geometry or became click-intercepting")
        }
        toggleIndicator()
        try check(indicators.isEmpty, "Indicator toggle did not remove windows")
        let rapidOpen = Task { await openNote() }
        try await waitForSmoke { self.presenter.phase == .expanding }
        let rapidClose = await closeNote()
        await rapidOpen.value
        try check(rapidClose && !panel.isVisible, "Close during opening did not wait and save")

        guard let display = NSScreen.main else { throw CocoaError(.featureUnsupported) }
        let trigger = geometry(display).trigger
        let inside = CGPoint(x: trigger.midX, y: trigger.midY)
        let outside = CGPoint(x: display.frame.minX + 30, y: display.frame.minY + 30)
        testPointer = outside; pointerMoved()
        testPointer = inside
        pointerMoved()
        try await waitForSmoke { self.presenter.phase == .expanded && self.model.isOpen }
        try check(openedByHover, "Dwell did not produce hover-opened state")
        model.text = "Hover exit saved this"
        testPointer = outside; pointerMoved()
        try await Task.sleep(nanoseconds: 60_000_000)
        testPointer = inside; pointerMoved()
        try await Task.sleep(nanoseconds: 220_000_000)
        try check(panel.isVisible && model.isOpen, "Reentry failed to cancel delayed dismissal")
        model.pinned = true
        testPointer = outside; pointerMoved()
        try await Task.sleep(nanoseconds: 240_000_000)
        try check(panel.isVisible && model.isOpen, "Pinned surface collapsed on exit")
        model.pinned = false; pointerMoved()
        try await waitForSmoke { !self.model.isOpen && !self.closing }
        try check(try String(contentsOf: file, encoding: .utf8) == "Hover exit saved this", "Hover dismissal lost edits")

        testPointer = inside; pointerMoved()
        try await waitForSmoke { self.presenter.phase == .expanded && self.model.isOpen }
        model.text = "Hover conflict buffer"
        try Data("External hover writer".utf8).write(to: file, options: .atomic)
        testPointer = outside; pointerMoved()
        try await waitForSmoke { self.model.error != nil && !self.closing }
        try check(panel.isVisible && presenter.phase == .expanded && model.text == "Hover conflict buffer",
                  "Hover save failure collapsed the surface")
        await model.reload()
        _ = await closeNote()
        testPointer = nil
        try await runSelectionChecks(file: file, display: display)
        try await runViewportChecks(file: file, display: display)
        print("HOVER_SMOKE_PASS: dwell, exit, reentry cancellation, pin, save-on-exit, conflict retention, close-during-open")
        print("SHELL_SMOKE_PASS: bookmark, open, close-save, disk refresh, conflict retention, indicator lifecycle")
    }
    private func runSelectionChecks(file: URL, display: NSScreen) async throws {
        func check(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "SelectionSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func editor() throws -> EditorProbe {
            guard let found = panel.contentView.flatMap({ EditorProbe.find(in: $0) }) else {
                throw CocoaError(.featureUnsupported)
            }
            return found
        }
        let source = (0..<150).map { "Line \($0) 🐸 writing a note\n" }.joined()
        try Data(source.utf8).write(to: file, options: .atomic)
        await openFile(file)
        let range = (source as NSString).range(of: "Line 140 🐸")
        try editor().setSelectedRange(range)
        try editor().view.scrollRangeToVisible(range)
        try check(model.editorSelection == range, "Selection delegate did not checkpoint native range")
        model.preview = true
        try await waitForSmoke { self.panel.contentView.flatMap { EditorProbe.find(in: $0) } == nil }
        model.preview = false
        try await waitForSmoke { self.panel.contentView.flatMap { EditorProbe.find(in: $0) }?.selectedRange() == range }
        model.preview = true
        try await waitForSmoke { self.panel.contentView.flatMap { EditorProbe.find(in: $0) } == nil }
        _ = await closeNote()
        try check(model.text.isEmpty && model.editorSelection == range, "Hidden buffer release erased saved selection")
        await openNote()
        let restored = try editor()
        try check(restored.selectedRange() == range && panel.firstResponder === restored.view,
                  "Explicit reopen did not focus the restored selection: native=\(restored.selectedRange()), expected=\(range), key=\(panel.isKeyWindow), editable=\(restored.isEditable), responder=\(String(describing: panel.firstResponder))")
        try check((restored.enclosingScrollView?.contentView.bounds.minY ?? 0) > 0,
                  "Reopen did not scroll the offscreen selection into view")
        // Reopen once more at a caret, not just a nonempty selection.
        let caret = NSRange(location: range.location, length: 0)
        restored.setSelectedRange(caret)
        _ = await closeNote()
        let trigger = geometry(display).trigger
        testPointer = CGPoint(x: trigger.midX, y: trigger.midY)
        await openFile(file, on: display, fromHover: true)
        let hoverEditor = try editor()
        try check(hoverEditor.selectedRange() == caret && panel.isKeyWindow &&
                  panel.firstResponder === hoverEditor.view,
                  "Hover reopen must focus the native editor at the restored caret")
        // Route a real app-local key event through the window/responder chain.
        // Do not click, makeFirstResponder, or insertText directly in this test.
        try postSmokeKey("x", keyCode: 7)
        let typed = (source as NSString).replacingCharacters(in: caret, with: "x")
        try await waitForSmoke { self.model.text == typed }
        try check(hoverEditor.selectedRange() == NSRange(location: caret.location + 1, length: 0),
                  "Typing after hover-open did not insert at the restored caret")
        _ = await closeNote()
        await openFile(file, on: display, fromHover: true)
        // A now-active hover-opened editor must dismiss on app switching,
        // including before the user has clicked or typed.
        model.pinned = true
        applicationDeactivated()
        try check(model.isOpen && !closing, "Pinned note did not ignore deactivation")
        model.pinned = false
        applicationDeactivated()
        try await waitForSmoke { !self.model.isOpen && !self.closing }
        try check(!panel.isVisible, "Unpinned hover editor ignored deactivation before interaction")
        testPointer = nil
        try Data("🐸".utf8).write(to: file, options: .atomic)
        await openNote()
        try check(try editor().selectedRange() == NSRange(location: 2, length: 0) && model.text == "🐸",
                  "Fresh shorter disk source did not clamp the caret to Unicode EOF")
        _ = await closeNote()
        let other = file.deletingLastPathComponent().appendingPathComponent("selection-other.md")
        try Data(source.utf8).write(to: other, options: .atomic)
        await openFile(other)
        try check(try editor().selectedRange() == NSRange(location: 0, length: 0),
                  "New file inherited another file's position")
        _ = await closeNote()
        print("EDITOR_SELECTION_SMOKE_PASS: caret and selection, preview recreation, hidden buffer release, scroll, explicit/hover focus, routed typing without a click, deactivation before interaction, fresh Unicode clamp, file switch")
    }
    private func runViewportChecks(file: URL, display: NSScreen) async throws {
        func check(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "ViewportSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func editor() throws -> EditorProbe {
            guard let found = panel.contentView.flatMap({ EditorProbe.find(in: $0) }) else {
                throw CocoaError(.featureUnsupported)
            }
            return found
        }
        let source = (0..<180).map { "Reading line \($0) 🐸\n" }.joined()
        try Data(source.utf8).write(to: file, options: .atomic)
        await openFile(file)
        let readingRange = (source as NSString).range(of: "Reading line 140")
        let caret = NSRange(location: 0, length: 0)
        try editor().setSelectedRange(caret)
        try editor().view.scrollRangeToVisible(readingRange)
        let saved = try editor().enclosingScrollView!.contentView.bounds.origin
        try check(saved.y > 500, "Viewport fixture did not scroll away from its caret")
        model.preview = true
        try await waitForSmoke { self.panel.contentView.flatMap { EditorProbe.find(in: $0) } == nil }
        model.preview = false
        try await waitForSmoke { self.panel.contentView.flatMap { EditorProbe.find(in: $0) } != nil }
        panel.contentView?.layoutSubtreeIfNeeded()
        try check(abs(try editor().enclosingScrollView!.contentView.bounds.origin.y - saved.y) < 1,
                  "Preview recreation lost the editor's viewport")
        _ = await closeNote()
        await openNote()
        let reopened = try editor()
        try check(reopened.selectedRange() == caret && panel.firstResponder === reopened.view,
                  "Viewport restoration changed caret or keyboard focus")
        try check(abs(reopened.enclosingScrollView!.contentView.bounds.origin.y - saved.y) < 1,
                  "Unchanged file did not restore its viewport independently of the caret")
        _ = await closeNote()
        let trigger = geometry(display).trigger
        testPointer = CGPoint(x: trigger.midX, y: trigger.midY)
        await openFile(file, on: display, fromHover: true)
        try check(abs(try editor().enclosingScrollView!.contentView.bounds.origin.y - saved.y) < 1,
                  "Hover focus overrode the saved viewport")
        try postSmokeKey("x", keyCode: 7)
        let edited = "x" + source
        try await waitForSmoke { self.model.text == edited }
        try check(try editor().selectedRange() == NSRange(location: 1, length: 0) &&
                  editor().enclosingScrollView!.contentView.bounds.origin.y < 100,
                  "Native typing did not naturally reveal the offscreen caret")
        // Save another reading viewport so external-change fallback is distinct
        // from the just-typed caret's native scroll-to-top.
        try editor().view.scrollRangeToVisible((edited as NSString).range(of: "Reading line 140"))
        _ = await closeNote()
        testPointer = nil
        // Same-length external edit must invalidate the viewport, not just shrink.
        try Data(edited.replacingOccurrences(of: "Reading", with: "Changed").utf8).write(to: file, options: .atomic)
        await openNote()
        try check(try editor().selectedRange() == NSRange(location: 1, length: 0) &&
                  editor().enclosingScrollView!.contentView.bounds.origin.y < 100,
                  "External byte change did not fall back to showing the caret")
        _ = await closeNote()
        print("EDITOR_VIEWPORT_SMOKE_PASS: independent offscreen caret, preview, menu/hover focus, exact unchanged viewport, natural typing reveal, same-length external edit fallback")
    }
    private func postSmokeKey(_ characters: String, keyCode: UInt16) throws {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: keyCode) else { throw CocoaError(.featureUnsupported) }
            NSApp.postEvent(event, atStart: false)
        }
    }
    private func waitForSmoke(_ condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw NSError(domain: "ShellSmoke", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for shell state"])
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

}
