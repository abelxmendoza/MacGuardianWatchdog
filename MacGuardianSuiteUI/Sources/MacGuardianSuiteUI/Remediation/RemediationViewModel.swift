import Foundation
import Combine

@MainActor
class RemediationViewModel: ObservableObject {
    @Published var actions: [RemediationAction] = []
    @Published var results: [RemediationResult] = []
    @Published var loading = false
    @Published var applying = false
    @Published var errorMessage: String?
    @Published var selectedAction: RemediationAction?
    @Published var showConfirmation = false
    
    func load(repositoryPath: String) async {
        loading = true
        errorMessage = nil

        let loadedActions = await RemediationScriptService.shared.previewActions(repositoryPath: repositoryPath)
        actions = loadedActions
        loading = false

        if actions.isEmpty && errorMessage == nil {
            errorMessage = "No remediation actions found. The script may need to be run from Terminal."
        }
    }

    func apply(_ action: RemediationAction, repositoryPath: String, dryRun: Bool = false) async -> Bool {
        applying = true
        errorMessage = nil

        let (success, message) = await RemediationScriptService.shared.applyFix(action: action, repositoryPath: repositoryPath, dryRun: dryRun)
        
        let result = RemediationResult(
            action: action,
            success: success,
            message: message
        )
        
        results.insert(result, at: 0) // Add to beginning
        
        if !success {
            errorMessage = message
        }
        
        applying = false
        return success
    }
    
    func requestApply(_ action: RemediationAction) {
        selectedAction = action
        showConfirmation = true
    }
    
    var actionsByCategory: [String: [RemediationAction]] {
        Dictionary(grouping: actions) { $0.category ?? "Other" }
    }
    
    var highImpactActions: [RemediationAction] {
        actions.filter { $0.impact.lowercased() == "high" || $0.impact.lowercased() == "critical" }
    }
    
    var lowRiskActions: [RemediationAction] {
        actions.filter { $0.riskLevel?.lowercased() == "low" || $0.impact.lowercased() == "low" }
    }
}

