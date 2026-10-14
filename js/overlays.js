// Vector art for the face lenses, drawn with Canvas 2D on top of the filtered
// frame. Everything is sized against the distance between the eyes, so a lens
// sits correctly whether the face is close to the camera or across the room, and
// scales cleanly when a capture renders at full camera resolution.

const BROWN = '#6b4529';
const BROWN_INNER = '#d99e85';

/**
 * @param {CanvasRenderingContext2D} ctx
 * @param {string} kind       which art to draw
 * @param {object} face       landmarks in the video's 0..1 space
 * @param {{map: Function, scale: number}} options
 */
export function drawOverlay(ctx, kind, face, { map, scale = 1 }) {
  let left = map(face.leftEye);
  let right = map(face.rightEye);
  // The tracker labels eyes from the subject's point of view, and mirroring can
  // swap them on screen. Order by x so the art never lands upside down.
  if (left.x > right.x) [left, right] = [right, left];

  const unit = Math.hypot(right.x - left.x, right.y - left.y);
  if (!unit || !isFinite(unit)) return;
  const angle = Math.atan2(right.y - left.y, right.x - left.x);
  const mid = { x: (left.x + right.x) / 2, y: (left.y + right.y) / 2 };

  ctx.save();
  ctx.translate(mid.x, mid.y);
  ctx.rotate(angle);

  switch (kind) {
    case 'shades': shades(ctx, unit); break;
    case 'crown': crown(ctx, unit); break;
    case 'puppy': puppy(ctx, unit, face, map, mid, angle); break;
    case 'hearts': hearts(ctx, unit); break;
    default: break;
  }

  ctx.restore();
  void scale;
}

/** Rounded rectangle path, because Safari only got roundRect recently. */
function roundRect(ctx, x, y, w, h, r) {
  const radius = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + radius, y);
  ctx.arcTo(x + w, y, x + w, y + h, radius);
  ctx.arcTo(x + w, y + h, x, y + h, radius);
  ctx.arcTo(x, y + h, x, y, radius);
  ctx.arcTo(x, y, x + w, y, radius);
  ctx.closePath();
}

function shades(ctx, u) {
  const lensW = u * 1.05;
  const lensH = u * 0.74;
  const gap = u * 0.3;

  ctx.fillStyle = 'rgba(8, 8, 10, 0.92)';
  for (const sign of [-1, 1]) {
    const x = sign < 0 ? -gap / 2 - lensW : gap / 2;
    roundRect(ctx, x, -lensH / 2, lensW, lensH, lensH * 0.42);
    ctx.fill();
  }

  // Bridge, then arms running off toward the ears.
  ctx.strokeStyle = 'rgba(8, 8, 10, 0.92)';
  ctx.lineWidth = u * 0.1;
  ctx.beginPath();
  ctx.moveTo(-gap / 2, -lensH * 0.12);
  ctx.lineTo(gap / 2, -lensH * 0.12);
  ctx.moveTo(-gap / 2 - lensW, -lensH * 0.26);
  ctx.lineTo(-gap / 2 - lensW - u * 0.42, -lensH * 0.42);
  ctx.moveTo(gap / 2 + lensW, -lensH * 0.26);
  ctx.lineTo(gap / 2 + lensW + u * 0.42, -lensH * 0.42);
  ctx.stroke();

  ctx.fillStyle = 'rgba(255, 255, 255, 0.16)';
  for (const sign of [-1, 1]) {
    const x = sign < 0 ? -gap / 2 - lensW * 0.88 : gap / 2 + lensW * 0.12;
    ctx.beginPath();
    ctx.ellipse(x + lensW * 0.2, -lensH * 0.18, lensW * 0.2, lensH * 0.16, -0.4, 0, Math.PI * 2);
    ctx.fill();
  }
}

function crown(ctx, u) {
  const w = u * 2.5;
  const h = u * 1.15;
  const top = -u * 2.5;

  ctx.fillStyle = '#f9c62f';
  ctx.beginPath();
  ctx.moveTo(-w / 2, top + h);
  ctx.lineTo(-w / 2, top + h * 0.28);
  ctx.lineTo(-w * 0.22, top + h * 0.68);
  ctx.lineTo(0, top);
  ctx.lineTo(w * 0.22, top + h * 0.68);
  ctx.lineTo(w / 2, top + h * 0.28);
  ctx.lineTo(w / 2, top + h);
  ctx.closePath();
  ctx.fill();

  ctx.fillStyle = '#d93352';
  for (const x of [-0.3, 0, 0.3]) {
    ctx.beginPath();
    ctx.arc(w * x, top + h * 0.82, u * 0.1, 0, Math.PI * 2);
    ctx.fill();
  }
}

function puppy(ctx, u, face, map, mid, angle) {
  const earW = u * 0.95;
  const earH = u * 1.9;
  const top = -u * 2.0;

  for (const sign of [-1, 1]) {
    const x = sign * u * 1.25;
    ctx.save();
    ctx.translate(x, top);
    ctx.rotate(sign * 0.18);

    ctx.fillStyle = BROWN;
    ctx.beginPath();
    ctx.moveTo(0, earH);
    ctx.bezierCurveTo(-earW * 0.75, earH * 0.72, -earW * 0.62, 0, 0, 0);
    ctx.bezierCurveTo(earW * 0.62, 0, earW * 0.75, earH * 0.72, 0, earH);
    ctx.closePath();
    ctx.fill();

    ctx.fillStyle = BROWN_INNER;
    ctx.beginPath();
    ctx.moveTo(0, earH * 0.86);
    ctx.bezierCurveTo(-earW * 0.38, earH * 0.64, -earW * 0.32, earH * 0.2, 0, earH * 0.18);
    ctx.bezierCurveTo(earW * 0.32, earH * 0.2, earW * 0.38, earH * 0.64, 0, earH * 0.86);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }

  // The nose is anchored to its own landmark rather than to the eye line, so it
  // is converted into the rotated frame the context is already in.
  if (!face.nose) return;
  const nose = map(face.nose);
  const dx = nose.x - mid.x;
  const dy = nose.y - mid.y;
  const cos = Math.cos(angle);
  const sin = Math.sin(angle);
  const nx = dx * cos + dy * sin;
  const ny = -dx * sin + dy * cos;

  ctx.fillStyle = '#161618';
  roundRect(ctx, nx - u * 0.3, ny - u * 0.2, u * 0.6, u * 0.42, u * 0.2);
  ctx.fill();
  ctx.fillStyle = 'rgba(255, 255, 255, 0.24)';
  ctx.beginPath();
  ctx.ellipse(nx - u * 0.1, ny - u * 0.08, u * 0.1, u * 0.055, 0, 0, Math.PI * 2);
  ctx.fill();
}

function hearts(ctx, u) {
  const size = u * 0.62;
  ctx.fillStyle = '#f23359';
  for (const sign of [-1, 1]) {
    const x = sign * u * 0.5;
    ctx.save();
    ctx.translate(x, 0);
    ctx.beginPath();
    ctx.moveTo(0, size * 0.52);
    ctx.bezierCurveTo(-size * 0.95, -size * 0.1, -size * 0.42, -size * 0.78, 0, -size * 0.28);
    ctx.bezierCurveTo(size * 0.42, -size * 0.78, size * 0.95, -size * 0.1, 0, size * 0.52);
    ctx.closePath();
    ctx.fill();
    ctx.restore();
  }
}
