import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppContainer {
    let modelContainer: ModelContainer
    let library: LibraryStore
    let credentialStore: any CredentialStore
    let hostTrustPrompt = HostTrustPromptCenter()
    let secretPrompt = SecretPromptCenter()
    let settings: AppSettings
    let transfers: TransferQueue
    let workspace: WorkspaceStore
    let router = AppRouter()

    init(
        inMemory: Bool = false,
        credentialStore: (any CredentialStore)? = nil,
        defaults: UserDefaults = .standard
    ) throws {
        let schema = Schema(RemoteHubSchemaV1.models)
        let configuration = ModelConfiguration(
            "RemoteHub",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        modelContainer = try ModelContainer(
            for: schema,
            migrationPlan: RemoteHubMigrationPlan.self,
            configurations: configuration
        )
        let context = modelContainer.mainContext
        library = LibraryStore(context: context)
        self.credentialStore = credentialStore ?? KeychainCredentialStore()
        settings = AppSettings(defaults: defaults)
        transfers = TransferQueue(maximumConcurrent: settings.concurrentTransfers)
        let connector = ConnectionConnector(
            library: library,
            credentialStore: self.credentialStore,
            hostStore: SwiftDataKnownHostStore(context: context),
            hostPrompt: hostTrustPrompt,
            secretPrompt: secretPrompt,
            settings: settings
        )
        workspace = WorkspaceStore(connector: connector)
    }
}
