// Live UPC/EAN barcode scanning with the phone's rear camera.
// Uses the built-in BarcodeDetector where available (Chrome on Android), otherwise ZXing (iPhone Safari).

const ZXING_URL = 'https://cdn.jsdelivr.net/npm/@zxing/library@0.20.0/umd/index.min.js';

function loadScript(src) {
  return new Promise((resolve, reject) => {
    if (document.querySelector(`script[src="${src}"]`)) return resolve();
    const s = document.createElement('script');
    s.src = src;
    s.onload = resolve;
    s.onerror = () => reject(new Error('Could not load the barcode scanner.'));
    document.head.appendChild(s);
  });
}

const CONSTRAINTS = {
  audio: false,
  video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } },
};

/** Starts scanning into `video`; calls onCode(text) once per detected code. Returns a stop function. */
export async function startScanner(video, onCode) {
  if (!navigator.mediaDevices?.getUserMedia) {
    throw new Error('This browser can’t use the camera. Type the UPC instead.');
  }
  video.setAttribute('playsinline', '');
  video.setAttribute('muted', '');
  video.muted = true;

  let native = null;
  if ('BarcodeDetector' in window) {
    try {
      const wanted = ['ean_13', 'ean_8', 'upc_a', 'upc_e', 'code_128'];
      const supported = (await window.BarcodeDetector.getSupportedFormats?.()) ?? wanted;
      const formats = wanted.filter((f) => supported.includes(f));
      if (formats.length) native = new window.BarcodeDetector({ formats });
    } catch {
      native = null;
    }
  }

  if (native) {
    const stream = await navigator.mediaDevices.getUserMedia(CONSTRAINTS);
    video.srcObject = stream;
    await video.play();
    let stopped = false;
    const tick = async () => {
      if (stopped) return;
      try {
        const codes = await native.detect(video);
        if (codes.length && !stopped) onCode(codes[0].rawValue);
      } catch { /* frame not ready */ }
      setTimeout(tick, 180);
    };
    tick();
    return () => {
      stopped = true;
      stream.getTracks().forEach((t) => t.stop());
      video.srcObject = null;
    };
  }

  await loadScript(ZXING_URL);
  const { BrowserMultiFormatReader, DecodeHintType, BarcodeFormat } = window.ZXing;
  const hints = new Map();
  hints.set(DecodeHintType.POSSIBLE_FORMATS, [
    BarcodeFormat.EAN_13, BarcodeFormat.EAN_8, BarcodeFormat.UPC_A, BarcodeFormat.UPC_E, BarcodeFormat.CODE_128,
  ]);
  hints.set(DecodeHintType.TRY_HARDER, true);
  const reader = new BrowserMultiFormatReader(hints, 250);
  await reader.decodeFromConstraints(CONSTRAINTS, video, (result) => {
    if (result) onCode(result.getText());
  });
  return () => reader.reset();
}
