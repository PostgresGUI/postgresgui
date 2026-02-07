//
//  LoadingOverlayView.swift
//  PostgresGUI
//
//  Created by ghazi on 12/20/25.
//

import SwiftUI

struct LoadingOverlayView: View {
    let phase: LoadingPhase

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: Constants.Spacing.large) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)

                Text(phase.localizedText)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(Constants.Spacing.extraLarge)
            .padding(.horizontal, Constants.Spacing.large)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

#Preview {
    LoadingOverlayView(phase: .connectingToDatabase)
}
