import SwiftUI

/// A type-to-guess field with forgiving autocomplete. Tapping a suggestion (or pressing
/// return on an exact match) submits the guess.
struct GuessInputView: View {
    let store: CountryStore
    let excluded: Set<String>
    let onGuess: (Country) -> Void

    @State private var text = ""
    @State private var suggestions: [Country] = []
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.textSecondary)
                TextField("Type a country…", text: $text)
                    .focused($focused)
                    .font(Theme.rounded(20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .submitLabel(.go)
                    .onChange(of: text) { newValue in refresh(newValue) }
                    .onSubmit(submitExact)
                if !text.isEmpty {
                    Button { clear() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityLabel("Clear")
                }
            }
            .cardStyle()

            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, country in
                        Button { submit(country) } label: {
                            HStack(spacing: 12) {
                                Text(country.flag).font(.system(size: 24))
                                Text(country.name)
                                    .font(Theme.rounded(18, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .contentShape(Rectangle())
                        }
                        if index < suggestions.count - 1 {
                            Divider().overlay(Theme.panelStroke)
                        }
                    }
                }
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.panelStroke, lineWidth: 1)
                )
            }
        }
    }

    private func refresh(_ value: String) {
        suggestions = store.search(value, excluding: excluded, limit: 6)
    }

    private func submit(_ country: Country) {
        onGuess(country)
        clear()
    }

    private func submitExact() {
        if let match = store.exactMatch(text, excluding: excluded) ?? suggestions.first {
            submit(match)
        }
    }

    private func clear() {
        text = ""
        suggestions = []
    }
}
