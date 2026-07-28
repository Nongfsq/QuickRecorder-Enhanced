//
//  AVContext.swift
//  QuickRecorder
//
//  Created by apple on 2024/4/27.
//
import AppKit
import Foundation
import AVFoundation
import UserNotifications
import RecordingDomain

extension AppDelegate {
    func recordingCamera(with device: AVCaptureDevice) {
        SCContext.captureSession = AVCaptureSession()
        
        guard let input = try? AVCaptureDeviceInput(device: device),
              SCContext.captureSession.canAddInput(input) else {
            print("Failed to set up camera")
            SCContext.requestCameraPermission()
            return
        }
        SCContext.captureSession.addInput(input)
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: .global())
        
        if SCContext.captureSession.canAddOutput(videoOutput) {
            SCContext.captureSession.addOutput(videoOutput)
        }
        
        SCContext.captureSession.startRunning()
        DispatchQueue.main.async { self.startCameraOverlayer() }
    }
    
    func closeCamera() {
        if SCContext.isCameraRunning() {
            //SCContext.previewType = nil
            if camWindow.isVisible { camWindow.close() }
            SCContext.captureSession.stopRunning()
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        /* 保留后续以作他用
        if !SCContext.isPaused && ud.string(forKey: "recordCam") != "" {
            if sampleBuffer.isValid { SCContext.isCameraReady = true }
            if sampleBuffer.imageBuffer != nil { SCContext.frameCache = sampleBuffer }
        }*/
    }
}

class AVOutputClass: NSObject, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = AVOutputClass()
    var output: AVCaptureMovieFileOutput!
    var dataOutput: AVCaptureVideoDataOutput!
    //var captureSession: AVCaptureSession!
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //print(sampleBuffer.nsImage?.size)
    }
    
    public func startRecording(with device: AVCaptureDevice, mute: Bool = false, preset: AVCaptureSession.Preset = .high, didOutput: Bool = true) {
        output = AVCaptureMovieFileOutput()
        dataOutput = AVCaptureVideoDataOutput()
        dataOutput.setSampleBufferDelegate(self, queue: .global())
        SCContext.captureSession = AVCaptureSession()
        SCContext.previewSession = AVCaptureSession()
        SCContext.captureSession.sessionPreset = preset
        SCContext.previewSession.sessionPreset = preset
        
        guard let input = try? AVCaptureDeviceInput(device: device),
              let preview = try? AVCaptureDeviceInput(device: device),
              SCContext.captureSession.canAddInput(input),
              SCContext.previewSession.canAddInput(preview),
              SCContext.captureSession.canAddOutput(output),
              SCContext.previewSession.canAddOutput(dataOutput) else {
            print("Failed to set up camera or device")
            SCContext.requestCameraPermission()
            return
        }

        let recordingRequest: RecordingRequest?
        if didOutput {
            recordingRequest = RecordingPreferencesStore().makeRequest(mode: .idevice)
            guard let recordingRequest, AppDelegate.shared.recordingSession.prepare(recordingRequest) else {
                return
            }
        } else {
            recordingRequest = nil
        }
        
        SCContext.captureSession.addInput(input)
        SCContext.captureSession.addOutput(output)
        SCContext.previewSession.addInput(preview)
        SCContext.previewSession.addOutput(dataOutput)
        
        if mute {
            if let audioConnection = output.connection(with: .audio) {
                SCContext.captureSession.removeConnection(audioConnection)
                /*DispatchQueue.main.async {
                    let alert = createAlert(title: "No Audio Connection",
                                                               message: "Unable to get audio stream on this device, only screen content will be recorded!",
                                                               button1: "OK")
                    alert.runModal()
                }*/
            }
        }
        
        if didOutput {
            guard let recordingRequest else {
                AppDelegate.shared.recordingSession.fail("iDevice recording request is unavailable.")
                return
            }
            let encoderIsH265 = recordingRequest.settings.encoder == .h265
            let videoSettings: [String: Any] = [ AVVideoCodecKey: encoderIsH265 ? AVVideoCodecType.hevc : AVVideoCodecType.h264 ]
            guard let connection = output.connection(with: .video) else {
                AppDelegate.shared.recordingSession.fail("iDevice video connection is unavailable.")
                return
            }
            output.setOutputSettings(videoSettings, for: connection)
            let fileEnding = recordingRequest.settings.videoFormat.rawValue
            SCContext.filePath = "\(SCContext.getFilePath()).\(fileEnding)"
            SCContext.captureSession.startRunning()
            output.startRecording(to: SCContext.filePath.url, recordingDelegate: self)
            SCContext.streamType = StreamType.idevice
            SCContext.startTime = Date.now
            AppDelegate.shared.recordingSession.markStarted()
        }
        
        SCContext.previewSession.startRunning()
        DispatchQueue.main.async {
            closeAllWindow(except: "Area Overlayer".local)
            updateStatusBar()
            AppDelegate.shared.startDeviceOverlayer(size: NSSize(width: 300, height: 500))
        }
    }

    public func stopRecording(completion: (() -> Void)? = nil) {
        guard AppDelegate.shared.recordingSession.beginStopping(completion: completion) else { return }
        if SCContext.captureSession.isRunning, output.isRecording {
            output.stopRecording()
            AppDelegate.shared.recordingSession.beginFinalizing()
            SCContext.captureSession.stopRunning()
            SCContext.previewSession.stopRunning()
            DispatchQueue.main.async {
                controlPanel.close()
                deviceWindow.close()
                updateStatusBar()
            }
        } else {
            AppDelegate.shared.recordingSession.beginFinalizing()
            SCContext.completeFinalization(
                .failure(
                    RecordingFailure(
                        stage: .deviceCapture,
                        message: "iDevice recording output is not active.",
                        retainedURL: SCContext.filePath?.url
                    )
                )
            )
        }
    }
    
    func closePreview() {
        if SCContext.isCameraRunning() {
            //SCContext.previewType = nil
            if deviceWindow.isVisible { deviceWindow.close() }
            if let preview = SCContext.previewSession { preview.stopRunning() }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        _ = AppDelegate.shared.recordingSession.beginStopping()
        guard AppDelegate.shared.recordingSession.beginFinalizing() else { return }
        let finishedSuccessfully: Bool
        if let error = error as NSError? {
            finishedSuccessfully = error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
        } else {
            finishedSuccessfully = true
        }
        let outcome: FinalizationOutcome
        if finishedSuccessfully {
            outcome = .success(
                RecordingArtifact(kind: .video, production: .deviceCapture, url: outputFileURL)
            )
        } else {
            outcome = .failure(
                RecordingFailure(
                    stage: .deviceCapture,
                    message: error?.localizedDescription ?? "iDevice recording failed.",
                    retainedURL: outputFileURL
                )
            )
        }
        DispatchQueue.main.async {
            SCContext.streamType = nil
            SCContext.startTime = nil
            SCContext.completeFinalization(outcome)
            updateStatusBar()
        }
    }
}
