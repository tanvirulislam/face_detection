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
                leftEyeOpen: 0,
                rightEyeOpen: 0,
            };

            faceDetection.onResults((results) => {
                const detections = results.detections || [];
                resultData.faceCount = detections.length;

                if (detections.length === 1) {
                    const box = detections[0].boundingBox;
                    const imgCenterX = img.width / 2;
                    const faceCenterX = box.xCenter * img.width;

                    // 👉 simple yaw approximation
                    resultData.yaw = (faceCenterX - imgCenterX) / imgCenterX * 30;
                }

                resolve(JSON.stringify(resultData)); // 🔥 MUST stringify
            });

            await faceDetection.send({ image: img });
        };
    });
}


// let faceDetection;

// async function initFaceDetector() {
//     if (faceDetection) return;

//     faceDetection = new FaceDetection({
//         locateFile: (file) =>
//             `https://cdn.jsdelivr.net/npm/@mediapipe/face_detection/${file}`,
//     });

//     faceDetection.setOptions({
//         model: "short",
//         minDetectionConfidence: 0.7,
//     });
// }

// async function detectFaceFromImage(base64Image) {
//     await initFaceDetector();

//     return new Promise((resolve) => {
//         const img = new Image();
//         img.src = "data:image/jpeg;base64," + base64Image;

//         img.onload = async () => {
//             let resultData = {
//                 faceCount: 0,
//                 yaw: 0,
//                 leftEyeOpen: 1.0,
//                 rightEyeOpen: 1.0,
//             };

//             faceDetection.onResults((results) => {
//                 const detections = results.detections || [];
//                 resultData.faceCount = detections.length;

//                 if (detections.length === 1) {
//                     const kp = detections[0].keypoints;
//                     const leftEye = kp[0];
//                     const rightEye = kp[1];
//                     const nose = kp[2];

//                     resultData.yaw =
//                         (nose.x - (leftEye.x + rightEye.x) / 2) * 100;
//                 }

//                 // 🔥 RETURN STRING, NOT OBJECT
//                 resolve(JSON.stringify(resultData));
//             });

//             await faceDetection.send({ image: img });
//         };
//     });
// }
