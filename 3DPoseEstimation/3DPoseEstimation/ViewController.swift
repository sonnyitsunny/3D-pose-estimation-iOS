//
//  ViewController.swift
//  3DPoseEstimation
//
//  Created by 손동현 on 10/15/24.
//

import UIKit
import AVFoundation

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    var captureSession: AVCaptureSession?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?

    @IBOutlet weak var projectName: UILabel!

    @IBAction func exitDetection(_ sender: UIButton) {
        print("종료")
        captureSession?.stopRunning()

        // 카메라 미리보기 레이어를 뷰에서 제거
        videoPreviewLayer?.removeFromSuperlayer()

    }



    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    @IBAction func startDetection(_ sender: UIButton) {
        print("시작 버튼 누름")
        captureSession?.startRunning()

        
    }

    func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .high

        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("후방 카메라를 찾을 수 없습니다.")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: backCamera)
            captureSession?.addInput(input)

            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            captureSession?.addOutput(videoOutput)

            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
            videoPreviewLayer?.videoGravity = .resizeAspectFill

            // 화면 가운데에 작은 사각형을 지정
            let previewWidth: CGFloat = 300 // 원하는 너비
            let previewHeight: CGFloat = 300 // 원하는 높이
            let xPos = (view.bounds.width - previewWidth) / 2
            let yPos = (view.bounds.height - previewHeight) / 2

            // 가운데에 위치하도록 레이어 크기 조정
            videoPreviewLayer?.frame = CGRect(x: xPos, y: yPos, width: previewWidth, height: previewHeight)

            view.layer.insertSublayer(videoPreviewLayer!, at: 0)



        } catch {
            print("카메라 설정 중 오류 발생: \(error)")
        }
    }

    // AVCaptureVideoDataOutputSampleBufferDelegate 메서드
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 실시간 프레임 처리
    }
}

