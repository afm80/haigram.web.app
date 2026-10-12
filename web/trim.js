// قص الفيديو إلى مدة محددة داخل المتصفح بدون إعادة ترميز (سريع وبدون فقد جودة).
// ملفات ffmpeg.wasm موجودة محلياً في web/ffmpeg ولا تُحمَّل إلا عند الحاجة.
(function () {
  var ffmpegInstance = null;

  function loadScript(src) {
    return new Promise(function (resolve, reject) {
      var s = document.createElement('script');
      s.src = src;
      s.onload = resolve;
      s.onerror = function () { reject(new Error('تعذر تحميل ' + src)); };
      document.head.appendChild(s);
    });
  }

  async function getFFmpeg() {
    if (ffmpegInstance) return ffmpegInstance;
    if (!window.FFmpegWASM) await loadScript('ffmpeg/ffmpeg.js');
    var ff = new window.FFmpegWASM.FFmpeg();
    await ff.load({
      coreURL: new URL('ffmpeg/ffmpeg-core.js', document.baseURI).href,
      wasmURL: new URL('ffmpeg/ffmpeg-core.wasm', document.baseURI).href,
      classWorkerURL: new URL('ffmpeg/814.ffmpeg.js', document.baseURI).href
    });
    ffmpegInstance = ff;
    return ff;
  }

  window.lamhaBlobUrl = function (data, mime) {
    return URL.createObjectURL(new Blob([data], { type: mime }));
  };

  // url: رابط blob للفيديو، ext: امتداد الملف الأصلي، seconds: أقصى مدة
  window.lamhaTrim = async function (url, ext, seconds) {
    var ff = await getFFmpeg();
    var data = new Uint8Array(await (await fetch(url)).arrayBuffer());
    var inName = 'in.' + ext;
    await ff.writeFile(inName, data);
    var code = await ff.exec(['-i', inName, '-t', String(seconds), '-c', 'copy', '-movflags', '+faststart', 'out.mp4']);
    if (code !== 0) throw new Error('فشل قص الفيديو (' + code + ')');
    var out = await ff.readFile('out.mp4');
    try { await ff.deleteFile(inName); await ff.deleteFile('out.mp4'); } catch (e) {}
    return out;
  };
})();
