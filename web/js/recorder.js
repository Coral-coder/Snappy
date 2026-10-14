// Video recording off the same canvas the viewfinder draws, so a clip gets
// exactly the filter you were looking at.
//
// Safari only learned canvas.captureStream + MediaRecorder relatively recently,
// and the container it produces differs by version, so everything here is
// feature-detected and the UI hides recording when it is not supported.

const CANDIDATE_TYPES = [
  'video/mp4;codecs=avc1.42E01E,mp4a.40.2',
  'video/mp4;codecs=avc1',
  'video/mp4',
  'video/webm;codecs=vp9,opus',
  'video/webm;codecs=vp8,opus',
  'video/webm'
];

export function pickMimeType() {
  if (typeof MediaRecorder === 'undefined') return null;
  if (!MediaRecorder.isTypeSupported) return 'video/webm';
  return CANDIDATE_TYPES.find((type) => MediaRecorder.isTypeSupported(type)) ?? null;
}

export function recordingSupported(canvas) {
  return Boolean(
    typeof MediaRecorder !== 'undefined' &&
    typeof canvas.captureStream === 'function' &&
    pickMimeType()
  );
}

export class CanvasRecorder {
  constructor(canvas, { fps = 30 } = {}) {
    this.canvas = canvas;
    this.fps = fps;
    this.recorder = null;
    this.chunks = [];
    this.stream = null;
    this.startedAt = 0;
  }

  get recording() {
    return this.recorder?.state === 'recording';
  }

  get seconds() {
    return this.recording ? (performance.now() - this.startedAt) / 1000 : 0;
  }

  start(audioTrack) {
    if (this.recording) return;
    const mimeType = pickMimeType();
    if (!mimeType) throw new Error('This browser cannot record video');

    this.stream = this.canvas.captureStream(this.fps);
    if (audioTrack) this.stream.addTrack(audioTrack);

    this.chunks = [];
    this.recorder = new MediaRecorder(this.stream, { mimeType, videoBitsPerSecond: 8_000_000 });
    this.recorder.ondataavailable = (event) => {
      if (event.data && event.data.size) this.chunks.push(event.data);
    };
    this.recorder.start(250);
    this.startedAt = performance.now();
  }

  /** Resolves with the finished clip, or null if nothing was captured. */
  stop() {
    return new Promise((resolve) => {
      const recorder = this.recorder;
      if (!recorder || recorder.state === 'inactive') {
        resolve(null);
        return;
      }
      recorder.onstop = () => {
        const mime = recorder.mimeType || 'video/mp4';
        const blob = this.chunks.length ? new Blob(this.chunks, { type: mime }) : null;
        this.chunks = [];
        // Only the canvas track is ours to stop; the mic belongs to the camera.
        this.stream?.getVideoTracks().forEach((track) => track.stop());
        this.stream = null;
        this.recorder = null;
        resolve(blob ? { blob, mime } : null);
      };
      recorder.stop();
    });
  }
}
