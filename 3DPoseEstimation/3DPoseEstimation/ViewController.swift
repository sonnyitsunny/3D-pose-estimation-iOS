import UIKit
import AVFoundation

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    @IBOutlet weak var projectName: UILabel!

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

        // 연결의 방향 설정
        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
        }

        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        if let videoPreviewLayer = videoPreviewLayer {
            videoPreviewLayer.videoGravity = .resizeAspectFill
            videoPreviewLayer.frame = view.layer.bounds
            view.layer.insertSublayer(videoPreviewLayer, at: 0)
        }

        // `startRunning`을 백그라운드 스레드에서 실행
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
        let uiImage = UIImage(ciImage: ciImage).fixedOrientation() // 이미지 회전 수정

        guard let jpegData = uiImage.jpegData(compressionQuality: 0.8) else {
            isProcessingFrame = false
            return
        }

        sendImageToServer(imageData: jpegData) {
            self.isProcessingFrame = false
        }
    }

    func sendImageToServer(imageData: Data, completion: @escaping () -> Void) {
        let urlString = "http://192.168.0.2:8000/process-frame/"
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

            guard let data = data else {
                print("서버에서 데이터가 반환되지 않았습니다.")
                return
            }

            DispatchQueue.main.async {
                self.displaySkeletonImage(imageData: data)
            }
        }
        task.resume()
    }

    func displaySkeletonImage(imageData: Data) {
        if let imageView = view.viewWithTag(101) {
            imageView.removeFromSuperview()
        }

        guard let skeletonImage = UIImage(data: imageData) else {
            print("수신된 데이터를 이미지로 변환하는 데 실패했습니다.")
            return
        }

        let imageView = UIImageView(image: skeletonImage)
        imageView.contentMode = .scaleAspectFill // 화면을 완전히 채우도록 설정
        imageView.tag = 101
        imageView.clipsToBounds = true // 이미지가 화면 경계를 넘지 않도록 자르기
        // 화면 전체 크기에 맞게 설정
        imageView.frame = view.bounds
        view.addSubview(imageView)

        // 버튼과 레이블을 최상단으로 가져오기
        view.bringSubviewToFront(projectName)
        if let startButton = view.viewWithTag(201) {
            view.bringSubviewToFront(startButton) // startDetection 버튼 앞으로 가져오기
        }
        if let stopButton = view.viewWithTag(202) {
            view.bringSubviewToFront(stopButton) // exitDetection 버튼 앞으로 가져오기
        }


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
