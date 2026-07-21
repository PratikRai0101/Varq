import Foundation
import SwiftUI

struct ContentView: View {
    let importViewModel: ImportViewModel
    let managedLibraryDirectory: URL

    var body: some View {
        LibraryView(
            importViewModel: importViewModel,
            managedLibraryDirectory: managedLibraryDirectory
        )
    }
}
