import Foundation

@MainActor
final class RemoteFileBrowserModel: ObservableObject {
    @Published private(set) var listing: RemoteDirectoryListing?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var pathInput = ""

    private let browser: any RemoteDirectoryBrowsing
    private var configuration: ServerConfiguration?
    private var loadTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var backStack: [String] = []
    private var forwardStack: [String] = []

    init(
        configuration: ServerConfiguration? = nil,
        browser: any RemoteDirectoryBrowsing = RemoteFileBrowser()
    ) {
        self.configuration = configuration
        self.browser = browser
    }

    deinit {
        loadTask?.cancel()
    }

    var canGoBack: Bool {
        !backStack.isEmpty
    }

    var canGoForward: Bool {
        !forwardStack.isEmpty
    }

    func updateConfiguration(_ configuration: ServerConfiguration?) {
        guard self.configuration != configuration else { return }
        cancel()
        self.configuration = configuration
        listing = nil
        pathInput = ""
        errorMessage = nil
        backStack.removeAll()
        forwardStack.removeAll()
    }

    func loadHomeIfNeeded() {
        guard listing == nil, !isLoading else { return }
        load(path: nil, history: .reset)
    }

    func navigateFromInput() {
        let trimmed = pathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            load(path: nil, history: .pushCurrent)
            return
        }
        guard Self.isValidPath(trimmed) else {
            errorMessage = RemoteFileBrowserError.invalidPath.localizedDescription
            return
        }
        load(path: trimmed, history: .pushCurrent)
    }

    func navigate(to path: String) {
        guard Self.isValidPath(path) else {
            errorMessage = RemoteFileBrowserError.invalidPath.localizedDescription
            return
        }
        load(path: path, history: .pushCurrent)
    }

    func goToParent() {
        guard let parent = listing?.parentPath else { return }
        load(path: parent, history: .pushCurrent)
    }

    func goBack() {
        guard let target = backStack.popLast() else { return }
        if let current = listing?.path {
            forwardStack.append(current)
        }
        load(path: target, history: .preserve)
    }

    func goForward() {
        guard let target = forwardStack.popLast() else { return }
        if let current = listing?.path {
            backStack.append(current)
        }
        load(path: target, history: .preserve)
    }

    func refresh() {
        load(path: listing?.path, history: .preserve)
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        activeRequestID = nil
        isLoading = false
    }

    private func load(path: String?, history: HistoryAction) {
        guard let configuration, configuration.isValid else {
            errorMessage = RemoteFileBrowserError.invalidConfiguration.localizedDescription
            return
        }

        let previousPath = listing?.path
        loadTask?.cancel()
        let requestID = UUID()
        activeRequestID = requestID
        isLoading = true
        errorMessage = nil

        loadTask = Task { [weak self, browser] in
            do {
                let result = try await browser.listDirectory(
                    configuration: configuration,
                    path: path,
                    timeout: .seconds(8)
                )
                guard let self, self.activeRequestID == requestID, !Task.isCancelled else { return }

                switch history {
                case .reset:
                    self.backStack.removeAll()
                    self.forwardStack.removeAll()
                case .pushCurrent:
                    if let previousPath, previousPath != result.path {
                        self.backStack.append(previousPath)
                        if self.backStack.count > 50 {
                            self.backStack.removeFirst(self.backStack.count - 50)
                        }
                    }
                    self.forwardStack.removeAll()
                case .preserve:
                    break
                }

                self.listing = result
                self.pathInput = result.path
                self.isLoading = false
                self.activeRequestID = nil
                self.loadTask = nil
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.activeRequestID == requestID, !Task.isCancelled else { return }
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.isLoading = false
                self.activeRequestID = nil
                self.loadTask = nil
            }
        }
    }

    private static func isValidPath(_ value: String) -> Bool {
        value.hasPrefix("/")
            && !value.contains("\0")
            && !value.contains("\n")
            && !value.contains("\r")
            && value.utf8.count <= 4_096
    }

    private enum HistoryAction {
        case reset
        case pushCurrent
        case preserve
    }
}
