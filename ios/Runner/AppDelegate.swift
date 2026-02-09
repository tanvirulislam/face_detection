import UIKit
import Flutter
import MLKitFaceDetection
import MLKitVision

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.example.face_detection/face_validator",
      binaryMessenger: controller.binaryMessenger
    )
    
    channel.setMethodCallHandler { [weak self] (call, result) in
      if call.method == "analyzeFace" {
        self?.analyzeFace(call: call, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  private func analyzeFace(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let imagePath = args["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Path required", details: nil))
        return
    }

    guard let rawImage = UIImage(contentsOfFile: imagePath) else {
        result(FlutterError(code: "IMAGE_LOAD_ERROR", message: "Failed to load image", details: nil))
        return
    }

    // 🔥 Fix orientation by redrawing
    UIGraphicsBeginImageContextWithOptions(rawImage.size, false, rawImage.scale)
    rawImage.draw(in: CGRect(origin: .zero, size: rawImage.size))
    let finalImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    guard let imageToProcess = finalImage else {
        result(FlutterError(code: "NORMALIZE_ERROR", message: "Normalization failed", details: nil))
        return
    }

    let visionImage = VisionImage(image: imageToProcess)
    visionImage.orientation = .up

    let options = FaceDetectorOptions()
    options.performanceMode = .accurate 
    options.landmarkMode = .all
    options.classificationMode = .all
    
    let faceDetector = FaceDetector.faceDetector(options: options)

    faceDetector.process(visionImage) { faces, error in
        if let error = error {
            result(FlutterError(code: "DETECTION_ERROR", message: error.localizedDescription, details: nil))
            return
        }

        guard let faces = faces, !faces.isEmpty else {
            result(["faceCount": 0, "yaw": 0.0, "leftEyeOpen": 0.0, "rightEyeOpen": 0.0])
            return
        }

        let face = faces[0]

        // 🕵️‍♂️ LANDMARK CHECK: Ensure nose and mouth are actually visible
        let nose = face.landmark(ofType: .noseBase)
        let mouthL = face.landmark(ofType: .mouthLeft)
        let mouthR = face.landmark(ofType: .mouthRight)
        
        // If these are nil, the face is only partially in the frame
        let isFullFace = (nose != nil && mouthL != nil && mouthR != nil)

        result([
            "faceCount": faces.count,
            "isFullFace": isFullFace,
            "yaw": face.headEulerAngleY,
            "pitch": face.headEulerAngleX,
            "roll": face.headEulerAngleZ,
            "leftEyeOpen": face.leftEyeOpenProbability,
            "rightEyeOpen": face.rightEyeOpenProbability
        ])
    }
  }
}