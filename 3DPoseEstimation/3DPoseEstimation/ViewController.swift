import UIKit
import AVFoundation

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    @IBOutlet weak var projectName: UILabel!
    @IBOutlet weak var statusLabel: UILabel! // 상태 메시지를 표시하는 UILabel 추가

    var captureSession: AVCaptureSession?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var isProcessingFrame = false
    var isDetectionActive = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCameraSession()
    }

    func setupCameraSession() {
        captureSession = AVCaptureSession()
        guard let captureSession = captureSession else { return }

        guard let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("후방 카메라를 찾을 수 없습니다.")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: backCamera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            print("카메라 입력 설정 오류: \(error.localizedDescription)")
            return
        }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
        }

        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        if let videoPreviewLayer = videoPreviewLayer {
            videoPreviewLayer.videoGravity = .resizeAspectFill
            videoPreviewLayer.frame = view.layer.bounds
            view.layer.insertSublayer(videoPreviewLayer, at: 0)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }
    }

    @IBAction func startDetection(_ sender: UIButton) {
        print("Detection started")
        isDetectionActive = true
        isProcessingFrame = false
    }

    @IBAction func exitDetection(_ sender: UIButton) {
        print("Detection stopped")
        isDetectionActive = false
        isProcessingFrame = true

        if let imageView = view.viewWithTag(101) {
            imageView.removeFromSuperview()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if isProcessingFrame || !isDetectionActive { return }

        isProcessingFrame = true

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isProcessingFrame = false
            return
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let uiImage = UIImage(ciImage: ciImage).fixedOrientation()

        guard let jpegData = uiImage.jpegData(compressionQuality: 0.8) else {
            isProcessingFrame = false
            return
        }

        sendImageToServer(imageData: jpegData) {
            self.isProcessingFrame = false
        }
    }

    func sendImageToServer(imageData: Data, completion: @escaping () -> Void) {
        let urlString = "http://192.168.45.26:8000/process-frame/"
        guard let url = URL(string: urlString) else {
            print("잘못된 서버 URL입니다.")
            completion()
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"frame.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { completion() }
            if let error = error {
                print("서버 요청 오류: \(error.localizedDescription)")
                return
            }

            guard let data = data,
                  let jsonResponse = try? JSONSerialization.jsonObject(with: data, options: []),
                  let jsonDict = jsonResponse as? [String: Any],
                  let imageHex = jsonDict["image"] as? String,
                  let analysis = jsonDict["analysis"] as? [[String: String]],
                  let imageData = Data(hexString: imageHex) else {
                print("서버 응답 처리 실패")
                return
            }

            DispatchQueue.main.async {
                self.updateUI(imageData: imageData, analysis: analysis)
            }
        }
        task.resume()
    }

    func updateUI(imageData: Data, analysis: [[String: String]]) {
        if let imageView = view.viewWithTag(101) {
            imageView.removeFromSuperview()
        }

        guard let skeletonImage = UIImage(data: imageData) else {
            print("수신된 데이터를 이미지로 변환하는 데 실패했습니다.")
            return
        }

        let imageView = UIImageView(image: skeletonImage)
        imageView.contentMode = .scaleAspectFill
        imageView.tag = 101
        imageView.clipsToBounds = true
        imageView.frame = view.bounds
        view.addSubview(imageView)

        view.bringSubviewToFront(projectName)

        // 버튼과 레이블을 최상단으로 가져오기

        view.bringSubviewToFront(statusLabel)
        if let startButton = view.viewWithTag(201) {
            view.bringSubviewToFront(startButton) // startDetection 버튼 앞으로 가져오기
        }
        if let stopButton = view.viewWithTag(202) {
            view.bringSubviewToFront(stopButton) // exitDetection 버튼 앞으로 가져오기
        }

        statusLabel.numberOfLines = 0
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.textAlignment = .center // 필요에 따라 변경

        // 분석 결과 업데이트
        var statusText = ""
        for result in analysis {
            if let overallStatus = result["overall_status"] {
                statusText += "\(overallStatus)\n"
            }
        }
        statusLabel.text = statusText
    }
}

// Hex 문자열을 Data로 변환
extension Data {
    init?(hexString: String) {
        var data = Data()
        var temp = ""
        for char in hexString {
            temp.append(char)
            if temp.count == 2 {
                if let byte = UInt8(temp, radix: 16) {
                    data.append(byte)
                }
                temp = ""
            }
        }
        self = data
    }
}

// UIImage 방향 수정 확장
extension UIImage {
    func fixedOrientation() -> UIImage {
        if imageOrientation == .up {
            return self
        }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return normalizedImage
    }
}
