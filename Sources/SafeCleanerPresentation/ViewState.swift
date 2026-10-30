import Foundation
#if SWIFT_PACKAGE
import SafeCleanerCore
#endif

public enum Destination: String, CaseIterable, Identifiable, Sendable {
    case overview = "Overview", review = "Review & clean", assistant = "Claude review", projects = "Projects", history = "Activity", settings = "Settings"
    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .review: return "sparkles"
        case .assistant: return "sparkle.magnifyingglass"
        case .projects: return "folder"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "slider.horizontal.3"
        }
    }
}

public enum WorkspaceAction {
    case navigate(Destination), scan, cancelScan, review(CleanCategory?)
    case queryChanged(String), categoryChanged(CleanCategory?)
    case toggleCandidate(String), toggleSelectAll, clearSelection, excludeCandidate(String), revealCandidate(String)
    case setProjectProtection(String, Bool), dismissResult, quitApp(String), selectRemaining, stopCleanup
    case addProjectFolder, removeProjectFolder(String), removeExclusion(String), revealHistory(UUID)
    case addDuplicateFolder, removeDuplicateFolder(String)
    case openConfirmation, dismissConfirmation, acknowledge(Bool), confirmCleanup, dismissMessage
    case resetHistory, openFullDiskAccessSettings, selectStaleBuildOutput
    case claudeKeyChanged(String), saveClaudeKey, removeClaudeKey, claudeModelChanged(ClaudeModel)
    case analyzeWithClaude, cancelClaude, reviewAIGroup(String), clearAIGroupFilter, verifyClaudeKey
}

/// How the saved key stands, for the status indicator. Verified means Anthropic accepted it this session.
public enum ClaudeKeyTone: Sendable, Equatable { case missing, untested, checking, verified, failed }

public struct AIAdviceRowState: Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let disposition: String
    public let reason: String
    public let caution: String
}

public struct CategorySummary: Identifiable {
    public var id: CleanCategory { category }
    public let category: CleanCategory
    public let title: String
    public let detail: String
    public let size: String
    public let count: String
    public let fraction: Double
}

public struct CandidateRowState: Identifiable {
    public let id: String
    public let title: String
    public let path: String
    public let fullPath: String
    public let size: String
    public let category: CleanCategory
    public let badge: String
    public let reason: String
    public let consequence: String
    public let metadata: String
    public let isSelected: Bool
    public let canSelect: Bool
    public let canReveal: Bool
    public let canExclude: Bool
}

public enum SelectAllState: Sendable { case none, some, all }

public struct CleanupProgressState: Equatable {
    public let fraction: Double
    public let countLabel: String
    public let bytesLabel: String
    public let current: String
    public let currentDetail: String
    public let isStopping: Bool
    public let canStop: Bool
}

/// A project found by the last scan, or one the user protected (protected projects are not
/// scanned, so they would otherwise vanish from the list the moment they are protected).
public struct ProjectRowState: Identifiable {
    public let id: String
    public let title: String
    public let path: String
    public let detail: String
    public let isProtected: Bool
    /// "Stale", "Active" or "Unknown", from local dates only.
    public let badge: String
    /// "Edited 90 days ago · Committed 95 days ago · Built 90 days ago", or what is known.
    public let activity: String
    public let isStale: Bool
}

public struct LocationRowState: Identifiable {
    public let id: String
    public let title: String
    public let path: String
}

public struct HistoryRowState: Identifiable {
    public let id: UUID
    public let title: String
    public let path: String
    public let date: String
    public let result: String
    public let failed: Bool
    public let canReveal: Bool
}

