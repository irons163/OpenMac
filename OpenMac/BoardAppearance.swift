import Foundation
import SwiftUI

struct BoardMessageColorToken: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    var color: Color {
        Color(red: red, green: green, blue: blue).opacity(opacity)
    }

    var relativeLuminance: Double {
        let linearRed = linearizedComponent(red)
        let linearGreen = linearizedComponent(green)
        let linearBlue = linearizedComponent(blue)
        return (0.2126 * linearRed) + (0.7152 * linearGreen) + (0.0722 * linearBlue)
    }

    func contrastRatio(against other: BoardMessageColorToken) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func linearizedComponent(_ value: Double) -> Double {
        if value <= 0.03928 {
            return value / 12.92
        }
        return pow((value + 0.055) / 1.055, 2.4)
    }
}

enum BoardMessageColorPalette {
    static let darkBoardBackground = BoardMessageColorToken(red: 0.10, green: 0.12, blue: 0.16, opacity: 1.0)
    static let lightBoardBackground = BoardMessageColorToken(red: 0.96, green: 0.98, blue: 1.0, opacity: 1.0)

    static func token(for severity: BoardMessageSeverity?, scheme: ColorScheme) -> BoardMessageColorToken {
        let resolvedSeverity = severity ?? .error
        if scheme == .dark {
            switch resolvedSeverity {
            case .info:
                return BoardMessageColorToken(red: 0.42, green: 0.87, blue: 0.96, opacity: 1.0)
            case .warning:
                return BoardMessageColorToken(red: 0.94, green: 0.67, blue: 0.22, opacity: 1.0)
            case .error:
                return BoardMessageColorToken(red: 1.0, green: 0.64, blue: 0.59, opacity: 1.0)
            }
        } else {
            switch resolvedSeverity {
            case .info:
                return BoardMessageColorToken(red: 0.00, green: 0.42, blue: 0.56, opacity: 1.0)
            case .warning:
                return BoardMessageColorToken(red: 0.69, green: 0.35, blue: 0.00, opacity: 1.0)
            case .error:
                return BoardMessageColorToken(red: 0.74, green: 0.08, blue: 0.08, opacity: 1.0)
            }
        }
    }

    static func color(for severity: BoardMessageSeverity?, scheme: ColorScheme) -> Color {
        token(for: severity, scheme: scheme).color
    }
}

enum BoardSurfacePalette {
    static let darkBoardBackgroundStart = BoardMessageColorToken(red: 0.07, green: 0.09, blue: 0.13, opacity: 1.0)
    static let darkBoardBackgroundEnd = BoardMessageColorToken(red: 0.10, green: 0.12, blue: 0.16, opacity: 1.0)
    static let lightBoardBackgroundStart = BoardMessageColorToken(red: 0.96, green: 0.98, blue: 1.0, opacity: 1.0)
    static let lightBoardBackgroundEnd = BoardMessageColorToken(red: 0.93, green: 0.96, blue: 0.99, opacity: 1.0)

    static func detailGradientTokens(for scheme: ColorScheme) -> [BoardMessageColorToken] {
        scheme == .dark
            ? [darkBoardBackgroundStart, darkBoardBackgroundEnd]
            : [lightBoardBackgroundStart, lightBoardBackgroundEnd]
    }

    static func columnToken(for status: KanbanStatus, scheme: ColorScheme) -> BoardMessageColorToken {
        if scheme == .dark {
            switch status {
            case .todo:
                return BoardMessageColorToken(red: 0.18, green: 0.27, blue: 0.36, opacity: 1.0)
            case .inProgress:
                return BoardMessageColorToken(red: 0.15, green: 0.31, blue: 0.24, opacity: 1.0)
            case .review:
                return BoardMessageColorToken(red: 0.34, green: 0.27, blue: 0.17, opacity: 1.0)
            case .done:
                return BoardMessageColorToken(red: 0.24, green: 0.25, blue: 0.31, opacity: 1.0)
            }
        } else {
            switch status {
            case .todo:
                return BoardMessageColorToken(red: 0.82, green: 0.9, blue: 0.98, opacity: 1.0)
            case .inProgress:
                return BoardMessageColorToken(red: 0.81, green: 0.94, blue: 0.87, opacity: 1.0)
            case .review:
                return BoardMessageColorToken(red: 0.99, green: 0.92, blue: 0.77, opacity: 1.0)
            case .done:
                return BoardMessageColorToken(red: 0.89, green: 0.89, blue: 0.92, opacity: 1.0)
            }
        }
    }

