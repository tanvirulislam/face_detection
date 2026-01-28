let faceDetection;

async function initFaceDetector() {
    if (faceDetection) return;

    faceDetection = new FaceDetection({
        locateFile: (file) =>
            `https://cdn.jsdelivr.net/npm/@mediapipe/face_detection/${file}`,
    });

    faceDetection.setOptions({
        model: "short",
        minDetectionConfidence: 0.7,
    });
}

async function detectFaceFromImage(base64Image) {
    await initFaceDetector();

    return new Promise((resolve) => {
        const img = new Image();
        img.src = "data:image/jpeg;base64," + base64Image;

        img.onload = async () => {
            let resultData = {
                faceCount: 0,
                yaw: 0,
                leftEyeOpen: 1.0,
                rightEyeOpen: 1.0,
            };

            faceDetection.onResults((results) => {
                const detections = results.detections || [];
                resultData.faceCount = detections.length;

                if (detections.length === 1) {
                    const kp = detections[0].keypoints;

                    const leftEye = kp[0];
                    const rightEye = kp[1];
                    const nose = kp[2];

                    // simple yaw estimation
                    resultData.yaw = (nose.x - (leftEye.x + rightEye.x) / 2) * 100;
                }

                resolve(JSON.stringify(resultData));
            });

            await faceDetection.send({ image: img });
        };
    });
}
