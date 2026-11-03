import FlypeCore
import SwiftUI
import UIKit

#if DEBUG
    import KeyboardKitHostPlugin
#endif

final class KeyboardViewController: UIInputViewController, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
    private let root = UIStackView()
    private let rows = KeyboardKeyGrid()
    private weak var spaceButton: KeyboardKeyButton?
    private var languageMenuState: String?
    private var language = FlypeLanguage.recognition()
    private var tabletLayout = false
    private var usesTabletLayout: Bool { traitCollection.userInterfaceIdiom == .pad && view.bounds.width > 650 }
    private let suggestionBar = WordSuggestionBar()
    private let wordSuggestions = WordSuggestions()
    private var suggestionTask: Task<Void, Never>?
    private var suggestionPending = false
    private var lastSuggestionContext: WordSuggestionContext?
    private var suggestionDocumentID: UUID?
    private var displayedSuggestions: [String] = []
    private var suggestionsExcluded = false
    private var displayedSuggestionContext: WordSuggestionContext?
    private var displayedSuggestionDocumentID: UUID?
    private let recordingView = RecordingLevelView()
    private var showsInputModeSwitchKey = false
    private var meterTimer: Timer?
    private let insert = UIButton(type: .system)
    private var pending: DictationResult?
    private var refreshTimer: Timer?
    private var deleteTimer: Timer?
    private var letterKeys: [(KeyboardKeyButton, String)] = []
    private var shiftButtons: [KeyboardKeyButton] = []
    private let keyPreview = UILabel()
    private let alternateStrip = KeyboardAlternatesView()
    private var alternateValues: [String] = []
    private weak var alternateSource: KeyboardKeyButton?
    private weak var previewSource: KeyboardKeyButton?
    private let previewGesture = KeyboardPreviewGesture()
    private var lastShiftTap: TimeInterval = 0
    private var lastSpaceTap: TimeInterval = 0
    private struct SuggestionSelection {
        let word: String
        let context: WordSuggestionContext
        let documentID: UUID
    }
    private var activeSuggestion: SuggestionSelection?
    private var suggestionTouchActive = false
    private var uppercase = true
    private var capsLock = false
    private var symbols = false
    private var secondarySymbols = false
    private var heightConstraint: NSLayoutConstraint?
    private var lastError: String?
    private weak var returnButton: UIButton?
    private var launchHost: UIHostingController<DictationLaunchLink>?
    private var startRequest: KeyboardStartRequest?
    private var resolvedHostID: String?
    private var voiceSession: VoiceSessionState?
    private var commandSentAt: Date?
    private var pendingStartID: UUID?
    private var insertionPermit: KeyboardInsertionPermit?
    #if DEBUG
        private var hostResolutionTask: Task<Void, Never>?
    #endif
    private var isVisible = false
    private var isInserting = false
    private var refreshLoading = false
    private var refreshAgain = false
    private var lastKeyboardSeenWrite: TimeInterval = 0
    private struct RenderedMicrophone: Equatable {
        var url: URL?
        var phase: VoiceSessionState.Phase?
    }
    private var renderedMicrophone = RenderedMicrophone()
    private weak var renderedReturnButton: UIButton?
    private var renderedReturnTitle: String?

    override func loadView() {
        let keyboardView = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
        keyboardView.allowsSelfSizing = true
        keyboardView.keyGrid = rows
        keyboardView.suggestionBar = suggestionBar
        inputView = keyboardView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Without full access the shared preferences are out of reach, so follow the device instead.
        if !hasFullAccess { language = .interface() }
        primaryLanguage = language.localeIdentifier
        wordSuggestions.selectedLanguage = language
        // Leave the host's keyboard material visible instead of painting a solid surface.
        // Fully transparent areas never reach this process, so gaps and margins need a trace of alpha.
        view.backgroundColor = UIColor(white: 0, alpha: 0.001)
        view.isOpaque = false
        buildInterface()
        NotificationCenter.default.addObserver(
            self, selector: #selector(hostBecameActive), name: .NSExtensionHostDidBecomeActive, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(hostBecameInactive), name: .NSExtensionHostWillResignActive, object: nil)
    }

    @objc private func hostBecameActive() {
        // App switching does not necessarily repeat the input controller appearance callbacks.
        guard isViewLoaded, view.window != nil else { return }
        isVisible = true
        restoreInsertionPermit()
        lastSuggestionContext = nil
        synchronizeCapitalization()
        resolveHostForReturn()
        startRefreshTimer()
        refresh()
    }

    @objc private func hostBecameInactive() {
        isVisible = false
        dismissAlternates()
        hideKeyPreview()
        refreshTimer?.invalidate()
        meterTimer?.invalidate()
        cancelSuggestions()
    }

    private func resolveHostForReturn() {
        #if DEBUG
            guard hostResolutionTask == nil else { return }
            hostResolutionTask = Task { [weak self] in
                guard let self else { return }
                defer { hostResolutionTask = nil }
                do {
                    resolvedHostID = try await pluginHostApplicationResolver(
                        controller: self, pollingInterval: 0.1, timeout: 2)
                    print("FLYPE_HOST_RESOLVED available=\(resolvedHostID != nil)")
                    if isVisible { refresh() }
                } catch {
                    resolvedHostID = nil
                    print("FLYPE_HOST_RESOLUTION_FAILED")
                }
            }
        #endif
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            timeInterval: 0.35, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
        startRefreshTimer()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // iOS only applies this once the keyboard is connected to the text field.
        hasDictationKey = true
        isVisible = true
        restoreInsertionPermit()
        lastSuggestionContext = nil
        synchronizeCapitalization()
        resolveHostForReturn()
        refresh()
        #if DEBUG
            KeyboardTouchDiagnostics.shared.logSystemGestures(from: view)
        #endif
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        #if DEBUG
            KeyboardTouchDiagnostics.shared.logSummary()
        #endif
        isVisible = false
        dismissAlternates()
        hideKeyPreview()
        refreshTimer?.invalidate()
        deleteTimer?.invalidate()
        meterTimer?.invalidate()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        // Keyboard-originated results are one-use return handoffs; document IDs can change after app switching.
        synchronizeCapitalization()
        refresh()
    }

    override func selectionDidChange(_ textInput: (any UITextInput)?) {
        super.selectionDidChange(textInput)
        synchronizeCapitalization()
        scheduleSuggestions()
    }

    private func buildInterface() {
        root.axis = .vertical
        root.spacing = 2
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5),
        ])
        heightConstraint = view.heightAnchor.constraint(equalToConstant: 216)
        heightConstraint?.priority = .init(999)
        heightConstraint?.isActive = true

        let launchHost = UIHostingController(rootView: DictationLaunchLink(url: nil))
        addChild(launchHost)
        launchHost.view.tag = KeyboardKeyGrid.hostedKeyTag
        launchHost.view.backgroundColor = .clear
        launchHost.safeAreaRegions = []
        launchHost.didMove(toParent: self)
        self.launchHost = launchHost
        insert.setImage(UIImage(systemName: "document.on.clipboard"), for: .normal)
        insert.tintColor = .label
        insert.accessibilityLabel = L10n.text("Bereitgestellte Transkription einfügen")
        insert.addTarget(self, action: #selector(insertResult), for: .touchUpInside)
        let insertWidth = insert.widthAnchor.constraint(equalToConstant: 40)
        insertWidth.priority = .init(999)
        insertWidth.isActive = true
        insert.isHidden = true

        let suggestionHeight = suggestionBar.heightAnchor.constraint(equalToConstant: 44)
        suggestionHeight.priority = .init(999)
        suggestionHeight.isActive = true
        suggestionBar.onBegin = { [weak self] index in self?.beginSuggestionSelection(at: index) }
        suggestionBar.onSelect = { [weak self] index in self?.acceptSuggestion(at: index) }
        suggestionBar.onCancel = { [weak self] in self?.cancelSuggestionSelection() }
        root.addArrangedSubview(suggestionBar)
        rows.axis = .vertical
        rows.spacing = 10
        rows.distribution = .fillEqually
        root.addArrangedSubview(rows)
        view.addSubview(recordingView)
        recordingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            recordingView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            recordingView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            recordingView.topAnchor.constraint(equalTo: root.topAnchor),
            recordingView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        recordingView.isHidden = true
        recordingView.stopButton.addTarget(self, action: #selector(stopFromLevelView), for: .touchUpInside)
        keyPreview.font = .systemFont(ofSize: 30)
        keyPreview.textAlignment = .center
        keyPreview.textColor = .label
        keyPreview.backgroundColor = .secondarySystemGroupedBackground
        keyPreview.layer.cornerRadius = 9
        keyPreview.layer.masksToBounds = true
        keyPreview.isUserInteractionEnabled = false
        keyPreview.isAccessibilityElement = false
        keyPreview.isHidden = true
        view.addSubview(keyPreview)
        view.addSubview(alternateStrip)
        previewGesture.onDown = { [weak self] key in self?.showKeyPreview(for: key) }
        previewGesture.onUp = { [weak self] key in
            if self?.previewSource === key { self?.hideKeyPreview() }
        }
        view.addGestureRecognizer(previewGesture)
        buildKeys()
        updateAppearance()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if tabletLayout != usesTabletLayout || showsInputModeSwitchKey != needsInputModeSwitchKey {
            tabletLayout = usesTabletLayout
            showsInputModeSwitchKey = needsInputModeSwitchKey
            buildKeys()
            updateRecordingView()
        }
        #if DEBUG
            guard FlypePreferences.defaults.bool(forKey: "keyboardLayoutDiagnostics") else { return }
            let geometry: [String: Double] = [
                "viewHeight": view.bounds.height, "viewY": view.frame.minY,
                "rootTop": root.frame.minY, "suggestionTop": suggestionBar.frame.minY,
                "suggestionHeight": suggestionBar.frame.height, "safeAreaTop": view.safeAreaInsets.top,
                "parentHeight": Double(view.superview?.bounds.height ?? 0),
                "windowTop": view.convert(.zero, to: view.window).y,
            ]
            if let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
                let data = try? JSONEncoder().encode(geometry)
            {
                try? data.write(to: cache.appendingPathComponent("layout-diagnostic.json"), options: .atomic)
            }
        #endif
    }

    @objc private func stopFromLevelView() { controlSession() }

    @objc private func refreshMeter() {
        guard isVisible, hasFullAccess else {
            meterTimer?.invalidate()
            return
        }
        do {
            guard let state = try VoiceSessionStore.shared().state(), state.phase == .recording else {
                meterTimer?.invalidate()
                meterTimer = nil
                refresh()
                return
            }
            voiceSession = state
            recordingView.update(state)
        } catch {
            meterTimer?.invalidate()
            meterTimer = nil
            refresh()
        }
    }

    private func updateRecordingView() {
        let recording = voiceSession?.phase == .recording && hasFullAccess
        let processing =
            (voiceSession?.phase == .processing || voiceSession?.phase == .preparing) && hasFullAccess
        let keyHeight: CGFloat = usesTabletLayout ? 290 : 216
        let desiredHeight: CGFloat =
            recording || processing ? (usesTabletLayout ? 290 : 216) : keyHeight + (suggestionBar.isHidden ? 0 : 46)
        if heightConstraint?.constant != desiredHeight {
            heightConstraint?.constant = desiredHeight
            preferredContentSize = CGSize(width: view.bounds.width, height: desiredHeight)
            inputView?.invalidateIntrinsicContentSize()
        }
        root.isHidden = recording || processing
        recordingView.isHidden = !(recording || processing)
        recordingView.showsProgress = processing
        if recording, let voiceSession {
            recordingView.update(voiceSession)
            if isVisible, meterTimer?.isValid != true {
                meterTimer = Timer.scheduledTimer(
                    timeInterval: 0.033, target: self, selector: #selector(refreshMeter), userInfo: nil, repeats: true)
                if let meterTimer { RunLoop.main.add(meterTimer, forMode: .common) }
            }
        } else {
            meterTimer?.invalidate()
            meterTimer = nil
        }
    }

    private func buildKeys() {
        dismissAlternates()
        hideKeyPreview()
        letterKeys.removeAll()
        shiftButtons.removeAll()
        for child in rows.arrangedSubviews {
            rows.removeArrangedSubview(child)
            child.removeFromSuperview()
        }
        rows.distribution = .fillEqually
        rows.spacing = usesTabletLayout ? 7 : 10
        if usesTabletLayout && !symbols {
            buildTabletKeys()
            return
        }
        let letters = language.keyboardRows.map(Array.init)
        let digits = [
            Array("1234567890").map(String.init), ["-", "/", ":", ";", "(", ")", "€", "&", "@", "\""],
            [".", ",", "?", "!", "'"],
        ]
        let extras = [
            Array("[]{}#%^*+=").map(String.init), ["_", "\\", "|", "~", "<", ">", "$", "£", "¥", "•"],
            [".", ",", "?", "!", "'"],
        ]
        let layout = symbols ? (secondarySymbols ? extras : digits) : letters.map { $0.map(String.init) }
        for (index, characters) in layout.enumerated() {
            let row = makeRow()
            if index == 2 {
                let title = symbols ? (secondarySymbols ? "123" : "#+=") : ""
                let shift = key(title, special: true)
                shift.titleLabel?.font = .systemFont(ofSize: 16)
                if !symbols {
                    shiftButtons.append(shift)
                    shift.setImage(UIImage(systemName: shiftSymbol), for: .normal)
                }
                shift.accessibilityLabel =
                    L10n.text(symbols ? "Weitere Sonderzeichen" : "Umschalttaste; doppeltippen für Feststelltaste")
                shift.addTarget(self, action: #selector(toggleShift), for: symbols ? .touchUpInside : .touchDown)
                row.addArrangedSubview(shift)
            }
            for character in characters {
                let title = !symbols && uppercase ? capitalizedKey(character) : character
                let button = key(title)
                if !symbols {
                    letterKeys.append((button, character))
                }
                configureAlternates(on: button, character: character)
                button.addAction(UIAction { [weak self] _ in self?.type(character) }, for: .touchUpInside)
                row.addArrangedSubview(button)
            }
            if index == 2 {
                let delete = key("", special: true)
                delete.setImage(UIImage(systemName: "delete.left"), for: .normal)
                delete.accessibilityLabel = L10n.text("Löschen")
                delete.addAction(UIAction { [weak self] _ in self?.deleteCharacter() }, for: .touchUpInside)
                configureRepeatedDelete(on: delete)
                row.addArrangedSubview(delete)
            }
            if index == 2, let first = row.arrangedSubviews.first, let last = row.arrangedSubviews.last {
                row.distribution = .fill
                first.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.115).isActive = true
                last.widthAnchor.constraint(equalTo: first.widthAnchor).isActive = true
                let characterKeys = Array(row.arrangedSubviews.dropFirst().dropLast())
                if symbols, let reference = characterKeys.first {
                    for key in characterKeys.dropFirst() {
                        key.widthAnchor.constraint(equalTo: reference.widthAnchor).isActive = true
                    }
                } else {
                    // Seven bottom letters retain the width of the eleven keys above.
                    // Flexible shoulders reproduce the native German row's indentation.
                    let leftShoulder = UIView()
                    let rightShoulder = UIView()
                    row.insertArrangedSubview(leftShoulder, at: 1)
                    row.insertArrangedSubview(rightShoulder, at: row.arrangedSubviews.count - 1)
                    leftShoulder.widthAnchor.constraint(equalTo: rightShoulder.widthAnchor).isActive = true
                    for key in characterKeys {
                        key.widthAnchor.constraint(
                            equalTo: row.widthAnchor, multiplier: 1.0 / CGFloat(language.keyboardRows[0].count),
                            constant: -6.0 * CGFloat(language.keyboardRows[0].count - 1)
                                / CGFloat(language.keyboardRows[0].count)
                        ).isActive = true
                    }
                }
            }
            rows.addArrangedSubview(row)
        }
        addBottomRow()
    }

    private func updateLanguageMenu() {
        guard let spaceButton else { return }
        let locked =
            voiceSession?.phase == .recording || voiceSession?.phase == .processing || voiceSession?.phase == .preparing
        let state = "\(language.rawValue)/\(FlypeLanguage.interface().rawValue)/\(locked)"
        guard languageMenuState != state || spaceButton.menu == nil else { return }
        languageMenuState = state
        spaceButton.menu = UIMenu(
            title: L10n.text("Sprache"),
            children: FlypeLanguage.allCases.map { value in
                UIAction(title: value.name, attributes: locked ? .disabled : [], state: value == language ? .on : .off)
                { [weak self] _ in
                    guard let self else { return }
                    FlypePreferences.defaults.set(value.rawValue, forKey: "dictationLanguage")
                    language = value
                    primaryLanguage = value.localeIdentifier
                    wordSuggestions.selectedLanguage = value
                    lastSuggestionContext = nil
                    updateLanguageMenu()
                    buildKeys()
                    scheduleSuggestions()
                }
            })
    }

    private func buildTabletKeys() {
        let numberRow = makeRow()
        for character in Array("1234567890").map(String.init) + (language == .de ? ["ß"] : []) {
            let button = key(character)
            configureAlternates(on: button, character: character)
            button.addAction(UIAction { [weak self] _ in self?.type(character) }, for: .touchUpInside)
            numberRow.addArrangedSubview(button)
        }
        let delete = key("", special: true)
        delete.setImage(UIImage(systemName: "delete.left"), for: .normal)
        delete.accessibilityLabel = L10n.text("Löschen")
        delete.addAction(UIAction { [weak self] _ in self?.deleteCharacter() }, for: .touchUpInside)
        configureRepeatedDelete(on: delete)
        numberRow.addArrangedSubview(delete)
        rows.addArrangedSubview(numberRow)
        for (index, characters) in language.keyboardRows.enumerated() {
            let row = makeRow()
            let leading = key("", special: true)
            leading.setImage(
                UIImage(systemName: index == 0 ? "arrow.right.to.line" : shiftSymbol),
                for: .normal)
            leading.accessibilityLabel = L10n.text(index == 0 ? "Tabulator" : "Umschalten")
            if index == 0 {
                leading.addAction(UIAction { [weak self] _ in self?.insertText("\t") }, for: .touchUpInside)
            } else {
                leading.addTarget(self, action: #selector(toggleShift), for: .touchDown)
                shiftButtons.append(leading)
            }
            row.addArrangedSubview(leading)
            let values =
                Array(characters).map(String.init)
                + (index == 0 && language == .de ? ["+"] : index == 2 ? [",", ".", "-"] : [])
            for character in values {
                let button = key(uppercase ? capitalizedKey(character) : character)
                letterKeys.append((button, character))
                configureAlternates(on: button, character: character)
                button.addAction(UIAction { [weak self] _ in self?.type(character) }, for: .touchUpInside)
                row.addArrangedSubview(button)
            }
            if index == 1 {
                let enter = key("", special: true)
                enter.setImage(UIImage(systemName: "return"), for: .normal)
                enter.accessibilityLabel = returnTitle
                returnButton = enter
                enter.addAction(UIAction { [weak self] _ in self?.insertText("\n") }, for: .touchUpInside)
                row.addArrangedSubview(enter)
            } else if index == 2 {
                let shift = key("", special: true)
                shift.setImage(UIImage(systemName: shiftSymbol), for: .normal)
                shift.accessibilityLabel = L10n.text("Umschalten")
                shiftButtons.append(shift)
                shift.addTarget(self, action: #selector(toggleShift), for: .touchDown)
                row.addArrangedSubview(shift)
            }
            rows.addArrangedSubview(row)
        }
        addBottomRow(tablet: true)
    }

    private func addBottomRow(tablet: Bool = false) {
        let bottom = UIStackView()
        bottom.axis = .horizontal
        bottom.spacing = 6
        let mode = key(symbols ? "ABC" : "123", special: true)
        mode.titleLabel?.font = .systemFont(ofSize: 16)
        mode.addTarget(self, action: #selector(toggleSymbols), for: .touchUpInside)
        let space = key("")
        spaceButton = space
        space.showsMenuAsPrimaryAction = false
        updateLanguageMenu()
        space.accessibilityLabel = L10n.text("Leerzeichen")
        addSpaceBranding(to: space)
        space.addAction(UIAction { [weak self] _ in self?.spacePressed() }, for: .touchUpInside)
        space.accessibilityHint = L10n.text("Gedrückt halten, um die Sprache auszuwählen.")
        let enter = key("", special: true)
        if !tablet { returnButton = enter }
        enter.titleLabel?.font = .systemFont(ofSize: 16)
        enter.accessibilityLabel = returnTitle
        enter.addAction(UIAction { [weak self] _ in self?.insertText("\n") }, for: .touchUpInside)
        bottom.addArrangedSubview(mode)
        // Devices without the system's own switcher need this key to leave the keyboard.
        if needsInputModeSwitchKey {
            let globe = key("", special: true)
            globe.setImage(UIImage(systemName: "globe"), for: .normal)
            globe.accessibilityLabel = L10n.text("Nächste Tastatur")
            globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
            bottom.addArrangedSubview(globe)
            globe.widthAnchor.constraint(equalTo: mode.widthAnchor).isActive = true
        }
        bottom.addArrangedSubview(space)
        insert.removeFromSuperview()
        bottom.addArrangedSubview(insert)
        if let launchHost {
            launchHost.view.removeFromSuperview()
            NSLayoutConstraint.deactivate(launchHost.view.constraints.filter { $0.firstAttribute == .width })
            bottom.addArrangedSubview(launchHost.view)
            launchHost.view.widthAnchor.constraint(equalTo: mode.widthAnchor).isActive = true
        }
        if usesTabletLayout {
            let hide = key("", special: true)
            hide.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
            hide.accessibilityLabel = L10n.text("Tastatur schließen")
            hide.addAction(UIAction { [weak self] _ in self?.dismissKeyboard() }, for: .touchUpInside)
            bottom.addArrangedSubview(hide)
            hide.widthAnchor.constraint(equalTo: mode.widthAnchor).isActive = true
        }
        if !tablet { bottom.addArrangedSubview(enter) }
        mode.widthAnchor.constraint(equalTo: bottom.widthAnchor, multiplier: 0.11).isActive = true
        if !tablet { enter.widthAnchor.constraint(equalTo: bottom.widthAnchor, multiplier: 0.22).isActive = true }
        rows.addArrangedSubview(bottom)
        updateAppearance()
    }

    private func addSpaceBranding(to key: KeyboardKeyButton) {
        // Reuse the waveform and rounded wordmark from the app header.
        // Decoration never receives touches or changes the space key's semantics.
        let tint = UIColor { traits in
            UIColor(white: traits.userInterfaceStyle == .dark ? 0.63 : 0.55, alpha: 1)
        }
        let symbol = UIImageView(
            image: UIImage(
                systemName: "waveform",
                withConfiguration:
                    UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)))
        symbol.tintColor = tint
        symbol.contentMode = .scaleAspectFit
        let name = UILabel()
        name.text = "flype"
        let font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        name.font = font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 14) } ?? font
        name.textColor = tint
        let branding = UIStackView(arrangedSubviews: [symbol, name])
        branding.axis = .horizontal
        branding.alignment = .center
        branding.spacing = 4
        branding.isUserInteractionEnabled = false
        branding.accessibilityElementsHidden = true
        branding.translatesAutoresizingMaskIntoConstraints = false
        key.addSubview(branding)
        NSLayoutConstraint.activate([
            branding.centerXAnchor.constraint(equalTo: key.centerXAnchor),
            branding.centerYAnchor.constraint(equalTo: key.centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant: 14),
            symbol.heightAnchor.constraint(equalToConstant: 14),
            branding.widthAnchor.constraint(lessThanOrEqualTo: key.widthAnchor, constant: -12),
        ])
    }

    private var returnTitle: String {
        switch textDocumentProxy.returnKeyType {
        case .search: L10n.text("Suchen")
        case .send: L10n.text("Senden")
        case .go: L10n.text("Los")
        case .done: L10n.text("Fertig")
        case .next: L10n.text("Weiter")
        default: "↵"
        }
    }

    private func makeRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        row.distribution = .fillEqually
        return row
    }

    private func key(_ title: String, special: Bool = false) -> KeyboardKeyButton {
        let button = KeyboardKeyButton(frame: .zero)
        button.setTitle(title, for: .normal)
        button.normalSurface = special ? KeyboardKeyAppearance.functionSurface : KeyboardKeyAppearance.characterSurface
        button.popupText = !special && title.count == 1 ? title : nil
        button.highlightChanged = { [weak self] button, highlighted in
            guard let self else { return }
            // The gesture shows the preview on touch-down; this handles sliding off and back onto a key.
            if highlighted {
                if self.previewGesture.isDown(on: button) { self.showKeyPreview(for: button) }
            } else if self.previewSource === button {
                self.hideKeyPreview()
            }
        }
        button.addAction(UIAction { _ in UIDevice.current.playInputClick() }, for: .touchDown)
        return button
    }

    private func showKeyPreview(for key: KeyboardKeyButton) {
        guard alternateStrip.isHidden, let text = key.popupText else { return }
        let frame = key.convert(key.bounds, to: view)
        let width = max(52, frame.width + 14)
        keyPreview.text = text
        keyPreview.frame = CGRect(
            x: min(max(2, frame.midX - width / 2), view.bounds.width - width - 2),
            y: max(0, frame.minY - 46), width: width, height: 48)
        previewSource = key
        keyPreview.isHidden = false
        view.bringSubviewToFront(keyPreview)
    }

    private func hideKeyPreview() {
        keyPreview.isHidden = true
        previewSource = nil
    }

    private func capitalizedKey(_ character: String) -> String { character == "ß" ? "ẞ" : character.uppercased() }

    private func type(_ character: String) {
        lastSpaceTap = 0
        insertText(!symbols && uppercase ? capitalizedKey(character) : character)
    }

    private func configureAlternates(on button: KeyboardKeyButton, character: String) {
        guard let values = KeyboardAlternates.values(for: character) else { return }
        button.alternateCharacter = character
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(selectAlternate(_:)))
        gesture.minimumPressDuration = 0.35
        gesture.allowableMovement = 18
        gesture.delaysTouchesBegan = false
        gesture.delaysTouchesEnded = false
        // UIKit cancels the normal key release when the hold begins, so only
        // the selected alternate is inserted, never the base character as well.
        button.addGestureRecognizer(gesture)
        button.accessibilityCustomActions = values.map { value in
            UIAccessibilityCustomAction(name: value) { [weak self] _ in
                self?.type(value)
                return true
            }
        }
    }

    @objc private func selectAlternate(_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view as? KeyboardKeyButton,
            let character = button.alternateCharacter
        else { return }
        switch gesture.state {
        case .began:
            guard let variants = KeyboardAlternates.values(for: character) else { return }
            alternateSource = button
            hideKeyPreview()
            let source = button.convert(button.bounds, to: view)
            let extendsLeft = source.midX > view.bounds.midX
            alternateValues = extendsLeft ? Array(variants.reversed()) + [character] : [character] + variants
            let titles = alternateValues.map { !symbols && uppercase ? capitalizedKey($0) : $0 }
            alternateStrip.present(titles: titles, source: source, bounds: view.bounds, extendsLeft: extendsLeft)
            view.bringSubviewToFront(alternateStrip)
        case .changed:
            guard alternateSource === button else { return }
            alternateStrip.select(at: gesture.location(in: view))
        case .ended:
            guard alternateSource === button else { return }
            alternateStrip.select(at: gesture.location(in: view))
            let value = alternateStrip.selectedIndex.flatMap {
                alternateValues.indices.contains($0) ? alternateValues[$0] : nil
            }
            dismissAlternates()
            if let value { type(value) }
        case .cancelled, .failed:
            if alternateSource === button { dismissAlternates() }
        default: break
        }
    }

    private func dismissAlternates() {
        alternateStrip.isHidden = true
        alternateSource = nil
        alternateValues = []
    }

    private func updateLetterCase() {
        for (button, character) in letterKeys {
            let title = uppercase ? capitalizedKey(character) : character
            button.setTitle(title, for: .normal)
            button.popupText = title
        }
        for shift in shiftButtons { shift.setImage(UIImage(systemName: shiftSymbol), for: .normal) }
    }

    private var shiftSymbol: String { capsLock ? "capslock.fill" : (uppercase ? "shift.fill" : "shift") }

    private func capitalizationMode() -> KeyboardTypingRules.Capitalization {
        switch textDocumentProxy.autocapitalizationType ?? .sentences {
        case .none: return .none
        case .words: return .words
        case .allCharacters: return .allCharacters
        default: return .sentences
        }
    }

    private func synchronizeCapitalization(before: String? = nil) {
        guard isVisible, !capsLock, !symbols else { return }
        let desired = KeyboardTypingRules.shouldUppercase(
            before: before ?? textDocumentProxy.documentContextBeforeInput ?? "", mode: capitalizationMode())
        if uppercase != desired {
            uppercase = desired
            updateLetterCase()
        }
    }

    @objc private func toggleShift() {
        if symbols {
            secondarySymbols.toggle()
            buildKeys()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastShiftTap < 0.35 {
            uppercase = true
            capsLock = true
            lastShiftTap = 0
        } else {
            uppercase.toggle()
            capsLock = false
            lastShiftTap = now
        }
        updateLetterCase()
    }

    @objc private func toggleSymbols() {
        symbols.toggle()
        secondarySymbols = false
        buildKeys()
    }

    private func spacePressed() {
        let now = ProcessInfo.processInfo.systemUptime
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        if now - lastSpaceTap < 0.35, KeyboardTypingRules.canReplaceDoubleSpace(before: before) {
            textDocumentProxy.deleteBackward()
            insertText(". ")
            lastSpaceTap = 0
        } else {
            insertText(" ")
            lastSpaceTap = now
        }
        if symbols {
            symbols = false
            secondarySymbols = false
            buildKeys()
        }
    }

    private func configureRepeatedDelete(on button: UIButton) {
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(repeatDelete(_:)))
        hold.delaysTouchesBegan = false
        hold.delaysTouchesEnded = false
        button.addGestureRecognizer(hold)
    }

    @objc private func repeatDelete(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            deleteTimer?.invalidate()
            deleteCharacter()
            deleteTimer = Timer.scheduledTimer(
                timeInterval: 0.09, target: self, selector: #selector(deleteCharacter), userInfo: nil, repeats: true)
        } else if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            deleteTimer?.invalidate()
            deleteTimer = nil
        }
    }

    private func insertText(_ text: String) {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        textDocumentProxy.insertText(text)
        synchronizeCapitalization(before: before + text)
        scheduleSuggestions()
    }

    @objc private func deleteCharacter() {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        textDocumentProxy.deleteBackward()
        synchronizeCapitalization(before: String(before.dropLast()))
        scheduleSuggestions()
    }

    private var currentDocumentID: UUID? {
        guard isVisible, let proxy = textDocumentProxy as? NSObject else { return nil }
        return DocumentIdentifier.read(from: proxy)
    }

    private func cancelSuggestions() {
        suggestionTask?.cancel()
        suggestionPending = false
    }

    private func scheduleSuggestions() {
        guard !suggestionTouchActive else { return }
        guard isVisible else {
            cancelSuggestions()
            renderSuggestions([])
            return
        }
        let excluded =
            textDocumentProxy.keyboardType == .emailAddress || textDocumentProxy.keyboardType == .URL
            || textDocumentProxy.spellCheckingType == .no
        suggestionsExcluded = excluded
        updateSuggestionBarVisibility()
        cancelSuggestions()
        guard !excluded, voiceSession?.phase != .recording else { return }
        // UITextChecker is main-actor isolated. Let a rapid typing burst finish
        // before doing spelling work on the same thread that delivers touches.
        suggestionPending = true
        suggestionTask = Task { [weak self] in
            defer { if !Task.isCancelled { self?.suggestionPending = false } }
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard let self, !Task.isCancelled, !self.suggestionTouchActive,
                let documentID = self.currentDocumentID
            else { return }
            guard self.textDocumentProxy.selectedText?.isEmpty != false else {
                self.renderSuggestions([])
                return
            }
            // Read after the host has applied our keystroke, instead of caching stale proxy text.
            let context = WordSuggestionContext(
                before: self.textDocumentProxy.documentContextBeforeInput ?? "",
                after: self.textDocumentProxy.documentContextAfterInput ?? "")
            guard context != self.lastSuggestionContext || documentID != self.suggestionDocumentID else { return }
            let language = self.wordSuggestions.selectedLanguage
            let fullAccess = self.hasFullAccess
            let candidates = await self.wordSuggestions.candidates(for: context)
            // The user can type, move the cursor or switch fields while the worker runs.
            guard !Task.isCancelled, self.isVisible, !self.suggestionTouchActive,
                self.voiceSession?.phase != .recording, !self.suggestionsExcluded,
                self.currentDocumentID == documentID, self.wordSuggestions.selectedLanguage == language,
                self.hasFullAccess == fullAccess, self.textDocumentProxy.selectedText?.isEmpty != false,
                context
                    == WordSuggestionContext(
                        before: self.textDocumentProxy.documentContextBeforeInput ?? "",
                        after: self.textDocumentProxy.documentContextAfterInput ?? "")
            else { return }
            self.lastSuggestionContext = context
            self.suggestionDocumentID = documentID
            self.renderSuggestions(candidates, context: context, documentID: documentID)
        }
    }

    private func beginSuggestionSelection(at index: Int) {
        cancelSuggestions()
        suggestionTouchActive = true
        activeSuggestion = nil
        recordSuggestionInteraction("touch-received", index: index)
        guard displayedSuggestions.indices.contains(index), let previous = displayedSuggestionContext,
            let documentID = currentDocumentID, documentID == displayedSuggestionDocumentID,
            textDocumentProxy.selectedText?.isEmpty != false
        else {
            recordSuggestionInteraction("document-not-ready", index: index)
            return
        }
        let context = WordSuggestionContext(
            before: textDocumentProxy.documentContextBeforeInput ?? "",
            after: textDocumentProxy.documentContextAfterInput ?? "")
        // Permit a few newly typed letters in the same word, never another field or word.
        guard context.after == previous.after,
            String(context.before.dropLast(context.prefix.count))
                == String(previous.before.dropLast(previous.prefix.count))
        else {
            recordSuggestionInteraction("word-context-changed", index: index)
            lastSuggestionContext = nil
            scheduleSuggestions()
            return
        }
        cancelSuggestions()
        activeSuggestion = SuggestionSelection(
            word: displayedSuggestions[index], context: context, documentID: documentID)
        suggestionTouchActive = true
        recordSuggestionInteraction("candidate-held", index: index)
    }

    private func cancelSuggestionSelection() {
        activeSuggestion = nil
        suggestionTouchActive = false
        lastSuggestionContext = nil
        scheduleSuggestions()
    }

    private func renderSuggestions(_ words: [String], context: WordSuggestionContext? = nil, documentID: UUID? = nil) {
        guard !suggestionTouchActive else { return }
        displayedSuggestionContext = context
        displayedSuggestionDocumentID = documentID
        displayedSuggestions = words
        updateSuggestionBarVisibility()
        suggestionBar.update(words: words)
    }

    private func updateSuggestionBarVisibility() {
        let hide = suggestionsExcluded || (displayedSuggestions.isEmpty && !symbols)
        if suggestionBar.isHidden != hide {
            suggestionBar.isHidden = hide
            updateRecordingView()
        }
    }

    private func acceptSuggestion(at index: Int) {
        // VoiceOver activation.
        if activeSuggestion == nil && !suggestionTouchActive { beginSuggestionSelection(at: index) }
        defer { cancelSuggestionSelection() }
        guard let selection = activeSuggestion,
            currentDocumentID == selection.documentID,
            (textDocumentProxy.documentContextBeforeInput ?? "") == selection.context.before,
            (textDocumentProxy.documentContextAfterInput ?? "") == selection.context.after,
            textDocumentProxy.selectedText?.isEmpty != false
        else {
            recordSuggestionInteraction("selection-changed-before-release", index: index)
            return
        }
        let context = selection.context
        if !context.suffix.isEmpty { textDocumentProxy.adjustTextPosition(byCharacterOffset: context.suffix.count) }
        for _ in 0..<context.replacementCount { textDocumentProxy.deleteBackward() }
        let following = context.after.dropFirst(context.suffix.count).first
        let needsSpace = following.map { !$0.isWhitespace && !".,;:!?)]}»”".contains($0) } ?? true
        textDocumentProxy.insertText(selection.word + (needsSpace ? " " : ""))
        if following == " " { textDocumentProxy.adjustTextPosition(byCharacterOffset: 1) }
        recordSuggestionInteraction("inserted", index: index)
        synchronizeCapitalization(before: String(context.before.dropLast(context.prefix.count)) + selection.word + " ")
    }

    private func recordSuggestionInteraction(_ stage: String, index: Int) {
        #if DEBUG
            // Only control status and geometry; never input text or suggested words.
            let status: [String: String] = [
                "stage": stage, "index": String(index),
                "width": String(Double(suggestionBar.bounds.width)),
                "height": String(Double(suggestionBar.bounds.height)),
            ]
            if let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
                let data = try? JSONEncoder().encode(status)
            {
                try? data.write(to: cache.appendingPathComponent("suggestion-interaction.json"), options: .atomic)
            }
        #endif
    }

    /// Shared files are read away from the thread that delivers touches.
    private struct RefreshSnapshot: Sendable {
        var voiceSession: VoiceSessionState?
        var pending: DictationResult?
        var failure: (any Error)?
    }

    nonisolated private static func loadRefreshSnapshot(markKeyboardSeen: Bool) -> RefreshSnapshot {
        var snapshot = RefreshSnapshot()
        do {
            let sessionStore = try VoiceSessionStore.shared()
            if markKeyboardSeen { try sessionStore.keyboardSeen() }
            snapshot.voiceSession = try sessionStore.state()
            snapshot.pending = try ResultStore.shared().pending()
        } catch {
            snapshot.failure = error
        }
        return snapshot
    }

    private func loadRefresh() {
        guard !refreshLoading else {
            refreshAgain = true
            return
        }
        refreshLoading = true
        // The app treats the keyboard as seen for 3 seconds.
        let now = ProcessInfo.processInfo.systemUptime
        let markKeyboardSeen = isVisible && now - lastKeyboardSeenWrite >= 1.5
        if markKeyboardSeen { lastKeyboardSeenWrite = now }
        Task { [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                Self.loadRefreshSnapshot(markKeyboardSeen: markKeyboardSeen)
            }.value
            guard let self else { return }
            #if DEBUG
                KeyboardTouchDiagnostics.shared.record(
                    "refreshLoad", milliseconds: (ProcessInfo.processInfo.systemUptime - now) * 1000)
            #endif
            refreshLoading = false
            if snapshot.failure != nil { lastKeyboardSeenWrite = 0 }
            #if DEBUG
                KeyboardTouchDiagnostics.shared.measure("refresh") { self.applyRefresh(snapshot) }
            #else
                applyRefresh(snapshot)
            #endif
            if refreshAgain {
                refreshAgain = false
                refresh()
            }
        }
    }

    @objc private func refresh() {
        let selected = hasFullAccess ? FlypeLanguage.recognition() : language
        if selected != language {
            language = selected
            primaryLanguage = selected.localeIdentifier
            wordSuggestions.selectedLanguage = selected
            lastSuggestionContext = nil
            buildKeys()
        }
        updateLanguageMenu()
        guard !isInserting else { return }
        wordSuggestions.setPersonalDictionaryEnabled(hasFullAccess)
        guard hasFullAccess else {
            pending = nil
            voiceSession = nil
            startRequest = nil
            updateMicrophone()
            updateAppearance()
            return
        }
        loadRefresh()
    }

    private func applyRefresh(_ snapshot: RefreshSnapshot) {
        // Access or an insertion can have changed while the files were read.
        guard !isInserting, hasFullAccess else { return }
        do {
            if let failure = snapshot.failure { throw failure }
            voiceSession = snapshot.voiceSession
            if let pendingStartID,
                voiceSession?.dictationID == pendingStartID
                    || commandSentAt.map({ Date().timeIntervalSince($0) >= 5 }) == true
            {
                self.pendingStartID = nil
                startRequest = nil
            }
            try refreshLaunchRequest()
            updateMicrophone()
            pending = snapshot.pending
            lastError = nil

        } catch {
            pending = nil
            lastError = "Übergabe nicht verfügbar. Öffne Flype erneut."
            // A result/request-file failure does not invalidate a separately verified live heartbeat.
            voiceSession = voiceSession.flatMap { $0.isAlive() ? $0 : nil }
            updateMicrophone()
            #if DEBUG
                saveDiagnostic(store: nil, error: error as NSError)
            #endif
        }
        if isVisible, let documentID = currentDocumentID {
            let activeRequest =
                (voiceSession?.phase == .recording || voiceSession?.phase == .processing
                    || voiceSession?.phase == .preparing) ? voiceSession?.dictationID : nil
            let previous = insertionPermit
            insertionPermit?.observe(
                documentID: documentID, activeRequestID: activeRequest, completedRequestID: pending?.keyboardRequestID)
            if let insertionPermit, insertionPermit != previous {
                try? KeyboardInsertionPermitStore.shared().save(insertionPermit)
            }
        }
        #if DEBUG
            if lastError == nil { saveDiagnostic(store: try? ResultStore.shared(), error: nil) }
        #endif
        if isVisible, let pending, canAutomaticallyInsert(pending) {
            insertResult()
        }
        updateAppearance()
    }

    private func refreshLaunchRequest() throws {
        guard pendingStartID == nil else { return }
        guard let documentID = currentDocumentID else {
            startRequest = nil
            updateMicrophone()
            return
        }
        let now = Date()
        if let startRequest, startRequest.targetDocumentID == documentID,
            startRequest.returnApplicationID == resolvedHostID, startRequest.isValid(at: now),
            startRequest.expiresAt.timeIntervalSince(now) > 10
        {
            return
        }
        let request = KeyboardStartRequest(now: now, targetDocumentID: documentID, returnApplicationID: resolvedHostID)
        try KeyboardStartStore.shared().issue(request)
        startRequest = request
        updateMicrophone()
    }

    private func updateMicrophone() {
        // The visible Link and its one-use capability must remain the same snapshot.
        let request = startRequest
        // Rendering depends only on these; the closures read everything else when they run.
        let state = RenderedMicrophone(url: request?.url, phase: voiceSession?.phase)
        guard state != renderedMicrophone else { return }
        renderedMicrophone = state
        launchHost?.rootView = DictationLaunchLink(
            url: request?.url, session: voiceSession,
            action: { [weak self] in
                self?.controlSession()
            },
            willOpen: { [weak self] requestedURL in
                guard let self, let request, request.url == requestedURL, request.isValid(at: Date()),
                    self.hasFullAccess, self.pendingStartID == nil, let document = self.currentDocumentID
                else { return false }
                do {
                    // A refresh may have issued another request since this Link was rendered.
                    // Publish the exact tapped request immediately before opening the app,
                    // then freeze refreshes until the app acknowledges it or the launch times out.
                    try KeyboardStartStore.shared().issue(request)
                    self.saveFieldContext(requestID: request.id)
                    self.startRequest = request
                    self.pendingStartID = request.id
                    self.commandSentAt = Date()
                    self.setInsertionPermit(
                        KeyboardInsertionPermit(requestID: request.id, documentID: document, awaitingReturn: true))
                    return true
                } catch {
                    return false
                }
            })
    }

    /// Dictation still works without it, so a failure here must not stop the start.
    private func saveFieldContext(requestID: UUID) {
        try? DictationFieldContextStore.shared().save(
            DictationFieldContext(requestID: requestID, text: textDocumentProxy.documentContextBeforeInput ?? ""))
    }

    private func controlSession() {
        guard hasFullAccess, let session = voiceSession, session.isAlive(),
            commandSentAt.map({ Date().timeIntervalSince($0) >= 0.8 }) ?? true
        else { return }
        do {
            let command: VoiceSessionCommand
            if session.phase == .recording, let requestID = session.dictationID {
                command = VoiceSessionCommand(sessionID: session.id, requestID: requestID, action: .stop)
            } else if session.phase == .ready, pendingStartID == nil {
                startRequest = nil
                try refreshLaunchRequest()
                guard let request = startRequest else { return }
                // Every background start still consumes a fresh one-use keyboard capability.
                try KeyboardStartStore.shared().issue(request)
                saveFieldContext(requestID: request.id)
                command = VoiceSessionCommand(sessionID: session.id, requestID: request.id, action: .start)
            } else {
                return
            }
            try VoiceSessionStore.shared().send(command)
            commandSentAt = Date()
            // A consumed request is never reused for another recording.
            if command.action == .start {
                pendingStartID = command.requestID
                if let document = currentDocumentID {
                    setInsertionPermit(
                        KeyboardInsertionPermit(
                            requestID: command.requestID, documentID: document, awaitingReturn: false))
                }
            }
        } catch {
            voiceSession = nil
            pendingStartID = nil
            commandSentAt = nil
            updateMicrophone()
        }
    }

    #if DEBUG
        private var lastDiagnostic: String?
        private func saveDiagnostic(store: ResultStore?, error: NSError?) {
            let directory = store?.diagnosticDirectory.path ?? "unavailable"
            let hasRequest = pending?.keyboardRequestID != nil
            let state =
                "\(directory)|\(pending != nil)|\(isVisible)|\(hasRequest)|\(insertionPermit != nil)|\(insertionPermit?.awaitingReturn ?? false)|\(insertionPermit?.invalidated ?? false)|\(error?.domain ?? "")|\(error?.code ?? 0)"
            guard state != lastDiagnostic else { return }
            lastDiagnostic = state
            let snapshot: [String: Any] = [
                "directory": directory, "hasFullAccess": hasFullAccess,
                "timestamp": Date().timeIntervalSince1970, "visible": isVisible,
                "hasKeyboardRequest": hasRequest,
                "eligibleForAutoInsert": pending?.canAutoInsert() ?? false,
                "hasInsertionPermit": insertionPermit != nil,
                "awaitingReturn": insertionPermit?.awaitingReturn ?? false,
                "permitInvalidated": insertionPermit?.invalidated ?? false,
                "permitAllowsInsertion": pending.map { canAutomaticallyInsert($0) } ?? false,
                "resultAge": pending.map { Date().timeIntervalSince($0.createdAt) } ?? -1,
                "hasPendingResult": pending != nil, "errorDomain": error?.domain ?? "", "errorCode": error?.code ?? 0,
            ]
            // Diagnostics stay in this extension's cache, with no dictated or typed text.
            if let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
                let data = try? PropertyListSerialization.data(fromPropertyList: snapshot, format: .xml, options: 0)
            {
                try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                try? data.write(to: cache.appendingPathComponent("handoff-diagnostic.plist"), options: .atomic)
                if pending != nil {
                    try? data.write(
                        to: cache.appendingPathComponent("handoff-pending-diagnostic.plist"), options: .atomic)
                }
            }
        }
    #endif

    private func updateAppearance() {
        guard isViewLoaded else { return }
        // A periodic refresh must not keep postponing a pause that is already running.
        if !suggestionPending { scheduleSuggestions() }
        updateRecordingView()
        let title = returnTitle
        if returnButton !== renderedReturnButton || title != renderedReturnTitle {
            renderedReturnButton = returnButton
            renderedReturnTitle = title
            let hasReturnSymbol = title == "↵"
            returnButton?.setTitle(hasReturnSymbol ? nil : title, for: .normal)
            returnButton?.setImage(
                hasReturnSymbol
                    ? UIImage(
                        systemName: "return",
                        withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)) : nil,
                for: .normal)
            returnButton?.accessibilityLabel = title
        }
        let needsManualInsertion =
            hasFullAccess && pending != nil && !(pending.map { canAutomaticallyInsert($0) } ?? false)
        insert.isHidden = !needsManualInsertion
        insert.isEnabled = needsManualInsertion
        launchHost?.view.isHidden = false
        launchHost?.view.accessibilityHint =
            L10n.text(
                lastError
                    ?? (hasFullAccess
                        ? "Transkription starten" : "Vollen Zugriff in den Tastatureinstellungen aktivieren"))

    }

    private func setInsertionPermit(_ permit: KeyboardInsertionPermit) {
        insertionPermit = permit
        try? KeyboardInsertionPermitStore.shared().save(permit)
    }

    private func restoreInsertionPermit() {
        guard insertionPermit == nil else { return }
        insertionPermit = try? KeyboardInsertionPermitStore.shared().load()
    }

    private func canAutomaticallyInsert(_ result: DictationResult) -> Bool {
        result.canAutoInsert()
            && (insertionPermit?.allows(requestID: result.keyboardRequestID, documentID: currentDocumentID) ?? false)
    }

    @objc private func insertResult() {
        guard hasFullAccess, !isInserting, let pending else { return }
        isInserting = true
        defer { isInserting = false }
        do {
            guard let claimed = try ResultStore.shared().claim(id: pending.id) else {
                self.pending = nil
                updateAppearance()
                return
            }
            self.pending = nil
            if let requestID = claimed.keyboardRequestID {
                try? KeyboardInsertionPermitStore.shared().clear(requestID: requestID)
            }
            insertionPermit = nil
            let before = textDocumentProxy.documentContextBeforeInput
            insertText(DictationFieldContext.separator(before: claimed.text, after: before) + claimed.text + " ")
            updateAppearance()
        } catch {
            lastError = "Einfügen nicht möglich. Die Transkription bleibt in Flype."
            updateAppearance()
        }
    }
}
