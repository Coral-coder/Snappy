// The frame pipeline.
//
// One rule, same as the native build: what you see is what gets saved. The video
// frame goes through the lens shader into a WebGL canvas, that canvas is blitted
// into the visible 2D canvas, and face overlays are drawn on top. Photos and
// recordings come from that same visible canvas, so the preview cannot lie.
//
// Preview renders at screen resolution. Capture re-renders the identical pipeline
// at the camera's full resolution, so a saved photo is not limited by the display.

import { PRELUDE } from './filters.js';
import { drawOverlay } from './overlays.js';

const VERTEX_SHADER = `
attribute vec2 a_pos;
varying vec2 v_uv;
uniform vec2 u_crop;
uniform float u_zoom;
uniform float u_mirror;
void main() {
  vec2 s = a_pos * 0.5 + 0.5;
  vec2 d = vec2(s.x, 1.0 - s.y);
  if (u_mirror > 0.5) d.x = 1.0 - d.x;
  v_uv = (d - 0.5) * u_crop / u_zoom + 0.5;
  gl_Position = vec4(a_pos, 0.0, 1.0);
}`;

export class Renderer {
  constructor(outputCanvas) {
    this.output = outputCanvas;
    this.ctx2d = outputCanvas.getContext('2d', { alpha: false, desynchronized: true });

    this.glCanvas = document.createElement('canvas');
    const attrs = { alpha: false, antialias: false, depth: false, stencil: false, preserveDrawingBuffer: false };
    this.gl = this.glCanvas.getContext('webgl', attrs) || this.glCanvas.getContext('experimental-webgl', attrs);
    if (!this.gl) throw new Error('WebGL is unavailable');

    this.programs = new Map();
    this.filter = null;
    this.zoom = 1;
    this.mirror = false;
    this.faces = [];
    this.start = performance.now();
    this.crop = [1, 1];

    this.#setupGeometry();
    this.#setupTexture();
  }

