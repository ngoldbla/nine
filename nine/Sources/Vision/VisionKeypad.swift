// VisionKeypad.swift — the trailing ornament: nine digits, then three tools.
//
// Laid out 3×3 because a cell's pencil notes are laid out 3×3: the 7 is in the
// keypad's bottom-left for the same reason it sits bottom-left of a cell, so
// the player's eye learns one map, not two. Every key is 76pt, over the 60pt
// eye-target floor, and every key is a system button, so the gaze highlight,
// the pinch press and the accessibility element come from the platform rather
// than from this file.
#if os(visionOS)
import SwiftUI
import CouchKit

struct VisionKeypad: View {
    @Environment(VisionModel.self) private var model

    private static let key: CGFloat = 76
    private static let gap: CGFloat = 10

    var body: some View {
        VStack(spacing: Self.gap) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: Self.gap) {
                    ForEach(1...3, id: \.self) { col in
                        digitKey(row * 3 + col)
                    }
                }
            }
            Divider().padding(.vertical, 4)
            HStack(spacing: Self.gap) {
                tool(Strings.string("game.control.pencil"),
                     symbol: model.pencilMode ? "pencil.circle.fill" : "pencil",
                     on: model.pencilMode) { model.pencilMode.toggle() }
                tool(Strings.string("menu.board.erase"), symbol: "delete.left") {
                    model.erase()
                }
                tool(Strings.string("game.control.undo"), symbol: "arrow.uturn.backward") {
                    model.undo()
                }
                .disabled(!model.canUndo)
            }
        }
        .padding(20)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 40, style: .continuous))
    }

    private func digitKey(_ digit: Int) -> some View {
        let done = model.isDigitComplete(digit) && !model.pencilMode
        return Button {
            model.enter(digit)
        } label: {
            Text(verbatim: "\(digit)")
                .font(.system(size: model.pencilMode ? 26 : 36,
                              weight: model.pencilMode ? .medium : .semibold,
                              design: .rounded))
                .monospacedDigit()
                .frame(width: Self.key, height: Self.key)
                .opacity(done ? 0.3 : 1)
        }
        .buttonStyle(.borderless)
        .buttonBorderShape(.roundedRectangle(radius: 22))
        .accessibilityLabel(Text(verbatim: "\(digit)"))
        .animation(.couchFast, value: model.pencilMode)
    }

    private func tool(_ label: String, symbol: String, on: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.medium))
                .frame(width: Self.key, height: Self.key * 0.8)
        }
        .buttonStyle(.borderless)
        .buttonBorderShape(.roundedRectangle(radius: 22))
        .background(on ? Color.accentColor.opacity(0.28) : .clear,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .help(label)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
#endif
