// VERSION 3.0 - Updated eye detection
console.log("🔥 FACE MESH BRIDGE LOADED - VERSION 3.0");

let faceMesh = null;

// ✅ Initialize FaceMesh (only once)
async function initFaceMesh() {
    if (faceMesh) return; // Already initialized

    faceMesh = new FaceMesh({
        locateFile: (file) => {
            return `https://cdn.jsdelivr.net/npm/@mediapipe/face_mesh/${file}`;
        }
    });

    faceMesh.setOptions({
        maxNumFaces: 1,
        refineLandmarks: true,
        minDetectionConfidence: 0.5,
        minTrackingConfidence: 0.5
    });

    await faceMesh.initialize();
}

// ✅ Calculate Eye Aspect Ratio (EAR) - Corrected
function calculateEAR(topLeft, topRight, bottomLeft, bottomRight, leftCorner, rightCorner) {
    // Vertical distances (height of eye)
    const v1 = Math.hypot(topLeft.x - bottomLeft.x, topLeft.y - bottomLeft.y);
    const v2 = Math.hypot(topRight.x - bottomRight.x, topRight.y - bottomRight.y);

    // Horizontal distance (width of eye)
    const h = Math.hypot(leftCorner.x - rightCorner.x, leftCorner.y - rightCorner.y);

    // Eye Aspect Ratio
    return (v1 + v2) / (2.0 * h);
}

window.detectFaceFromImage = async function (base64Image) {
    console.log("🎯 detectFaceFromImage called");
    await initFaceMesh();

    return new Promise((resolve) => {
        const img = new Image();
        img.src = "data:image/jpeg;base64," + base64Image;

        let resolved = false;

        img.onload = async () => {
            faceMesh.onResults((results) => {
                if (resolved) return;
                resolved = true;

                const resultData = {
                    faceCount: 0,
                    yaw: 0,
                    leftEyeOpen: 0,
                    rightEyeOpen: 0,
                    leftEyeEAR: 0,
                    rightEyeEAR: 0,
                    debugInfo: ""
                };

                if (!results.multiFaceLandmarks || results.multiFaceLandmarks.length === 0) {
                    resultData.debugInfo = "No face detected";
                    console.log("❌ No face detected");
                    resolve(JSON.stringify(resultData));
                    return;
                }

                resultData.faceCount = 1;

                const lm = results.multiFaceLandmarks[0];

                // landmarks for face orientation
                const nose = lm[1];
                const leftCheek = lm[234];
                const rightCheek = lm[454];

                const faceCenterX = (leftCheek.x + rightCheek.x) / 2;
                resultData.yaw = (nose.x - faceCenterX) * 60;
                // LEFT eye
                const leftEyeTop1 = lm[159];
                const leftEyeTop2 = lm[160];
                const leftEyeBottom1 = lm[145];
                const leftEyeBottom2 = lm[144];
                const leftEyeLeftCorner = lm[33];
                const leftEyeRightCorner = lm[133];

                // RIGHT eye
                const rightEyeTop1 = lm[386];
                const rightEyeTop2 = lm[385];
                const rightEyeBottom1 = lm[374];
                const rightEyeBottom2 = lm[373];
                const rightEyeLeftCorner = lm[362];
                const rightEyeRightCorner = lm[263];

                const leftEAR = calculateEAR(
                    leftEyeTop1, leftEyeTop2,
                    leftEyeBottom1, leftEyeBottom2,
                    leftEyeLeftCorner, leftEyeRightCorner
                );

                const rightEAR = calculateEAR(
                    rightEyeTop1, rightEyeTop2,
                    rightEyeBottom1, rightEyeBottom2,
                    rightEyeLeftCorner, rightEyeRightCorner
                );

                // ✅ Adjusted threshold - lower value means more sensitive to closure
                const EYE_CLOSED_THRESHOLD = 0.25;

                resultData.leftEyeOpen = leftEAR > EYE_CLOSED_THRESHOLD ? 1 : 0;
                resultData.rightEyeOpen = rightEAR > EYE_CLOSED_THRESHOLD ? 1 : 0;
                resultData.leftEyeEAR = parseFloat(leftEAR.toFixed(4));
                resultData.rightEyeEAR = parseFloat(rightEAR.toFixed(4));

                resolve(JSON.stringify(resultData));
            });

            await faceMesh.send({ image: img });
        };


    });
};