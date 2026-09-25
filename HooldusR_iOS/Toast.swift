//
//  Toast.swift
//  HooldusR_iOS
//
//  Stands in for FancyToast. Same idea: a short banner, colour-coded.
//

import SwiftUI

struct ToastMessage: Identifiable, Equatable {
    enum Kind {
        case success, warning, failure

        var tint: Color {
            switch self {
            case .success: return Color(red: 0x07 / 255, green: 0x9E / 255, blue: 0x3B / 255)
            case .warning: return .orange
            case .failure: return Color(red: 0xB5 / 255, green: 0x16 / 255, blue: 0x06 / 255)
            }
        }

        var symbol: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .failure: return "xmark.octagon.fill"
            }
        }
    }

    let id = UUID()
    let text: String
    let kind: Kind
}

struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: message.kind.symbol)
            Text(message.text)
                .font(.callout)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(message.kind.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(radius: 6, y: 2)
        .padding(.horizontal, 24)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