public struct WorkspaceViewState {
    public internal(set) var version = ""
    public internal(set) var destination: Destination = .overview
    public internal(set) var isPreview = false
    public internal(set) var isBusy = true
    public internal(set) var isScanning = false
    public internal(set) var isCleaning = false
    public internal(set) var progress = "Preparing your workspace…"
    public internal(set) var hasScanned = false
    public internal(set) var canScan = false
    public internal(set) var canEditSettings = false
    public internal(set) var canReviewSelection = false
    public internal(set) var message: String?
    public internal(set) var query = ""
    public internal(set) var categoryFilter: CleanCategory?
    public internal(set) var diskFraction = 0.0
    public internal(set) var diskPercent = "—"
    public internal(set) var freeSpace = "—"
    public internal(set) var usedSpace = "—"
    public internal(set) var foundSize = "Let’s find out."
    public internal(set) var foundValue: Double = 0
    public internal(set) var foundCaption = "Scan supported caches and project folders. You review every item."
    public internal(set) var candidateCount = "0"
    public internal(set) var scanDate = "Awaiting first scan"
    public internal(set) var selectedSize = "Zero KB"
    public internal(set) var selectedValue: Double = 0
    public internal(set) var selectionCaption = "No items selected"
    public internal(set) var categories: [CategorySummary] = []
    public internal(set) var candidates: [CandidateRowState] = []
    public internal(set) var issues: [ScanIssue] = []
    public internal(set) var selectAll: SelectAllState = .none
    public internal(set) var canSelectAll = false
    public internal(set) var selectAllLabel = "Select all"
    public internal(set) var selectAllAccessibilityValue = ""
    /// What the app is busy with, shown on every screen. Controls are disabled while busy,
    /// and a disabled control with no visible reason reads as a broken one.
    public internal(set) var busyStatus: String?
    /// Saving an API key does not interact with a scan or cleanup, so it is not locked by them.
    public internal(set) var canEditClaudeKey = false
    public internal(set) var projectsEmptyMessage: String?
    /// "3 stale projects hold 18 GB of build output", or nil when nothing is stale and unprotected.
    public internal(set) var staleSummary: String?
    public internal(set) var canSelectStaleBuildOutput = false
    /// Shown as a sheet, not a banner: a cleanup that left anything behind must not be missable.
    public internal(set) var cleanupResult: CleanupResultState?
    public internal(set) var cleanupProgress: CleanupProgressState?
    /// One sheet carries the whole cleanup: confirm, then progress, then the result. Swapping
    /// separate sheets in a single update is unreliable on macOS, and the user should never be
    /// left looking at a spinner with no sense of when it is done.
    public internal(set) var showCleanupSheet = false
    public internal(set) var confirmationHint: String?
    public internal(set) var projects: [ProjectRowState] = []
    public internal(set) var projectRoots: [LocationRowState] = []
    public internal(set) var duplicateRoots: [LocationRowState] = []
    public internal(set) var exclusions: [LocationRowState] = []
    public internal(set) var history: [HistoryRowState] = []
    /// The stored history could not be read, so cleanup is paused until it is reset.
    public internal(set) var historyNeedsReset = false
    /// Locations the scanner cannot read. Empty means nothing is being hidden.
    public internal(set) var blockedAreas: [String] = []
    /// True when the block needs Full Disk Access, which macOS will not prompt for.
    public internal(set) var needsFullDiskAccess = false
    public internal(set) var noProjectRootsYet = false
    public internal(set) var showConfirmation = false
    public internal(set) var confirmationTitle = ""
    public internal(set) var confirmationDetail = ""
    public internal(set) var confirmButtonTitle = "Move to Trash"
    /// Present when the selection includes tool-managed items, which are removed permanently.
    public internal(set) var confirmationToolNote: String?
    public internal(set) var confirmationItems: [CandidateRowState] = []
    public internal(set) var confirmationAcknowledged = false
    public internal(set) var canConfirmCleanup = false
    public internal(set) var claudeKeyDraft = ""
    public internal(set) var hasClaudeKey = false
    public internal(set) var claudeModel: ClaudeModel = .haiku
    public internal(set) var isAnalyzing = false
    public internal(set) var canAnalyze = false
    public internal(set) var canSaveClaudeKey = false
    public internal(set) var claudeKeyStatus = "No API key saved"
    public internal(set) var claudeKeyDetail: String?
    public internal(set) var claudeKeyTone: ClaudeKeyTone = .missing
    public internal(set) var canVerifyClaudeKey = false
    public internal(set) var isVerifyingClaudeKey = false
    /// Why “Send summary to Claude” is disabled, when it is.
    public internal(set) var aiSendHint: String?
    public internal(set) var aiConsent = "Sends only grouped types, counts and sizes to Anthropic when you click “Send summary to Claude”. No filenames, paths or file contents. Uses your API credits."
    public internal(set) var aiPayload = "Run a scan first."
    public internal(set) var aiScope = ""
    public internal(set) var aiSummary: String?
    public internal(set) var aiUsage: String?
    public internal(set) var aiAdvice: [AIAdviceRowState] = []
    public internal(set) var aiGroupFilterTitle: String?
    public init() {}
}

enum Operation { case loading, idle, scanning, cleaning, choosingFolder, analyzing }

/// Session-only. A check is a point-in-time fact, so it is never persisted and restarts as untested.
enum ClaudeKeyCheckState: Equatable {
    case untested, checking
    case verified(model: String, at: Date)
    case failed(reason: String, at: Date)
}

struct WorkspaceSession {
    var destination: Destination = .overview
    var operation: Operation = .loading
    var candidates: [Candidate] = []
    var projects: [URL] = []
    var activity: [ProjectActivity] = []
    /// Projects unprotected since the last scan: listed, but their build folders are not known yet.
    var rescanNeeded: [URL] = []
    /// Separate from `operation` so a key can be saved during a scan without replacing it.
    var savingKey = false
    var outcome: CleanupOutcome?
    var cleanupProgress: CleanupProgress?
    var stoppingCleanup = false
    /// The project roots the last completed scan covered, so a newly added root is not
    /// described as "no projects found" before it was ever scanned.
    var scannedRoots: [URL] = []
    var selected = Set<String>()
    var issues: [ScanIssue] = []
    var settings = WorkspaceSettings()
    var records: [CleanupRecord] = []
    var historyAvailable = true
    var access = DiskAccessReport(blocked: [])
    var disk = DiskCapacity.unavailable
    var lastScan: Date?
    var progress = "Preparing your workspace…"
    var message: String?
    var query = ""
    var category: CleanCategory?
    var showConfirmation = false
    var acknowledged = false
    var claudeKeyDraft = ""
    var hasClaudeKey = false
    var claudeModel: ClaudeModel = .haiku
    var keyCheck: ClaudeKeyCheckState = .untested
    var aiPacket: AIReviewPacket?
    var aiAnalysis: AIAnalysis?
    var aiGroupFilter: AIReviewGroup?
}
