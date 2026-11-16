import AppKit
import ServiceManagement
import SwiftUI
import ScribbitCore

final class NotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation, NSPopoverDelegate, NSWindowDelegate {
    private let model = NoteModel()
    private let isolated: Bool
    private let settings: AppSettings
    init(isolated: Bool = false) {
        self.isolated = isolated
        settings = AppSettings(isolated: isolated)
        super.init()
        model.animationSpeed = settings.animationSpeed
        model.hoverDelay = settings.hoverDelay
    }
    private var panel: NotePanel!
    private var presenter: NotchPresenter!
    private var closing = false
    private var openedByHover = false
    private var pointerInsideSurface = true
    private var exitWork: DispatchWorkItem?
    private let popupState = SettingsPopupState()
    private let settingsPopover = NSPopover()
    private var settingsPresented = false
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
        if !isolated, bookmark == nil { Task { await openNote() } }
    }

    private func applicationDeactivated() {
        guard !presentingDialog, !trackingMenu, !settingsPresented,
              NSApp.modalWindow == nil, !model.pinned else { return }
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
        panel.delegate = self
        let content = NSHostingView(rootView: NoteView(model: model,
            choose: { [weak self] in Task { await self?.chooseFile() } },
            saveCopy: { [weak self] in Task { await self?.saveCopy() } },
            reload: { [weak self] in Task { await self?.confirmReload() } },
            create: { [weak self] in Task { await self?.createFile() } },
            showSettings: { [weak self] button in self?.showSettings(from: button) }))
        presenter = NotchPresenter(panel: panel, content: content)
        presenter.animationSpeed = settings.animationSpeed
        panel.setAccessibilityLabel("Scribbit editor")
    }

    private func createMenus() {
        let main = NSMenu()
        let appRoot = NSMenuItem()
        let app = NSMenu()
        app.addItem(item("Settings…", #selector(settingsAction), key: ","))
        app.addItem(.separator())
        app.addItem(item("Quit Scribbit", #selector(quit), key: "q"))
        appRoot.submenu = app
        main.addItem(appRoot)
        let fileRoot = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let file = NSMenu(title: "File")
        file.addItem(item("Choose Note…", #selector(chooseAction), key: "o"))
        file.addItem(item("Create Note File…", #selector(createAction)))
        file.addItem(item("Save", #selector(saveAction), key: "s"))
        file.addItem(item("Close Note", #selector(closeAction), key: "w"))
        file.addItem(item("Done", #selector(closeAction), key: "\r"))
        file.addItem(item("Toggle Note Information", #selector(toggleControlsAction)))
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

        for menu in [app, file, edit] { menu.delegate = self }
    }
    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
    func menuWillOpen(_ menu: NSMenu) {
        trackingMenu = true
        exitWork?.cancel(); exitWork = nil
        refreshPopupState()
    }
    func menuDidClose(_ menu: NSMenu) {
        trackingMenu = false
        if panel.isVisible { trackOpenPointer() }
    }
    private func refreshPopupState() {
        popupState.indicator = indicatorEnabled
        popupState.launchAtLogin = !isolated && SMAppService.mainApp.status == .enabled
        popupState.loginRequiresApproval = !isolated && SMAppService.mainApp.status == .requiresApproval
    }
    private func controlButton(_ identifier: String, in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton, button.identifier?.rawValue == identifier { return button }
        return view.subviews.lazy.compactMap { self.controlButton(identifier, in: $0) }.first
    }
    private func settingsAnchor() -> NSButton? {
        if model.controlsExpanded, let gear = controlButton("openSettings", in: panel.contentView) {
            return gear
        }
        return controlButton("toggleNoteInformation", in: panel.contentView)
    }
    private func showSettings(from anchor: NSView) {
        guard !model.isBusy, !closing, !presentingDialog, !presenter.isTransitioning else { return }
        if settingsPresented { settingsPopover.performClose(nil); return }
        rememberViewport(in: panel.contentView)
        refreshPopupState()
        settingsPopover.behavior = .transient
        settingsPopover.delegate = self
        settingsPopover.contentViewController = NSHostingController(rootView: SettingsPopupView(
            model: model, settings: popupState, canChangeLogin: !isolated,
            choose: { [weak self] in self?.chooseAction() },
            create: { [weak self] in self?.createAction() },
            save: { [weak self] in self?.saveAction() },
            saveCopy: { [weak self] in
                self?.settingsPopover.performClose(nil)
                Task { await self?.saveCopy() }
            },
            close: { [weak self] in self?.closeAction() },
            loginChanged: { [weak self] in self?.toggleLogin() },
            indicatorChanged: { [weak self] in self?.toggleIndicator() },
            speedChanged: { [weak self] rate in self?.setAnimationSpeed(rate) },
            hoverDelayChanged: { [weak self] delay in self?.setHoverDelay(delay) },
            about: { [weak self] in self?.about() },
            quit: { [weak self] in self?.quit() }))
        settingsPresented = true
        exitWork?.cancel(); exitWork = nil
        settingsPopover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }
    @objc private func settingsAction() {
        Task {
            if !panel.isVisible { await openNote() }
            panel.contentView?.layoutSubtreeIfNeeded()
            if let button = settingsAnchor() { showSettings(from: button) }
        }
    }
    func popoverDidClose(_ notification: Notification) {
        settingsPresented = false
        settingsPopover.contentViewController = nil
        guard !closing, !presentingDialog, panel.isVisible else { return }
        if !isolated, !NSApp.isActive { applicationDeactivated() }
        else {
            if model.isOpen, panel.isKeyWindow { focusEditor(in: panel.contentView) }
            trackOpenPointer()
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
            if event.type == .keyDown, event.keyCode == 53, self.settingsPresented {
                self.settingsPopover.performClose(nil); return nil
            }
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
        guard !presentingDialog, !trackingMenu, !settingsPresented, !model.isBusy, !closing else { return }
        if panel.isVisible { trackOpenPointer(); return }
        let candidate = target(at: self.pointerLocation)
        if candidate != hover.target { dwell?.cancel(); dwell = nil }
        guard hover.move(to: candidate), let candidate else { return }
        scheduleDwell(for: candidate)
    }
    private func scheduleDwell(for candidate: Int) {
        dwell?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.dwell = nil
            guard self.hover.canOpen(candidate),
                  self.target(at: self.pointerLocation) == candidate,
                  NSScreen.screens.indices.contains(candidate) else { return }
            let screen = NSScreen.screens[candidate]
            Task { await self.openNote(on: screen, fromHover: true) }
        }
        dwell = work
        DispatchQueue.main.asyncAfter(deadline: .now() + model.hoverDelay, execute: work)
    }
    private func retainsHover(at point: CGPoint) -> Bool {
        presenter.contains(point) || presenter.geometry?.hoverRetentionContains(point) == true
    }
    private func trackOpenPointer() {
        guard !presenter.isTransitioning else { return }
        let inside = retainsHover(at: self.pointerLocation)
        if inside { exitWork?.cancel(); exitWork = nil }
        let changed = inside != pointerInsideSurface
        pointerInsideSurface = inside
        guard changed || exitWork == nil,
              NotchInteraction.closesOnExit(openedByHover: openedByHover, pinned: model.pinned, inside: inside,
                heldByUI: presentingDialog || trackingMenu || settingsPresented, busy: model.isBusy || closing,
                dragging: NSEvent.pressedMouseButtons != 0) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, NotchInteraction.closesOnExit(openedByHover: self.openedByHover,
                pinned: self.model.pinned, inside: self.retainsHover(at: self.pointerLocation),
                heldByUI: self.presentingDialog || self.trackingMenu || self.settingsPresented,
                busy: self.model.isBusy || self.closing,
                dragging: NSEvent.pressedMouseButtons != 0) else { return }
            Task { await self.closeNote() }
        }
        if exitWork == nil {
            exitWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.exitDelay, execute: work)
        }
    }

    private func outsideClick() {
        guard panel.isVisible, !model.pinned, !presentingDialog, !trackingMenu, !settingsPresented, NSApp.modalWindow == nil,
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
        guard !presentingDialog, !settingsPresented, !model.isBusy, !closing,
              presenter?.isTransitioning != true else { return }
        if panel.isVisible {
            openedByHover = false
            exitWork?.cancel(); exitWork = nil
            NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
            focusEditor(in: panel.contentView)
            return
        }
        if model.isUntitled, model.isDirty {
            await revealPanel(on: screen, fromHover: fromHover)
            return
        }
        do {
            guard let url = try resolveFile() else {
                await revealPanel(on: screen, fromHover: fromHover)
                return
            }
            await openFile(url, on: screen, fromHover: fromHover)
        } catch {
            showError("Cannot locate the selected note", error.localizedDescription + " Choose the file again from Settings.")
            await revealPanel(on: screen, fromHover: fromHover)
        }
    }
    private func openFile(_ selected: URL, on screen: NSScreen? = nil, fromHover: Bool = false) async {
        guard !closing, presenter.isTransitioning == false else { return }
        let url = selected.resolvingSymlinksInPath()
        let scoped = selected.startAccessingSecurityScopedResource()
        guard await model.open(url) else {
            if scoped { selected.stopAccessingSecurityScopedResource() }
            showError("Cannot open note", model.error ?? "Unknown error")
            await revealPanel(on: screen, fromHover: fromHover)
            return
        }
        // Observation outlives panel visibility. Replace the previous scope only
        // after successfully opening the new selection; quit balances the last.
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = scoped ? selected : nil
        do { try remember(selected) }
        catch { model.error = "The file opened, but its location could not be remembered: \(error.localizedDescription)" }
        await revealPanel(on: screen, fromHover: fromHover)
    }
    private func revealPanel(on screen: NSScreen? = nil, fromHover: Bool) async {
        let destination = screen ?? NSScreen.screens.first(where: { $0.frame.contains(self.pointerLocation) }) ?? NSScreen.main
        if fromHover, let destination {
            let current = geometry(destination)
            let stillInside = current.triggerContains(self.pointerLocation)
                || (indicatorEnabled && current.indicatorContains(self.pointerLocation))
            if !stillInside {
                _ = await model.close()
                return
            }
        }
        if !model.isOpen { model.openUntitled() }
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
        if let text = view as? NoteTextView {
            let origin = text.enclosingScrollView?.contentView.bounds.origin
            panel.makeFirstResponder(text)
            if model.editorScrollOrigin != nil, let origin {
                text.restoreViewport(origin)
                text.layoutSubtreeIfNeeded()
            } else {
                text.scrollRangeToVisible(text.selectedRange())
            }
            return
        }
        for child in view.subviews { focusEditor(in: child) }
    }
    private func rememberViewport(in view: NSView?) {
        guard let view else { return }
        if let editor = view as? NoteTextView, let scroll = editor.enclosingScrollView {
            model.rememberEditorScrollOrigin(scroll.contentView.bounds.origin)
            return
        }
        for child in view.subviews { rememberViewport(in: child) }
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
        guard model.isOpen || panel.isVisible else { return true }
        guard !presentingDialog else { return false }
        closing = true
        defer { closing = false }
        settingsPopover.performClose(nil)
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
        dwell?.cancel(); dwell = nil
        hover.suppressUntilExit()
        if target(at: self.pointerLocation) == nil { _ = hover.move(to: nil) }
        refreshIndicators()
        return true
    }

    private func chooseFile() async {
        guard !presentingDialog, !model.isBusy, !closing, presenter?.isTransitioning != true else { return }
        guard await resolveUntitledBeforeReplacement(), await closeNote() else { return }
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
        if model.isUntitled { _ = await saveUntitled(); return }
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
    /// Drafts survive ordinary dismissal. Only explicit replacement or quit asks
    /// whether to save/discard; cancelling either dialog leaves the draft intact.
    private func resolveUntitledBeforeReplacement() async -> Bool {
        commitComposition(in: panel.contentView)
        guard model.isUntitled, model.isDirty else { return true }
        presentingDialog = true
        settingsPopover.performClose(nil)
        if !panel.isVisible { await revealPanel(fromHover: false) }
        let alert = NSAlert()
        alert.messageText = "Save your untitled note?"
        alert.informativeText = "Unsaved changes will be lost if you discard this note."
        alert.addButton(withTitle: "Save As…")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard")
        let response = await withCheckedContinuation { continuation in
            alert.window.level = panel.level
            alert.beginSheetModal(for: panel) { continuation.resume(returning: $0) }
        }
        presentingDialog = false
        switch response {
        case .alertFirstButtonReturn: return await saveUntitled()
        case .alertThirdButtonReturn: model.discardUntitled(); return true
        default: return false
        }
    }
    private func saveUntitled() async -> Bool {
        guard model.isUntitled, !presentingDialog, !model.isBusy, !closing else { return false }
        commitComposition(in: panel.contentView)
        presentingDialog = true
        settingsPopover.performClose(nil)
        if !panel.isVisible { await revealPanel(fromHover: false) }
        let picker = NSSavePanel()
        picker.title = "Save untitled note to a new file"
        picker.nameFieldStringValue = "Notes.md"
        let response = await withCheckedContinuation { continuation in
            picker.beginSheetModal(for: panel) { continuation.resume(returning: $0) }
        }
        guard response == .OK, let selected = picker.url else {
            presentingDialog = false
            return false
        }
        let scoped = selected.startAccessingSecurityScopedResource()
        let saved = await model.saveUntitled(to: selected.resolvingSymlinksInPath())
        presentingDialog = false
        if saved {
            accessedURL?.stopAccessingSecurityScopedResource()
            accessedURL = scoped ? selected : nil
            do { try remember(selected) }
            catch { model.error = "Saved, but the location could not be remembered: \(error.localizedDescription)" }
            if !panel.isVisible { await revealPanel(fromHover: false) }
        } else if scoped { selected.stopAccessingSecurityScopedResource() }
        return saved
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
        settingsPopover.performClose(nil)
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
            if reportError { showError("Could not change Launch at Login", error.localizedDescription + " Install the bundled app in Applications, then try the setting again.") }
        }
        refreshPopupState()
    }
    @objc private func toggleLogin() {
        guard !isolated else { return }
        let state = SMAppService.mainApp.status
        if state == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        else { setLogin(enabled: state != .enabled, reportError: true) }
    }
    @objc private func toggleIndicator() {
        settings.indicator = !indicatorEnabled
        refreshPopupState(); refreshIndicators()
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
    }
    private func setHoverDelay(_ delay: Double) {
        let normalized = HoverDelay.normalized(delay)
        guard model.hoverDelay != normalized else { return }
        settings.hoverDelay = normalized
        model.hoverDelay = settings.hoverDelay
        // Restart only an already-pending entry, never reset HoverGate: resetting
        // it would erase explicit-close suppression while still over the notch.
        let candidate = dwell == nil ? nil : hover.target
        dwell?.cancel(); dwell = nil
        guard !panel.isVisible, !presentingDialog, !trackingMenu, !settingsPresented,
              !model.isBusy, !closing, let candidate, hover.canOpen(candidate),
              target(at: pointerLocation) == candidate else { return }
        scheduleDwell(for: candidate)
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
    @objc private func chooseAction() {
        settingsPopover.performClose(nil)
        Task { await chooseFile() }
    }
    @objc private func createAction() {
        settingsPopover.performClose(nil)
        Task { await createFile() }
    }
    @objc private func saveAction() {
        guard !model.resetInProgress else { return }
        commitComposition(in: panel.contentView)
        Task {
            if model.isUntitled { _ = await saveUntitled() }
            else { await model.save() }
        }
    }
    private var editableResponder: NSTextView? {
        guard !model.isBusy, !model.resetInProgress, let editor = panel?.firstResponder as? NSTextView,
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
        guard !presentingDialog, panel.isVisible else { return }
        presentingDialog = true
        settingsPopover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        let identity = AboutInfo(infoDictionary: Bundle.main.infoDictionary)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.messageText = identity.name
        alert.informativeText = identity.versionText
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Reset App…")
        // A standalone app-modal alert can sit below the status-bar-level
        // notch panel. Use native sheet parenting/order at the panel's level.
        alert.window.level = panel.level
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard let self else { return }
            if response == .alertSecondButtonReturn {
                // Defer until AppKit has finished ending the About sheet.
                Task { await self.resetApp() }
                return
            }
            self.presentingDialog = false
            if self.model.isOpen, self.panel.isKeyWindow { self.focusEditor(in: self.panel.contentView) }
            self.trackOpenPointer()
        }
    }
    /// Invoked only from About after an explicit user click. The isolated
    /// harness cannot register/unregister login items or touch real defaults.
    private func resetApp() async {
        guard !model.isBusy, !closing else { presentingDialog = false; return }
        presentingDialog = true
        defer {
            model.resetInProgress = false
            presentingDialog = false
            if model.isOpen, panel.isKeyWindow { focusEditor(in: panel.contentView) }
            trackOpenPointer()
        }
        let confirmation = NSAlert()
        confirmation.alertStyle = .warning
        confirmation.messageText = "Reset Scribbit for first-time setup?"
        confirmation.informativeText = "This forgets the selected file, resets Scribbit settings and cursor position, and turns off Launch at Login. Your note files are never deleted. Unsaved text must be saved or explicitly discarded. A blank untitled notepad will open immediately. Like a first launch, the next launch will attempt to enable Launch at Login again."
        confirmation.addButton(withTitle: "Cancel")
        confirmation.addButton(withTitle: "Continue…")
        guard await resetSheet(confirmation) == .alertSecondButtonReturn else { return }
        // Explicit setup intent keeps cancellation/save errors visible after sheets.
        openedByHover = false
        commitComposition(in: panel.contentView)
        if model.isDirty {
            let edits = NSAlert()
            edits.messageText = "Save your note before resetting?"
            edits.informativeText = "Discard removes only the unsaved text from Scribbit. The existing note file will not be changed."
            edits.addButton(withTitle: model.isUntitled ? "Save As…" : "Save")
            edits.addButton(withTitle: "Cancel")
            edits.addButton(withTitle: "Discard")
            switch await resetSheet(edits) {
            case .alertFirstButtonReturn:
                if model.isUntitled {
                    presentingDialog = false
                    let saved = await saveUntitled()
                    presentingDialog = true
                    guard saved else { return }
                } else {
                    await model.save()
                    guard !model.isDirty, model.error == nil else { return }
                }
            case .alertThirdButtonReturn: break // Defer actual discard until reset commits.
            default: return
            }
        }
        model.resetInProgress = true
        panel.makeFirstResponder(nil)
        if !isolated {
            do {
                if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                    try await SMAppService.mainApp.unregister()
                }
            } catch {
                model.error = "Reset cancelled because Launch at Login could not be disabled: \(error.localizedDescription)"
                return
            }
        }
        guard await model.resetDiscardingEdits() else { return }
        accessedURL?.stopAccessingSecurityScopedResource(); accessedURL = nil
        settings.reset()
        model.animationSpeed = settings.animationSpeed
        presenter.animationSpeed = settings.animationSpeed
        model.hoverDelay = settings.hoverDelay
        dwell?.cancel(); dwell = nil
        exitWork?.cancel(); exitWork = nil
        hover = HoverGate()
        openedByHover = false
        pointerInsideSurface = true
        refreshPopupState()
        refreshIndicators()
        // Let SwiftUI recreate the editor if reset was requested from preview.
        await Task.yield()
        panel.contentView?.layoutSubtreeIfNeeded()
        clearEditorHistory(in: panel.contentView)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    private func resetSheet(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        alert.window.level = panel.level
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: panel) { continuation.resume(returning: $0) }
        }
    }
    private func clearEditorHistory(in view: NSView?) {
        guard let view else { return }
        if let editor = view as? NoteTextView {
            editor.breakUndoCoalescing()
            editor.undoManager?.removeAllActions()
            return
        }
        for child in view.subviews { clearEditorHistory(in: child) }
    }
    func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect {
        guard window === panel, let geometry = presenter.geometry else { return rect }
        return geometry.sheetAttachmentRect(in: window.frame, proposed: rect)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { await openNote() }
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !presentingDialog, !model.isBusy else { return .terminateCancel }
        Task {
            let proceed = await resolveUntitledBeforeReplacement()
            NSApp.reply(toApplicationShouldTerminate: proceed ? await closeNote() : false)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        settingsPopover.performClose(nil)
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
        refreshPopupState()
        defer {
            settingsPopover.performClose(nil)
            panel.orderOut(nil)
            indicators.forEach { $0.orderOut(nil) }
            applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        func check(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "ShellSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        try check(BrandAssets.notch.isTemplate && BrandAssets.notch.representations.count == 2,
                  "Notch template is missing its scale representations")
        if Bundle.main.bundleURL.pathExtension == "app" {
            try check(BrandAssets.resourceBundle.bundleURL.path.hasPrefix(Bundle.main.bundleURL.path + "/Contents/Resources/"),
                      "Brand assets were loaded from build cache instead of the app")
        }
        await openNote()
        try check(panel.isVisible && model.isOpen && model.isUntitled,
                  "No-file launch did not reveal an editable untitled notepad")
        try check(controlButton("openSettings", in: panel.contentView) == nil &&
                  settingsAnchor()?.identifier?.rawValue == "toggleNoteInformation",
                  "Collapsed untitled state did not expose the visible chevron fallback")
        settingsAction()
        try await waitForSmoke { self.settingsPopover.isShown && self.settingsPresented }
        try check(settingsPopover.contentViewController != nil,
                  "Untitled notepad settings popup was inaccessible")
        settingsPopover.performClose(nil)
        guard let draftEditor = panel.contentView.flatMap({ EditorProbe.find(in: $0) }) else {
            throw CocoaError(.featureUnsupported)
        }
        try check(draftEditor.isEditable && panel.firstResponder === draftEditor.view,
                  "Untitled editor did not receive native keyboard focus")
        model.text = "Disposable RAM-only draft"
        _ = await closeNote()
        await openNote()
        try check(model.isUntitled && model.text == "Disposable RAM-only draft",
                  "Dismissing and reopening discarded the untitled draft")
        model.discardUntitled()
        _ = await closeNote()
        await openFile(file)
        try check(panel.isVisible && model.isOpen, "Shell open failed")
        try check(bookmark != nil, "Isolated bookmark could not be created")
        try check(EditorProbe.find(in: panel.contentView!)?.view is NoteTextView,
                  "Shell did not use the native note editor")
        let settingsItem = NSApp.mainMenu?.items.first?.submenu?.items.first(where: { $0.action == #selector(settingsAction) })
        try check(settingsItem?.keyEquivalent == ",", "Settings lost the native Command-comma action")
        guard let editor = EditorProbe.find(in: panel.contentView!) else { throw CocoaError(.featureUnsupported) }
        let popupSource = model.text
        let popupSelection = editor.selectedRange()
        let popupHistory = editor.undoManager
        model.controlsExpanded = true
        try await waitForSmoke { self.controlButton("openSettings", in: self.panel.contentView) != nil }
        guard let anchor = controlButton("openSettings", in: panel.contentView) else { throw CocoaError(.featureUnsupported) }
        anchor.performClick(nil)
        try await waitForSmoke { self.settingsPopover.isShown && self.settingsPresented }
        try check(model.editorScrollOrigin != nil, "Settings did not checkpoint the native viewport")
        outsideClick()
        applicationDeactivated()
        try await Task.sleep(nanoseconds: 220_000_000)
        try check(model.isOpen && !closing && panel.isVisible, "Settings interaction dismissed the note")
        settingsPopover.performClose(nil)
        try await waitForSmoke { !self.settingsPresented }
        try check(EditorProbe.find(in: panel.contentView!)?.view === editor.view &&
                  model.text == popupSource && editor.selectedRange() == popupSelection &&
                  editor.undoManager === popupHistory, "Settings popup replaced editor, source, selection or undo")
        model.controlsExpanded = false
        try await waitForSmoke { self.controlButton("openSettings", in: self.panel.contentView) == nil }
        print("SETTINGS_POPUP_SMOKE_PASS: collapsed Command-comma/visible chevron anchor, expanded gear, hold during popup, editor/selection/history retention")
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
        let retention = geometry(display).hoverRetentionFrame
        let grace = CGPoint(x: retention.minX + 4, y: retention.midY)
        try check(!presenter.contains(grace) && retainsHover(at: grace),
                  "Hover grace fixture was not outside the actual surface")
        testPointer = grace; pointerMoved()
        try await Task.sleep(nanoseconds: 240_000_000)
        try check(model.isOpen && panel.isVisible && exitWork == nil,
                  "Pointer grace area incorrectly scheduled hover dismissal")
        testPointer = outside; pointerMoved()
        try await Task.sleep(nanoseconds: 60_000_000)
        testPointer = grace; pointerMoved()
        try await Task.sleep(nanoseconds: 220_000_000)
        try check(model.isOpen && panel.isVisible && exitWork == nil,
                  "Returning to the grace area did not cancel pending dismissal")
        // Grace is not an invisible click target: an intentional outside click
        // still saves/closes using the real contour rather than the buffer.
        outsideClick()
        try await waitForSmoke { !self.model.isOpen && !self.closing }
        try check(!panel.isVisible, "Hover grace area swallowed an outside click")
        testPointer = inside; pointerMoved()
        try await waitForSmoke { self.presenter.phase == .expanded && self.model.isOpen }
        print("HOVER_RETENTION_SMOKE_PASS: outside-contour grace, delayed-close cancellation, unchanged outside-click behavior")
        settingsAction()
        try await waitForSmoke { self.settingsPresented && self.settingsPopover.isShown }
        testPointer = outside; pointerMoved()
        try await Task.sleep(nanoseconds: 240_000_000)
        try check(model.isOpen && panel.isVisible, "Hover exit dismissed the note while settings were open")
        testPointer = inside
        guard let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: settingsPopover.contentViewController?.view.window?.windowNumber ?? panel.windowNumber,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53) else { throw CocoaError(.featureUnsupported) }
        NSApp.postEvent(escape, atStart: false)
        try await waitForSmoke { !self.settingsPresented }
        try check(model.isOpen && panel.isVisible, "Escape closed the note instead of just settings")
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
        try await runHoverSettingsChecks(display: display)
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
    private func runHoverSettingsChecks(display: NSScreen) async throws {
        func check(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "HoverSettingsSmoke", code: 1,
                                     userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let trigger = geometry(display).trigger
        let inside = CGPoint(x: trigger.midX, y: trigger.midY)
        let outside = CGPoint(x: display.frame.minX + 30, y: display.frame.minY + 30)
        testPointer = outside; pointerMoved()
        setHoverDelay(1)
        testPointer = inside; pointerMoved()
        let oldDwell = dwell
        setHoverDelay(0.8)
        try check(oldDwell != nil && oldDwell?.isCancelled == true && dwell != nil && dwell !== oldDwell,
                  "Changing hover delay did not cancel and replace a pending dwell")
        try check(settings.hoverDelay == model.hoverDelay && HoverDelay.label(model.hoverDelay) == "800 ms",
                  "Hover delay setting and model did not stay synchronized")
        // A 100/250 ms hard-coded deadline would open before this point.
        try await Task.sleep(nanoseconds: 350_000_000)
        try check(!model.isOpen && presenter.phase == .hidden,
                  "Controller ignored the configured longer hover delay")
        let changedDwell = dwell
        testPointer = outside; pointerMoved()
        try check(changedDwell?.isCancelled == true && dwell == nil,
                  "Leaving the trigger did not cancel the configured dwell")
        setHoverDelay(HoverDelay.defaultValue)
        testPointer = inside; pointerMoved()
        try await waitForSmoke { self.model.isOpen && self.presenter.phase == .expanded }
        _ = await closeNote()
        setHoverDelay(HoverDelay.range.lowerBound)
        testPointer = inside; pointerMoved()
        try check(dwell == nil && !model.isOpen,
                  "Changing hover delay erased close-until-exit suppression")
        testPointer = outside; pointerMoved()
        // Zero removes the dwell, but still queues guarded work. Leaving before
        // that work runs must cancel it rather than open a stale hover request.
        try check(model.hoverDelay == 0 && settings.hoverDelay == 0,
                  "Zero hover delay was not retained by settings and model")
        testPointer = inside; pointerMoved()
        let zeroDwell = dwell
        testPointer = outside; pointerMoved()
        try check(zeroDwell != nil && zeroDwell?.isCancelled == true && dwell == nil && !model.isOpen,
                  "Zero-delay hover bypassed pointer-exit cancellation")
        testPointer = inside; pointerMoved()
        try await waitForSmoke { self.model.isOpen && self.presenter.phase == .expanded }
        _ = await closeNote()
        pointerMoved()
        try check(dwell == nil && !model.isOpen,
                  "Zero-delay hover bypassed explicit-close suppression")
        testPointer = outside; pointerMoved()
        testPointer = nil
        setHoverDelay(HoverDelay.defaultValue)
        print("HOVER_SETTINGS_SMOKE_PASS: persisted model synchronization, configurable deadline, pending cancellation/restart, zero-delay opening and cancellation, pointer exit, close suppression")
    }

}
