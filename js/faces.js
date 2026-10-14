// Face landmarks for the face lenses.
//
// iOS Safari has no Vision framework and no FaceDetector API, so this pulls in
// MediaPipe's face landmarker on demand — the first time you select a face lens,
// not at startup. It is a few megabytes, so it is lazy, cached by the service
// worker after the first successful load, and entirely optional: if it fails
// (offline on first use, CDN blocked, unsupported device) the face lenses are
// simply hidden and the rest of the app is unaffected.

const VISION_VERSION = '0.10.14';
const VISION_MODULE = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${VISION_VERSION}/vision_bundle.mjs`;
const VISION_WASM = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${VISION_VERSION}/wasm`;
const MODEL =
  'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task';

// Landmark indices in MediaPipe's 478-point mesh.
const RIGHT_EYE = [33, 133, 159, 145];
const LEFT_EYE = [362, 263, 386, 374];
const NOSE_TIP = 1;
const MOUTH = 13;

export class FaceTracker {
  constructor() {
    this.landmarker = null;
    this.state = 'idle'; // idle | loading | ready | unavailable
    this.error = null;
    this.faces = [];
    this.frame = 0;
    this.lastTimestamp = -1;
  }

  get available() {
    return this.state === 'ready';
  }

  /** Loads the model. Safe to call repeatedly; only the first call does work. */
  async load() {
    if (this.state === 'ready' || this.state === 'loading') return this.state === 'ready';
    this.state = 'loading';
    try {
      const vision = await import(/* @vite-ignore */ VISION_MODULE);
      const fileset = await vision.FilesetResolver.forVisionTasks(VISION_WASM);
      this.landmarker = await vision.FaceLandmarker.createFromOptions(fileset, {
        baseOptions: { modelAssetPath: MODEL, delegate: 'GPU' },
        runningMode: 'VIDEO',
        numFaces: 1,
        outputFaceBlendshapes: false,
        outputFacialTransformationMatrixes: false
      });
      this.state = 'ready';
      return true;
    } catch (error) {
      this.error = error;
      this.state = 'unavailable';
      console.warn('Face tracking unavailable', error);
      return false;
    }
  }

  reset() {
    this.faces = [];
    this.frame = 0;
  }

  /**
   * Landmarks for the current video frame, in the video's own 0..1 space.
   * Detection runs every other frame and the previous result is reused between,
   * which is invisible at 30fps and roughly halves the cost.
   */
  detect(video, timestampMs) {
    if (!this.available || !video || video.readyState < 2) return this.faces;
    if (this.frame++ % 2 !== 0) return this.faces;

    // MediaPipe rejects a timestamp that does not move forward.
    const stamp = timestampMs <= this.lastTimestamp ? this.lastTimestamp + 1 : timestampMs;
    this.lastTimestamp = stamp;

    let result;
    try {
      result = this.landmarker.detectForVideo(video, stamp);
    } catch {
      return this.faces;
    }

    const meshes = result?.faceLandmarks ?? [];
    this.faces = meshes.map((points) => summarise(points)).filter(Boolean);
    return this.faces;
  }
}

function centroid(points, indices) {
  let x = 0;
  let y = 0;
  for (const index of indices) {
    const point = points[index];
    if (!point) return null;
    x += point.x;
    y += point.y;
  }
  return { x: x / indices.length, y: y / indices.length };
}

function summarise(points) {
  const leftEye = centroid(points, LEFT_EYE);
  const rightEye = centroid(points, RIGHT_EYE);
  if (!leftEye || !rightEye) return null;

  let minX = 1;
  let minY = 1;
  let maxX = 0;
  let maxY = 0;
  for (const point of points) {
    if (point.x < minX) minX = point.x;
    if (point.x > maxX) maxX = point.x;
    if (point.y < minY) minY = point.y;
    if (point.y > maxY) maxY = point.y;
  }

  return {
    leftEye,
    rightEye,
    nose: points[NOSE_TIP] ? { x: points[NOSE_TIP].x, y: points[NOSE_TIP].y } : null,
    mouth: points[MOUTH] ? { x: points[MOUTH].x, y: points[MOUTH].y } : null,
    centre: { x: (minX + maxX) / 2, y: (minY + maxY) / 2 },
    radius: Math.max(maxX - minX, (maxY - minY) * 0.6) / 2,
    box: { x: minX, y: minY, w: maxX - minX, h: maxY - minY }
  };
}
