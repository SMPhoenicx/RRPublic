//
//  LaunchView.swift
//  RegattaResults
//
//  Created by Suman Muppavarapu on 5/21/26.
//

import SwiftUI
import DotLottie

struct LaunchView: View {
    @EnvironmentObject var repository: RegattaRepository
    let onComplete: () -> Void
    
    @State private var hasStarted = false
    //amt of time it stays open
    private let minSplashSeconds: UInt64 = 1_200_000_000

    let loadAnim = DotLottieAnimation(fileName: "waveAnim", config: AnimationConfig(autoplay: false, loop: false, speed: 1.7))
    
    var body: some View {
        ZStack {
            AtmosphereBackground()
            
            VStack(spacing: 16) {
                Spacer()
                
                Image("rrWhite")
                    .resizable()
                    .frame(width: 200, height: 128)
                    .foregroundColor(.tellAccent)
                
                Spacer()
                
                DotLottiePlayerView(animation: loadAnim)
                                .looping()
                
                Text("Waiting for the breeze...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.tellTextMute)
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            guard !hasStarted else { return }
            hasStarted = true
//            #if !DEBUG
            Task {
                await runStartup()
            }
//            #endif
        }
    }
    
    @MainActor
    private func runStartup() async {
        await repository.fetchAllHomeData()
        
        try? await Task.sleep(nanoseconds: minSplashSeconds)
        
        onComplete()
    }
}

//#Preview {
//    LaunchView() {
//
//    }
//}