    static func taskCardToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        scheme == .dark
            ? BoardMessageColorToken(red: 0.11, green: 0.14, blue: 0.19, opacity: 1.0)
            : BoardMessageColorToken(red: 1.0, green: 1.0, blue: 1.0, opacity: 1.0)
    }

    static func supplementaryCardToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        scheme == .dark
            ? BoardMessageColorToken(red: 0.17, green: 0.20, blue: 0.27, opacity: 1.0)
            : BoardMessageColorToken(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.92)
    }

    static func emptyStateToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        scheme == .dark
            ? BoardMessageColorToken(red: 0.19, green: 0.23, blue: 0.30, opacity: 1.0)
            : BoardMessageColorToken(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.68)
    }

    static func color(for status: KanbanStatus, scheme: ColorScheme) -> Color {
        columnToken(for: status, scheme: scheme).color
    }

    static func taskCardColor(for scheme: ColorScheme) -> Color {
        taskCardToken(for: scheme).color
    }

    static func supplementaryCardColor(for scheme: ColorScheme) -> Color {
        supplementaryCardToken(for: scheme).color
    }

    static func emptyStateColor(for scheme: ColorScheme) -> Color {
        emptyStateToken(for: scheme).color
    }
}

enum BoardChromePalette {
    static func counterToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        scheme == .dark
            ? BoardMessageColorToken(red: 0.24, green: 0.29, blue: 0.37, opacity: 1.0)
            : BoardMessageColorToken(red: 0.96, green: 0.97, blue: 0.99, opacity: 1.0)
    }

    static func storyPointToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        scheme == .dark
            ? BoardMessageColorToken(red: 0.20, green: 0.24, blue: 0.31, opacity: 1.0)
            : BoardMessageColorToken(red: 0.90, green: 0.92, blue: 0.95, opacity: 1.0)
    }

    static func columnBorderToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        scheme == .dark
            ? BoardMessageColorToken(red: 0.31, green: 0.36, blue: 0.46, opacity: 1.0)
            : BoardMessageColorToken(red: 0.72, green: 0.77, blue: 0.84, opacity: 1.0)
    }

    static func taskCardBorderToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        scheme == .dark
            ? BoardMessageColorToken(red: 0.30, green: 0.35, blue: 0.44, opacity: 1.0)
            : BoardMessageColorToken(red: 0.72, green: 0.77, blue: 0.84, opacity: 1.0)
    }

    static func supplementaryCardBorderToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        scheme == .dark
            ? BoardMessageColorToken(red: 0.30, green: 0.35, blue: 0.45, opacity: 1.0)
            : BoardMessageColorToken(red: 0.71, green: 0.76, blue: 0.83, opacity: 1.0)
    }

    static func summaryBadgeBorderToken(for scheme: ColorScheme) -> BoardMessageColorToken {
        columnBorderToken(for: scheme)
    }

    static func counterColor(for scheme: ColorScheme) -> Color {
        counterToken(for: scheme).color
    }

    static func storyPointColor(for scheme: ColorScheme) -> Color {
        storyPointToken(for: scheme).color
    }

    static func columnBorderColor(for scheme: ColorScheme) -> Color {
        columnBorderToken(for: scheme).color
    }

    static func taskCardBorderColor(for scheme: ColorScheme) -> Color {
        taskCardBorderToken(for: scheme).color
    }

    static func supplementaryCardBorderColor(for scheme: ColorScheme) -> Color {
        supplementaryCardBorderToken(for: scheme).color
    }

    static func summaryBadgeBorderColor(for scheme: ColorScheme) -> Color {
        summaryBadgeBorderToken(for: scheme).color
    }
}

enum SummaryBadgeAccent: CaseIterable {
    case blue
    case indigo
    case amber
    case red
    case green
    case teal
    case mint
}

