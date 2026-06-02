//
//  ScannerSheet.swift
//  RegattaResults
//
//  Presented as a .sheet from TrackedView. Handles only input:
//  camera QR scanning and manual URL entry. Validates the URL before
//  calling onValidURL and dismissing — the caller (TrackedView) drives
//  loading and navigation from there.
//

import SwiftUI
import AVFoundation
import Vision

struct ScannerSheet: View {
    /// Called with the validated, cleaned URL when the user submits.
    let onValidURL: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    @State private var urlText       = ""
    @State private var clipboardURL: String? = nil
    @State private var pasteFeedback = false
    @State private var showError     = false
    @State private var errorMessage  = ""

    // Camera scanning state — local to this sheet
    @State private var isScanning    = true
    @State private var isLoading     = false   // unused here, satisfies ScannerView bindings

    var body: some View {
        ZStack {
            AtmosphereBackground()

            VStack(spacing: 0) {
                handleBar

                // Header
                VStack(spacing: 2) {
                    Text("SCAN OR ENTER URL")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.4)
                        .foregroundColor(.tellTextMute)
                    Text("Find a Regatta")
                        .font(.system(size: 26, weight: .black))
                        .tracking(-0.5)
                        .foregroundColor(.tellText)
                }
                .padding(.top, 8)
                .padding(.bottom, 24)

                viewfinder
                    .padding(.horizontal, 40)
                Spacer()
                if let clip = clipboardURL {
                    clipChip(clip)
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                urlBar
                    .padding(.horizontal, 24)
                    .padding(.top, clipboardURL == nil ? 24 : 12)

                Text("Supports: ClubSpot")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(0.3)
                    .foregroundColor(.tellTextMute)
                    .padding(.top, 12)

                Spacer()
            }
        }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button("Done") { fieldFocused = false }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.tellAccent)
                }
            }
        }
        .alert("Invalid URL", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear { refreshClipboard() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshClipboard()
        }
        .onChange(of: isLoading) { loading in
            if loading && !urlText.isEmpty {
                submitURL(urlText)
            }
        }
    }

    // MARK: - Handle bar

    private var handleBar: some View {
        Capsule()
            .fill(Color.white.opacity(0.20))
            .frame(width: 36, height: 4)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.glassBorder, lineWidth: 1))
            .aspectRatio(1, contentMode: .fit)
            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 8)
            .overlay {
                GeometryReader { geo in
                    let inset: CGFloat = 20
                    let innerSize = max(geo.size.width - inset * 2, 0)

                    ZStack {
                        ScannerView(
                            scannedString: $urlText,
                            isScanning:    $isScanning,
                            isLoading:     $isLoading
                        )
                        .frame(width: innerSize, height: innerSize)
                        .clipShape(RoundedRectangle(cornerRadius: 18))

                        TellScannerCorners(size: innerSize)
                    }
                    .frame(width: innerSize, height: innerSize)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
    }

    // MARK: - Clipboard chip

    private func clipChip(_ url: String) -> some View {
        Button { submitURL(url) } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.tellCool)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tap to use clipboard")
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundColor(.tellTextMute)
                    Text(url)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.tellText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.tellCool)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassCard(radius: 12, railColor: .glassBorder)
        }
        .buttonStyle(.plain)
    }

    // MARK: - URL bar

    private var urlBar: some View {
        HStack(spacing: 0) {
            // Paste
            Button {
                guard !pasteFeedback else { return }
                if let s = UIPasteboard.general.string {
                    urlText = s
                    clipboardURL = nil
                    pasteFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { pasteFeedback = false }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: pasteFeedback ? "checkmark" : "doc.on.clipboard")
                        .font(.system(size: 13, weight: .bold))
                    Text(pasteFeedback ? "Pasted" : "Paste")
                        .font(.system(size: 13, weight: .black))
                        .tracking(0.3)
                }
                .foregroundColor(pasteFeedback ? .tellGreen : .tellCool)
                .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 14)
            }
            .animation(.easeInOut(duration: 0.2), value: pasteFeedback)

            Rectangle().fill(Color.glassBorder).frame(width: 1, height: 28)

            // Field
            TextField("https://theclubspot.com/regatta/…", text: $urlText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tellText)
                .tint(.tellAccent)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .focused($fieldFocused)
                .submitLabel(.go)
                .onSubmit { submitURL(urlText) }
                .padding(.horizontal, 12).padding(.vertical, 14)

            if !urlText.isEmpty {
                Button { urlText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.tellTextMute)
                }
                .padding(.trailing, 8)
                .transition(.scale.combined(with: .opacity))
            }

            // Go button
            Button { submitURL(urlText) } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(urlText.isEmpty ? Color.white.opacity(0.08) : Color.tellAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: urlText.isEmpty ? .clear : .tellAccent.opacity(0.4),
                            radius: 8, x: 0, y: 3)
            }
            .disabled(urlText.isEmpty)
            .padding(.trailing, 6)
            .animation(.easeInOut(duration: 0.2), value: urlText.isEmpty)
        }
        .glassCard(radius: 14)
        .animation(.easeInOut(duration: 0.15), value: urlText.isEmpty)
    }

    // MARK: - Submit logic

    private func submitURL(_ raw: String) {
        fieldFocused = false
        var url = raw.trimmingCharacters(in: .whitespaces)
        if url.hasSuffix("/results") { url = String(url.dropLast("/results".count)) }

        guard isRecognized(url) else {
            errorMessage = "That doesn't look like a ClubSpot or RegattaNetwork URL. Check it and try again."
            showError = true
            return
        }

        dismiss()
        // Small delay so the sheet dismiss animation starts before TrackedView
        // transitions to loading state — keeps it feeling smooth.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onValidURL(url)
        }
    }

    private func refreshClipboard() {
        guard let s = UIPasteboard.general.string, isRecognized(s), s != urlText else {
            clipboardURL = nil; return
        }
        clipboardURL = s
    }

    private func isRecognized(_ s: String) -> Bool {
        if s.lowercased().contains("regattanetwork") { return true }
        guard let url = URL(string: s) else { return false }
        return url.path.contains("/regatta/")
    }
}


