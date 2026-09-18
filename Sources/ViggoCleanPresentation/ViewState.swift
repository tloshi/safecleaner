import Foundation
#if SWIFT_PACKAGE
import ViggoCleanCore
#endif

public enum Destination: String, CaseIterable, Identifiable, Sendable {
    case overview = "Overview", review = "Review & clean", projects = "Projects", history = "Activity", settings = "Settings"
    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .review: return "sparkles"
        case .projects: return "folder"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "slider.horizontal.3"
        }
    }
}

public enum WorkspaceAction {
    case navigate(Destination), scan, cancelScan, review(CleanCategory?)
    case queryChanged(String), categoryChanged(CleanCategory?)
    case toggleCandidate(String), clearSelection, excludeCandidate(String), revealCandidate(String)
    case addProjectFolder, removeProjectFolder(String), removeExclusion(String), revealHistory(UUID)
    case openConfirmation, dismissConfirmation, acknowledge(Bool), confirmCleanup, dismissMessage
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
    public internal(set) var projectRoots: [LocationRowState] = []
    public internal(set) var exclusions: [LocationRowState] = []
    public internal(set) var history: [HistoryRowState] = []
    public internal(set) var showConfirmation = false
    public internal(set) var confirmationItems: [CandidateRowState] = []
    public internal(set) var confirmationAcknowledged = false
    public internal(set) var canConfirmCleanup = false
    public init() {}
}

enum Operation { case loading, idle, scanning, cleaning, choosingFolder }

struct WorkspaceSession {
    var destination: Destination = .overview
    var operation: Operation = .loading
    var candidates: [Candidate] = []
    var selected = Set<String>()
    var issues: [ScanIssue] = []
    var settings = WorkspaceSettings()
    var records: [CleanupRecord] = []
    var disk = DiskCapacity.unavailable
    var lastScan: Date?
    var progress = "Preparing your workspace…"
    var message: String?
    var query = ""
    var category: CleanCategory?
    var showConfirmation = false
    var acknowledged = false
}
