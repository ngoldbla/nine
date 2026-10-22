// TVSettings.swift — the TV's settings list, beside the board (tvOS input pass).
//
// The TV used to render `PrefsSheetContent`, the phone's sheet, at couch size.
// Its rows were tvOS's stock `Toggle`s, whose system focus platter is drawn
// larger than the row and so broke out of the grouped card around it, and
// whose resting state looked half-focused — eight blue slabs and no list
// (review: "highlights that are oversized and break their containers").
//
// This is one row shape for everything, with a focus treatment drawn *inside*
// the row's own shape: an accent wash, a crisp rim and a one-and-a-half percent
// lift. No cards inside cards; a section is a small label over a run of rows.
// A toggle flips in place. Theme and accent are rows that open a strip of
// swatches in place — focus previews on the board beside the panel, a tap
// keeps it, Back puts the old one back.
#if os(tvOS)
import SwiftUI
import CouchKit

struct TVSettingsList: View {
    let model: AppModel
    let accent: Color
    let onNewGame: @MainActor (Difficulty) -> Void
    let onHome: @MainActor () -> Void

    private enum Picking: Equatable { case theme, accent }

    @State private var picking: Picking?
    /// What the strip opened on, restored by Back.
    @State private var pickedFrom: (theme: ThemeChoice, accent: AccentChoice)?
    @FocusState private var focusedTheme: ThemeChoice?
    @FocusState private var focusedAccent: AccentChoice?
    @FocusState private var focusedRow: String?
    @Environment(\.colorScheme) private var colorScheme

    private var tones: ThemeTones { model.prefs.theme.tones(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            section(Strings.string("prefs.section.play")) {
                toggleRow("timer", Strings.string("prefs.timer.title"), "clock.fill", \.showTimer)
                toggleRow("errors", Strings.string("prefs.errorHighlight.title"),
                          "exclamationmark.triangle.fill", \.errorHighlight)
                toggleRow("highlight", Strings.string("prefs.numberHighlight.title"),
                          "square.grid.3x3.fill", \.numberHighlight)
                toggleRow("resume", Strings.string("prefs.resume.title"), "play.fill",
                          \.resumeOnLaunch)
            }
            section(Strings.string("prefs.section.feel")) {
                toggleRow("haptics", Strings.string("prefs.controllerHaptics.title"),
                          "gamecontroller.fill", \.controllerHaptics)
            }
            section(Strings.string("prefs.section.appearance")) {
                if picking == .theme { themeStrip } else {
                    valueRow("theme", Strings.string("prefs.theme.title"), "circle.lefthalf.filled",
                             value: model.prefs.theme.title) { open(.theme) }
                }
                if picking == .accent { accentStrip } else {
                    valueRow("accent", Strings.string("prefs.accent.title"), "paintpalette.fill",
                             value: model.prefs.accent.title) { open(.accent) }
                }
            }
            section(Strings.string("prefs.newGame.title")) {
                ForEach(Difficulty.rowBands, id: \.self) { band in
                    valueRow("new.\(band.rawValue)", Strings.difficulty(band), "square.grid.3x3",
                             value: "") { onNewGame(band) }
                }
            }
            valueRow("home", Strings.string("game.control.home"), "house.fill", value: "") {
                onHome()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Rows

    private func section<Rows: View>(
        _ title: String, @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
                .accessibilityAddTraits(.isHeader)
            rows()
        }
    }

    private func toggleRow(
        _ id: String, _ title: String, _ symbol: String,
        _ key: WritableKeyPath<NinePrefs, Bool>
    ) -> some View {
        let isOn = model.prefs[keyPath: key]
        return Button {
            model.prefs[keyPath: key].toggle()
        } label: {
            TVRowLabel(title: title, symbol: symbol,
                       value: TVSettingsPhrase.onOff(isOn),
                       valueTint: isOn ? accent : Color.secondary, iconTint: accent)
        }
        .buttonStyle(TVRowStyle(accent: accent, isLight: tones.isLight))
        .focused($focusedRow, equals: id)
        .accessibilityValue(TVSettingsPhrase.onOff(isOn))
    }

    private func valueRow(
        _ id: String, _ title: String, _ symbol: String, value: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            TVRowLabel(title: title, symbol: symbol, value: value,
                       valueTint: .secondary, iconTint: accent)
        }
        .buttonStyle(TVRowStyle(accent: accent, isLight: tones.isLight))
        .focused($focusedRow, equals: id)
    }

    // MARK: - Swatch strips

    private func open(_ which: Picking) {
        pickedFrom = (model.prefs.theme, model.prefs.accent)
        withAnimation(.couchFast) { picking = which }
        // Land on the current choice, so the strip opens where the row was.
        Task { @MainActor in
            switch which {
            case .theme: focusedTheme = model.prefs.theme
            case .accent: focusedAccent = model.prefs.accent
            }
        }
    }

    /// Keep what is under focus and fold the strip back into its row.
    private func close(keep: Bool) {
        let which = picking
        if !keep, let from = pickedFrom {
            model.prefs.theme = from.theme
            model.prefs.accent = from.accent
        }
        withAnimation(.couchFast) { picking = nil }
        pickedFrom = nil
        Task { @MainActor in focusedRow = which == .theme ? "theme" : "accent" }
    }

    private var themeStrip: some View {
        strip(title: Strings.string("prefs.theme.title")) {
            ForEach(ThemeChoice.allCases, id: \.self) { choice in
                Button { close(keep: true) } label: {
                    ThemeSwatchArt(choice: choice)
                }
                .buttonStyle(TVSwatchStyle(accent: accent, round: false))
                .focused($focusedTheme, equals: choice)
                .accessibilityLabel(choice.title)
            }
        }
        .onChange(of: focusedTheme) { _, choice in
            if let choice { model.prefs.theme = choice }
        }
    }

    private var accentStrip: some View {
        strip(title: Strings.string("prefs.accent.title")) {
            ForEach(AccentChoice.allCases, id: \.self) { choice in
                Button { close(keep: true) } label: {
                    Circle()
                        .fill(choice.color(isLight: tones.isLight))
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(TVSwatchStyle(accent: accent, round: true))
                .focused($focusedAccent, equals: choice)
                .accessibilityLabel(choice.title)
            }
        }
        .onChange(of: focusedAccent) { _, choice in
            if let choice { model.prefs.accent = choice }
        }
    }

    /// An open strip: the row's title over its swatches, one line, scrolling
    /// sideways when a theme list outgrows the panel. Back cancels.
    private func strip<Swatches: View>(
        title: String, @ViewBuilder swatches: () -> Swatches
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .padding(.leading, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) { swatches() }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .scrollClipDisabled()
        }
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.primary.opacity(0.06)))
        .onExitCommand { close(keep: false) }
        .focusSection()
        .transition(.opacity)
    }
}

