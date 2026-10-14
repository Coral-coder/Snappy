// getUserMedia wrangling.
//
// Audio is requested only when a recording starts, so the microphone prompt
// never appears just for opening the viewfinder.

export class Camera {
  constructor(video) {
    this.video = video;
    this.stream = null;
    this.audioStream = null;
    this.facing = 'user';
  }

  get mirrored() {
    return this.facing === 'user';
  }

  get settings() {
    return this.stream?.getVideoTracks()[0]?.getSettings?.() ?? {};
  }

  async start(facing = this.facing) {
    this.stop();
    this.facing = facing;

    const constraints = {
      audio: false,
      video: {
        facingMode: { ideal: facing },
        width: { ideal: 1920 },
        height: { ideal: 1080 },
        frameRate: { ideal: 30 }
      }
    };

    try {
      this.stream = await navigator.mediaDevices.getUserMedia(constraints);
    } catch (error) {
      if (error && (error.name === 'OverconstrainedError' || error.name === 'NotFoundError')) {
        // Some devices have no camera on the requested side; take whatever exists.
        this.stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
      } else {
        throw error;
      }
    }

    this.video.srcObject = this.stream;
    this.video.muted = true;
    this.video.playsInline = true;
    this.video.setAttribute('playsinline', '');
    await this.video.play();
    return this.stream;
  }

  async flip() {
    return this.start(this.facing === 'user' ? 'environment' : 'user');
  }

  /** Microphone track for a recording, or null if it is unavailable or refused. */
  async audioTrack() {
    if (this.audioStream) return this.audioStream.getAudioTracks()[0] ?? null;
    try {
      this.audioStream = await navigator.mediaDevices.getUserMedia({ audio: true });
      return this.audioStream.getAudioTracks()[0] ?? null;
    } catch {
      return null;
    }
  }

  releaseAudio() {
    this.audioStream?.getTracks().forEach((track) => track.stop());
    this.audioStream = null;
  }

  stop() {
    this.stream?.getTracks().forEach((track) => track.stop());
    this.stream = null;
    this.video.srcObject = null;
  }

  stopAll() {
    this.stop();
    this.releaseAudio();
  }
}

export function cameraSupported() {
  return Boolean(navigator.mediaDevices?.getUserMedia);
}

/** A page served over plain http (other than localhost) cannot open a camera. */
export function secureContextOK() {
  return window.isSecureContext;
}
