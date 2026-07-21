import SwiftUI

struct ContentView: View {
    let importViewModel: ImportViewModel

    var body: some View {
        LibraryView(importViewModel: importViewModel)
    }
}