// MARK: - The row

/// Icon, title, value — the one row every setting is.
private struct TVRowLabel: View {
    let title: String
    let symbol: String
    let value: String
    let valueTint: Color
    let iconTint: Color

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 36)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 12)
            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(valueTint)
                    .lineLimit(1)
            }
        }
    }
}

/// The row's focus treatment, inside its own rounded shape: nothing about a
/// focused row is larger than the row (the old platter's whole fault).
struct TVRowStyle: ButtonStyle {
    let accent: Color
    let isLight: Bool

    func makeBody(configuration: Configuration) -> some View {
        TVRowBody(configuration: configuration, accent: accent, isLight: isLight)
    }

    private struct TVRowBody: View {
        let configuration: ButtonStyle.Configuration
        let accent: Color
        let isLight: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            configuration.label
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                .background(shape.fill(isFocused ? accent.opacity(isLight ? 0.18 : 0.26)
                                                 : Color.primary.opacity(isLight ? 0.04 : 0.06)))
                .overlay(shape.strokeBorder(isFocused ? accent : Color.primary.opacity(0.08),
                                            lineWidth: isFocused ? 2.5 : 1))
                .scaleEffect(isFocused ? 1.015 : (configuration.isPressed ? 0.99 : 1))
                .animation(.couchFast, value: isFocused)
        }
    }
}

/// A swatch's focus: a ring and a lift, both inside the strip's padding.
private struct TVSwatchStyle: ButtonStyle {
    let accent: Color
    let round: Bool

    func makeBody(configuration: Configuration) -> some View {
        SwatchBody(configuration: configuration, round: round)
    }

    private struct SwatchBody: View {
        let configuration: ButtonStyle.Configuration
        let round: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .padding(7)
                .overlay {
                    if round {
                        Circle().strokeBorder(Color.primary, lineWidth: isFocused ? 4 : 0)
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary, lineWidth: isFocused ? 4 : 0)
                    }
                }
                .scaleEffect(isFocused ? 1.12 : 1)
                .animation(.couchFast, value: isFocused)
        }
    }
}

/// A theme at swatch size: its ground with a "9" in its digit tone; Auto is
/// split diagonally because it can resolve to either.
private struct ThemeSwatchArt: View {
    let choice: ThemeChoice

    var body: some View {
        let dark = choice.tones(for: .dark)
        let light = choice.tones(for: .light)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack {
            Rectangle().fill(dark.background)
            if choice == .auto {
                PrefsSheetContent.DiagonalHalf().fill(light.background)
            }
            Text(verbatim: "9")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(choice == .auto ? .gray : dark.digitTone)
        }
        .frame(width: 52, height: 52)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
    }
}

enum TVSettingsPhrase {
    static func onOff(_ isOn: Bool) -> String {
        Strings.string(isOn ? "prefs.toggle.on" : "prefs.toggle.off")
    }
}
#endif