// MARK: - ScannerView (AVFoundation camera + Vision barcode detection)
//
// SwiftUI wrapper around an AVCaptureSession. Detects ClubSpot regatta URLs
// and RegattaNetwork URLs in QR codes, strips the `/results` suffix, and
// reports them via the `scannedString` binding. The parent view should
// observe `isLoading` flipping to `true` to know a valid code was found.

struct ScannerView: UIViewControllerRepresentable {
    @Binding var scannedString: String
    @Binding var isScanning:    Bool
    @Binding var isLoading:     Bool

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        let captureSession = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
              captureSession.canAddInput(videoInput) else {
            return viewController
        }
        captureSession.addInput(videoInput)

        let videoOutput = AVCaptureVideoDataOutput()
        if captureSession.canAddOutput(videoOutput) {
            videoOutput.setSampleBufferDelegate(context.coordinator, queue: DispatchQueue(label: "videoQueue"))
            captureSession.addOutput(videoOutput)
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.cornerRadius = 20
        viewController.view.layer.addSublayer(previewLayer)

        context.coordinator.captureSession = captureSession
        context.coordinator.previewLayer   = previewLayer
        context.coordinator.viewController = viewController

        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            if self.isScanning {
                if let session = context.coordinator.captureSession, !session.isRunning {
                    DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
                }
            } else {
                if let session = context.coordinator.captureSession, session.isRunning {
                    DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
                }
            }
            context.coordinator.previewLayer?.frame = uiViewController.view.bounds
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        var parent: ScannerView
        var captureSession: AVCaptureSession?
        var previewLayer:   AVCaptureVideoPreviewLayer?
        var viewController: UIViewController?
        private var hasScannedInCurrentSession = false

        init(_ parent: ScannerView) { self.parent = parent; super.init() }

        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            DispatchQueue.main.async {
                guard self.parent.isScanning && !self.hasScannedInCurrentSession else { return }
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                DispatchQueue.global(qos: .userInitiated).async { self.detectBarcode(in: pixelBuffer) }
            }
        }

