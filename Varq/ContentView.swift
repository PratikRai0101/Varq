import Foundation
import SwiftUI

struct ContentView: View {
    let importViewModel: ImportViewModel
    let privateBookViewModel: PrivateBookViewModel
    let managedLibraryDirectory: URL

    var body: some View {
        LibraryView(
            importViewModel: importViewModel,
            privateBookViewModel: privateBookViewModel,
            managedLibraryDirectory: managedLibraryDirectory
        )
    }
}
