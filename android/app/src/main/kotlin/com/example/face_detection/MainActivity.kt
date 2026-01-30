// 🔁 UPDATE THIS IN YOUR PROJECT: must match your app's package name
package com.example.face_detection

import android.net.Uri
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceContour
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.face.FaceLandmark
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    // 🔁 UPDATE THIS IN YOUR PROJECT: use your own unique channel name
    private val CHANNEL = "com.example.face_detection/face_validator"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->

            when (call.method) {
                // 🔁 UPDATE THIS IN YOUR PROJECT: method name must match Flutter side
                "analyzeFace" -> {
                    val path = call.argument<String>("path")

                    if (path.isNullOrEmpty()) {
                        result.error(
                            "INVALID_PATH",
                            "Image path is null or empty",
                            null,
                        )
                        return@setMethodCallHandler
                    }

                    analyzeFace(path, result)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    // 🔁 REUSABLE FUNCTION: works for any project using ML Kit Face Detection
    private fun analyzeFace(
        path: String,
        result: MethodChannel.Result,
    ) {
        try {
            // 🔁 Works with image file path from Flutter
            val image =
                InputImage.fromFilePath(
                    this,
                    Uri.fromFile(File(path)),
                )

            // 🔁 ML Kit Face Detector configuration
            val options =
                FaceDetectorOptions
                    .Builder()
                    .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
                    .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
                    .setContourMode(FaceDetectorOptions.CONTOUR_MODE_ALL) // 🔥 REQUIRED
                    .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
                    .setMinFaceSize(0.15f)
                    .enableTracking()
                    .build()

            val detector = FaceDetection.getClient(options)

            detector
                .process(image)
                .addOnSuccessListener { faces ->
                    val response = HashMap<String, Any>()

                    // 🔁 Face count validation
                    response["faceCount"] = faces.size

                    if (faces.isNotEmpty()) {
                        val face = faces[0]

                    // 🔁 Face bounding box (for cropping)
                        val box = face.boundingBox
                        response["faceBox"] = mapOf(
                            "left" to box.left,
                            "top" to box.top,
                            "right" to box.right,
                            "bottom" to box.bottom
                        )

                        // 🔁 Head rotation
                        response["yaw"] = face.headEulerAngleY

                        // 🔁 Eye visibility
                        response["leftEyeOpen"] = face.leftEyeOpenProbability ?: -1.0
                        response["rightEyeOpen"] = face.rightEyeOpenProbability ?: -1.0
                    }

                    detector.close()
                    result.success(response)
                }.addOnFailureListener { e ->
                    detector.close()
                    result.error(
                        "DETECTION_FAILED",
                        e.message,
                        null,
                    )
                }
        } catch (e: Exception) {
            result.error(
                "IMAGE_ERROR",
                e.message,
                null,
            )
        }
    }
}
