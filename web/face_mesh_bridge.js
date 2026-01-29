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


window.detectFaceFromImage = async function (base64Image) {
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
                    leftEyeOpen: 1,
                    rightEyeOpen: 1,
                };

                if (!results.multiFaceLandmarks || results.multiFaceLandmarks.length === 0) {
                    resolve(JSON.stringify(resultData));
                    return;
                }

                resultData.faceCount = 1;

                const lm = results.multiFaceLandmarks[0];

                // landmarks
                const nose = lm[1];
                const leftCheek = lm[234];
                const rightCheek = lm[454];

                const faceCenterX = (leftCheek.x + rightCheek.x) / 2;

                // ✅ Proper yaw (now works for left/right)
                resultData.yaw = (nose.x - faceCenterX) * 60;

                resolve(JSON.stringify(resultData));
            });

            await faceMesh.send({ image: img });
        };

        // ⛑️ fallback safety (if FaceMesh fails)
        setTimeout(() => {
            if (!resolved) {
                resolved = true;
                resolve(
                    JSON.stringify({
                        faceCount: 0,
                        yaw: 0,
                        leftEyeOpen: 1,
                        rightEyeOpen: 1,
                    })
                );
            }
        }, 800);
    });
};