enum SummaryBadgePalette {
    static func token(for accent: SummaryBadgeAccent, scheme: ColorScheme) -> BoardMessageColorToken {
        if scheme == .dark {
            switch accent {
            case .blue:
                return BoardMessageColorToken(red: 0.19, green: 0.31, blue: 0.47, opacity: 1.0)
            case .indigo:
                return BoardMessageColorToken(red: 0.24, green: 0.26, blue: 0.48, opacity: 1.0)
            case .amber:
                return BoardMessageColorToken(red: 0.43, green: 0.30, blue: 0.12, opacity: 1.0)
            case .red:
                return BoardMessageColorToken(red: 0.48, green: 0.20, blue: 0.20, opacity: 1.0)
            case .green:
                return BoardMessageColorToken(red: 0.20, green: 0.39, blue: 0.28, opacity: 1.0)
            case .teal:
                return BoardMessageColorToken(red: 0.16, green: 0.36, blue: 0.36, opacity: 1.0)
            case .mint:
                return BoardMessageColorToken(red: 0.15, green: 0.34, blue: 0.29, opacity: 1.0)
            }
        } else {
            switch accent {
            case .blue:
                return BoardMessageColorToken(red: 0.84, green: 0.92, blue: 0.99, opacity: 1.0)
            case .indigo:
                return BoardMessageColorToken(red: 0.87, green: 0.89, blue: 0.98, opacity: 1.0)
            case .amber:
                return BoardMessageColorToken(red: 0.99, green: 0.92, blue: 0.80, opacity: 1.0)
            case .red:
                return BoardMessageColorToken(red: 0.98, green: 0.86, blue: 0.86, opacity: 1.0)
            case .green:
                return BoardMessageColorToken(red: 0.86, green: 0.95, blue: 0.89, opacity: 1.0)
            case .teal:
                return BoardMessageColorToken(red: 0.84, green: 0.95, blue: 0.95, opacity: 1.0)
            case .mint:
                return BoardMessageColorToken(red: 0.86, green: 0.96, blue: 0.92, opacity: 1.0)
            }
        }
    }

    static func color(for accent: SummaryBadgeAccent, scheme: ColorScheme) -> Color {
        token(for: accent, scheme: scheme).color
    }
}

enum BoardSemanticTextRole {
    case success
    case warning
    case error
}

enum BoardSemanticTextPalette {
    static func token(for role: BoardSemanticTextRole, scheme: ColorScheme) -> BoardMessageColorToken {
        if scheme == .dark {
            switch role {
            case .success:
                return BoardMessageColorToken(red: 0.45, green: 0.92, blue: 0.59, opacity: 1.0)
            case .warning:
                return BoardMessageColorToken(red: 0.94, green: 0.67, blue: 0.22, opacity: 1.0)
            case .error:
                return BoardMessageColorToken(red: 1.0, green: 0.64, blue: 0.59, opacity: 1.0)
            }
        } else {
            switch role {
            case .success:
                return BoardMessageColorToken(red: 0.06, green: 0.45, blue: 0.18, opacity: 1.0)
            case .warning:
                return BoardMessageColorToken(red: 0.69, green: 0.35, blue: 0.00, opacity: 1.0)
            case .error:
                return BoardMessageColorToken(red: 0.74, green: 0.08, blue: 0.08, opacity: 1.0)
            }
        }
    }

    static func color(for role: BoardSemanticTextRole, scheme: ColorScheme) -> Color {
        token(for: role, scheme: scheme).color
    }
}

enum BoardNeutralTextRole {
    case secondary
}

enum BoardNeutralTextPalette {
    static func token(for role: BoardNeutralTextRole, scheme: ColorScheme) -> BoardMessageColorToken {
        if scheme == .dark, role == .secondary {
            return BoardMessageColorToken(red: 0.82, green: 0.86, blue: 0.92, opacity: 1.0)
        }
        return BoardMessageColorToken(red: 0.28, green: 0.33, blue: 0.42, opacity: 1.0)
    }

    static func color(for role: BoardNeutralTextRole, scheme: ColorScheme) -> Color {
        token(for: role, scheme: scheme).color
    }
}

struct BoardMessageBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: String
    let severity: BoardMessageSeverity?

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(BoardMessageColorPalette.color(for: severity, scheme: colorScheme))
    }
}
