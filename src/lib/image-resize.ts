/** Largest side (px) of a stored profile photo. Plenty for a 96px avatar on a 3x screen. */
export const AVATAR_MAX_SIDE = 640;

/** Scales (w, h) down to fit inside a max x max square. Never scales up. */
export function fitWithin(w: number, h: number, max: number): { width: number; height: number } {
  if (!(w > 0) || !(h > 0)) return { width: 0, height: 0 };
  const scale = Math.min(1, max / Math.max(w, h));
  return { width: Math.max(1, Math.round(w * scale)), height: Math.max(1, Math.round(h * scale)) };
}

/**
 * Shrinks a photo in the browser and re-encodes it as JPEG. iPhone photos are
 * often 3-8 MB (and sometimes HEIC); this makes them small, correctly rotated
 * and in a format the bucket accepts. Throws if the browser can't read the image.
 */
export async function resizeToJpeg(file: File, max = AVATAR_MAX_SIDE, quality = 0.86): Promise<Blob> {
  const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
  try {
    const { width, height } = fitWithin(bitmap.width, bitmap.height, max);
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("no canvas");
    ctx.fillStyle = "#ffffff"; // flatten transparency (PNG/WebP) onto white for JPEG
    ctx.fillRect(0, 0, width, height);
    ctx.drawImage(bitmap, 0, 0, width, height);
    const blob = await new Promise<Blob | null>((res) => canvas.toBlob(res, "image/jpeg", quality));
    if (!blob) throw new Error("encode failed");
    return blob;
  } finally {
    bitmap.close();
  }
}
