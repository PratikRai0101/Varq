//
//  VarqApp.swift
//  Varq
//
//  Created by Pratik Rai on 21/07/26.
//

import SwiftUI
import SwiftData

@main
struct VarqApp: App {
    let importViewModel: ImportViewModel

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            Book.self,
            ReadingProgress.self,
            Highlight.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        guard let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("The app sandbox did not provide an Application Support directory.")
        }

        let managedLibraryDirectory = applicationSupportDirectory
            .appendingPathComponent("Varq", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
        importViewModel = ImportViewModel(importer: ImportService(libraryDirectory: managedLibraryDirectory))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(importViewModel: importViewModel)
        }
        .modelContainer(sharedModelContainer)
    }
}