  #setupGeometry() {
    const gl = this.gl;
    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
    this.buffer = buffer;
  }

  #setupTexture() {
    const gl = this.gl;
    this.texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, this.texture);
    // Camera frames are never power-of-two, so clamp and skip mipmaps.
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  }

  /** Compiles a lens the first time it is selected, then caches it. */
  #program(filter) {
    if (this.programs.has(filter.id)) return this.programs.get(filter.id);
    const gl = this.gl;

    const compile = (type, source) => {
      const shader = gl.createShader(type);
      gl.shaderSource(shader, source);
      gl.compileShader(shader);
      if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        const log = gl.getShaderInfoLog(shader);
        gl.deleteShader(shader);
        throw new Error(`${filter.id}: ${log}`);
      }
      return shader;
    };

    const fragment = `${PRELUDE}\n${filter.body}\nvoid main() { gl_FragColor = vec4(snappy(v_uv), 1.0); }`;
    const program = gl.createProgram();
    gl.attachShader(program, compile(gl.VERTEX_SHADER, VERTEX_SHADER));
    gl.attachShader(program, compile(gl.FRAGMENT_SHADER, fragment));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      throw new Error(`${filter.id}: ${gl.getProgramInfoLog(program)}`);
    }

    const entry = {
      program,
      attrib: gl.getAttribLocation(program, 'a_pos'),
      uniforms: Object.fromEntries(
        ['u_tex', 'u_res', 'u_time', 'u_aspect', 'u_hasFace', 'u_eyeL', 'u_eyeR', 'u_faceC', 'u_faceR',
         'u_crop', 'u_zoom', 'u_mirror'].map((name) => [name, gl.getUniformLocation(program, name)])
      )
    };
    this.programs.set(filter.id, entry);
    return entry;
  }

  setFilter(filter) {
    try {
      this.#program(filter);
      this.filter = filter;
      return true;
    } catch (error) {
      // A lens that will not compile is dropped rather than taking the app down.
      console.warn('Lens failed to compile', error);
      return false;
    }
  }

  /** Screen position (CSS pixels) of a point in the video's own 0..1 space. */
  mapToScreen(point, width, height) {
    const [cx, cy] = this.crop;
    let x = (point.x - 0.5) * this.zoom / cx + 0.5;
    const y = (point.y - 0.5) * this.zoom / cy + 0.5;
    if (this.mirror) x = 1 - x;
    return { x: x * width, y: y * height };
  }

  /**
   * Renders one frame through the identical pipeline into a detached canvas, so
   * a photo can be taken at the camera's full resolution without the viewfinder
   * flickering through a resize.
   */
  captureFrame(video, width, height) {
    const target = document.createElement('canvas');
    target.width = width;
    target.height = height;

    const previousOutput = this.output;
    const previousCtx = this.ctx2d;
    this.output = target;
    this.ctx2d = target.getContext('2d', { alpha: false });
    try {
      this.draw(video, width, height);
    } finally {
      this.output = previousOutput;
      this.ctx2d = previousCtx;
    }
    return target;
  }

  /** Renders one frame of `video` at `width` x `height` into the output canvas. */
  draw(video, width, height, { overlayScale = 1 } = {}) {
    if (!this.filter || !video || video.readyState < 2) return;
    const vw = video.videoWidth;
    const vh = video.videoHeight;
    if (!vw || !vh) return;

    const gl = this.gl;
    if (this.glCanvas.width !== width || this.glCanvas.height !== height) {
      this.glCanvas.width = width;
      this.glCanvas.height = height;
    }
    if (this.output.width !== width || this.output.height !== height) {
      this.output.width = width;
      this.output.height = height;
    }

    // Aspect-fill: crop the long edge of the frame rather than letterboxing it.
    const canvasAspect = width / height;
    const videoAspect = vw / vh;
    this.crop = canvasAspect < videoAspect
      ? [canvasAspect / videoAspect, 1]
      : [1, videoAspect / canvasAspect];

    gl.viewport(0, 0, width, height);
    gl.bindTexture(gl.TEXTURE_2D, this.texture);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, video);

    const { program, attrib, uniforms } = this.#program(this.filter);
    gl.useProgram(program);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
    gl.enableVertexAttribArray(attrib);
    gl.vertexAttribPointer(attrib, 2, gl.FLOAT, false, 0, 0);

    const face = this.faces[0];
    gl.uniform1i(uniforms.u_tex, 0);
    gl.uniform2f(uniforms.u_res, width, height);
    gl.uniform1f(uniforms.u_time, (performance.now() - this.start) / 1000);
    gl.uniform1f(uniforms.u_aspect, canvasAspect);
    gl.uniform1f(uniforms.u_hasFace, face ? 1 : 0);
    gl.uniform2f(uniforms.u_eyeL, face?.leftEye.x ?? 0.4, face?.leftEye.y ?? 0.4);
    gl.uniform2f(uniforms.u_eyeR, face?.rightEye.x ?? 0.6, face?.rightEye.y ?? 0.4);
    gl.uniform2f(uniforms.u_faceC, face?.centre.x ?? 0.5, face?.centre.y ?? 0.5);
    gl.uniform1f(uniforms.u_faceR, face?.radius ?? 0.25);
    gl.uniform2f(uniforms.u_crop, this.crop[0], this.crop[1]);
    gl.uniform1f(uniforms.u_zoom, this.zoom);
    gl.uniform1f(uniforms.u_mirror, this.mirror ? 1 : 0);

    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);

    this.ctx2d.drawImage(this.glCanvas, 0, 0, width, height);

    if (this.filter.overlay && this.faces.length) {
      for (const face of this.faces) {
        drawOverlay(this.ctx2d, this.filter.overlay, face, {
          map: (point) => this.mapToScreen(point, width, height),
          scale: overlayScale
        });
      }
    }
  }
}