        func detectBarcode(in pixelBuffer: CVPixelBuffer) {
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            do {
                try handler.perform([request])
                if let results = request.results?.compactMap({ $0 as VNBarcodeObservation }),
                   var payload = results.first?.payloadStringValue {
                    DispatchQueue.main.async {
                        guard self.parent.isScanning && !self.hasScannedInCurrentSession else { return }
                        guard let url = URL(string: payload) else { return }
                        let isClubSpot = url.path.contains("/regatta/")
                        let isRegNet   = payload.lowercased().contains("regattanetwork")
                        guard isClubSpot || isRegNet else { return }
                        if payload.hasSuffix("/results") {
                            payload = String(payload.dropLast("/results".count))
                        }
                        self.hasScannedInCurrentSession = true
                        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                        self.parent.scannedString = payload
                        self.parent.isLoading     = true
                        self.parent.isScanning    = false
                    }
                }
            } catch {
                print("Barcode detection failed: \(error)")
            }
        }

        func resetScanningSession() {
            hasScannedInCurrentSession = false
            if let session = captureSession, !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
            }
        }
    }
}


// MARK: - TellScannerCorners
//
// Overlay drawn on top of ScannerView: four cool-blue corner brackets plus
// a pulsing horizontal scan line. Sized to a 260×260 viewfinder.

struct TellScannerCorners: View {
    let size: CGFloat
    @State private var scanLine: CGFloat = -1

    var body: some View {
        ZStack {
            // Animated scan line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .tellCool.opacity(0.7), .tellCool, .tellCool.opacity(0.7), .clear],
                        startPoint: .leading,
                        endPoint:   .trailing
                    )
                )
                .frame(height: 1.5)
                .offset(y: scanLine * (size/2))
                .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: scanLine)

            // Corner brackets
            ForEach(CornerPosition.allCases, id: \.self) { corner in
                TellCornerBracket(corner: corner, size: size)
            }
        }
        .onAppear { scanLine = 1 }
    }
}

enum CornerPosition: CaseIterable, Hashable {
    case topLeft, topRight, bottomLeft, bottomRight
}

struct TellCornerBracket: View {
    let corner: CornerPosition
    let size: CGFloat

    var body: some View {
        Path { path in
            let arm:  CGFloat = 24
            let w:    CGFloat = 3.5
            switch corner {
            case .topLeft:
                path.move(to: CGPoint(x: 0,   y: arm)); path.addLine(to: CGPoint(x: 0,    y: w))
                path.addLine(to: CGPoint(x: w, y: 0));  path.addLine(to: CGPoint(x: arm,  y: 0))
            case .topRight:
                path.move(to: CGPoint(x: size-arm, y: 0));    path.addLine(to: CGPoint(x: size-w, y: 0))
                path.addLine(to: CGPoint(x: size,  y: w));    path.addLine(to: CGPoint(x: size,   y: arm))
            case .bottomLeft:
                path.move(to: CGPoint(x: 0,   y: size-arm));  path.addLine(to: CGPoint(x: 0,    y: size-w))
                path.addLine(to: CGPoint(x: w, y: size));     path.addLine(to: CGPoint(x: arm,  y: size))
            case .bottomRight:
                path.move(to: CGPoint(x: size-arm, y: size)); path.addLine(to: CGPoint(x: size-w, y: size))
                path.addLine(to: CGPoint(x: size,  y: size-w)); path.addLine(to: CGPoint(x: size, y: size-arm))
            }
        }
        .stroke(Color.tellCool, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
    }
}
