// Sharing is the whole of Snappy's social surface: hand the file to the OS and
// let it decide what is offered. On iOS that sheet is also how a shot reaches
// the photo library ("Save Image"), so there is nothing to upload anywhere.

export function shareSupported() {
  return Boolean(navigator.canShare && navigator.share);
}

export async function shareFile(blob, fileName, title = 'Snappy') {
  const file = new File([blob], fileName, { type: blob.type });
  if (navigator.canShare?.({ files: [file] })) {
    try {
      await navigator.share({ files: [file], title });
      return 'shared';
    } catch (error) {
      if (error?.name === 'AbortError') return 'cancelled';
      // Fall through to a download when the sheet refuses the file.
    }
  }
  return download(blob, fileName);
}

export function download(blob, fileName) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = fileName;
  link.rel = 'noopener';
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 30_000);
  return 'downloaded';
}
