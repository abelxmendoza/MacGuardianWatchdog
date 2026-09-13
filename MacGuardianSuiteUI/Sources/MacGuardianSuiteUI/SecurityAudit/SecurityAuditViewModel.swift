import Foundation
import Combine

@MainActor
class SecurityAuditViewModel: ObservableObject {
    @Published var checks: [AuditCheck] = []
    @Published var summary: AuditSummary = AuditSummary()
    @Published var loading = false
    @Published var errorMessage: String?
    @Published var lastRunDate: Date?
    
    func run(repositoryPath: String) async {
        loading = true
        errorMessage = nil

        let (loadedChecks, loadedSummary) = await SecurityAuditScriptService.shared.runAudit(repositoryPath: repositoryPath)
        
        checks = loadedChecks
        summary = loadedSummary
        lastRunDate = Date()
        loading = false
        
        // If no checks were found, set error message
        if checks.isEmpty && errorMessage == nil {
            errorMessage = "No audit results found. The script may need to be run from Terminal."
        }
    }
    
    var checksByCategory: [AuditCategory] {
        let grouped = Dictionary(grouping: checks) { $0.category ?? "Other" }
        return grouped.map { AuditCategory(name: $0.key, checks: $0.value) }
            .sorted { $0.name < $1.name }
    }
    
    var failedChecks: [AuditCheck] {
        checks.filter { $0.status.lowercased() == "fail" }
    }
    
    var warningChecks: [AuditCheck] {
        checks.filter { $0.status.lowercased() == "warning" }
    }
    
    var passedChecks: [AuditCheck] {
        checks.filter { $0.status.lowercased() == "pass" }
    }
}

