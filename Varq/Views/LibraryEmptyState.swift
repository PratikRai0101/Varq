import SwiftUI

struct LibraryEmptyState: View {
    let importBooks: () -> Void

    var body: some View {
        VStack(spacing: VarqSpacing.regular) {
            Image(systemName: "location.north.fill")
                .font(VarqTypography.ui(.largeTitle))
                .foregroundStyle(Color.varqSaffron)
                .accessibilityHidden(true)

            Text("Your next page is waiting")
                .font(VarqTypography.uiMedium(.title2))
                .foregroundStyle(Color.varqInkDark)

            Text("Import an EPUB, PDF, or CBZ to make a place for it in your library.")
                .font(VarqTypography.ui(.body))
                .foregroundStyle(Color.varqParchmentDeep)
                .multilineTextAlignment(.center)

            Button("Import books", action: importBooks)
                .buttonStyle(.borderedProminent)
                .tint(Color.varqTerracotta)
        }
        .padding(VarqSpacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.varqIndigo)
        .clipShape(RoundedRectangle(cornerRadius: VarqSpacing.regular))
        .accessibilityElement(children: .combine)
    }
}
