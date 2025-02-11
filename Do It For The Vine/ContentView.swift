//
//  ContentView.swift
//  Do It For The Vine
//
//  Created by Taha Abbasi on 2/10/25.
//

import SwiftUI
import AVFoundation
import Photos
import Combine

struct ContentView: View {
    @StateObject private var videoRecorder = VideoRecorder()
    @State private var isRecording = false

    var body: some View {
        VStack {
            CameraPreview(session: videoRecorder.session)
                .aspectRatio(1, contentMode: .fit)
                .frame(width: UIScreen.main.bounds.width - 40)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white, lineWidth: 2))

            Button(action: {
                if isRecording {
                    videoRecorder.stopRecording()
                } else {
                    videoRecorder.startRecording()
                }
                isRecording.toggle()
            }) {
                Circle()
                    .frame(width: 80, height: 80)
                    .foregroundColor(isRecording ? .red : .gray)
                    .shadow(radius: 5)
            }
            .padding()
        }
        .onAppear {
            videoRecorder.setupSession()
        }
    }
}

class VideoRecorder: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureMovieFileOutput()
    private var outputURL: URL?

    func setupSession() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let mic = AVCaptureDevice.default(for: .audio),
                  let videoInput = try? AVCaptureDeviceInput(device: camera),
                  let audioInput = try? AVCaptureDeviceInput(device: mic) else {
                print("🚨 Error: Unable to access camera or microphone")
                return
            }

            if self.session.canAddInput(videoInput) { self.session.addInput(videoInput) }
            if self.session.canAddInput(audioInput) { self.session.addInput(audioInput) }
            if self.session.canAddOutput(self.videoOutput) { self.session.addOutput(self.videoOutput) }

            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    func startRecording() {
        guard session.isRunning else {
            print("🚨 AVCaptureSession is not running!")
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        outputURL = fileURL

        videoOutput.startRecording(to: fileURL, recordingDelegate: self)
    }

    func stopRecording() {
        videoOutput.stopRecording()
    }
}

extension VideoRecorder: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        guard error == nil else { return }
        cropVideoToSquare(inputURL: outputFileURL) { croppedURL in
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: croppedURL)
                    }
                }
            }
        }
    }

    private func cropVideoToSquare(inputURL: URL, completion: @escaping (URL) -> Void) {
        let outputURL = inputURL.deletingPathExtension().appendingPathExtension("mp4")
        let asset = AVAsset(url: inputURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            completion(inputURL)
            return
        }

        let squareComposition = AVMutableVideoComposition()
        squareComposition.renderSize = CGSize(width: 1080, height: 1080)
        squareComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(inputURL)
            return
        }
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        let transform = videoTrack.preferredTransform
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        squareComposition.instructions = [instruction]

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = squareComposition
        exportSession.exportAsynchronously {
            completion(outputURL)
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

#Preview {
    ContentView()
}
