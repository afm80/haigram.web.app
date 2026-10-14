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

  // ضغط الفيديو داخل المتصفح: يقصّه إلى أقصى مدة، ويصغّر الضلع الأقصر إلى
  // maxShort بكسل (720 = جودة 720p)، ويحدد معدل البيانات فيصغر الملف كثيراً.
  // onProgress: دالة تستقبل رقماً بين 0 و 1.
  window.lamhaCompress = async function (url, ext, seconds, maxShort, onProgress) {
    var ff = await getFFmpeg();
    var data = new Uint8Array(await (await fetch(url)).arrayBuffer());
    var inName = 'in.' + ext;
    await ff.writeFile(inName, data);
    data = null;
    var handler = function (e) {
      if (!onProgress) return;
      var p = e && typeof e.progress === 'number' ? e.progress : 0;
      onProgress(Math.max(0, Math.min(1, p)));
    };
    ff.on('progress', handler);
    try {
      var m = String(maxShort);
      var vf = "scale=w='if(gt(iw,ih),-2,min(" + m + ",iw))':h='if(gt(iw,ih),min(" + m + ",ih),-2)'";
      var code = await ff.exec([
        '-i', inName,
        '-t', String(seconds),
        '-vf', vf,
        '-c:v', 'libx264', '-preset', 'superfast', '-crf', '30',
        '-maxrate', '1500k', '-bufsize', '3000k',
        '-pix_fmt', 'yuv420p',
        '-c:a', 'aac', '-b:a', '96k',
        '-movflags', '+faststart',
        'out.mp4'
      ]);
      if (code !== 0) throw new Error('فشل ضغط الفيديو (' + code + ')');
      var out = await ff.readFile('out.mp4');
      return out;
    } finally {
      try { ff.off('progress', handler); } catch (e) {}
      try { await ff.deleteFile(inName); } catch (e) {}
      try { await ff.deleteFile('out.mp4'); } catch (e) {}
    }
  };

  // صورة مصغّرة JPEG (عرضها width بكسل) من أول لحظات الفيديو. تعيد null عند الفشل.
  window.lamhaThumb = function (url, width) {
    return new Promise(function (resolve) {
      var v = document.createElement('video');
      var done = false;
      var timer = null;
      function finish(val) {
        if (done) return;
        done = true;
        clearTimeout(timer);
        try { v.removeAttribute('src'); v.load(); } catch (e) {}
        resolve(val);
      }
      function toJpeg(canvas, q) {
        return new Promise(function (res) { canvas.toBlob(res, 'image/jpeg', q); });
      }
      timer = setTimeout(function () { finish(null); }, 10000);
      v.muted = true;
      v.playsInline = true;
      v.preload = 'auto';
      v.onerror = function () { finish(null); };
      v.onloadeddata = function () {
        var d = v.duration;
        v.currentTime = (isFinite(d) && d > 0) ? Math.min(0.5, d / 2) : 0;
      };
      v.onseeked = async function () {
        try {
          var vw = v.videoWidth, vh = v.videoHeight;
          if (!vw || !vh) return finish(null);
          var w = Math.min(width, vw);
          var h = Math.round(vh * w / vw);
          var c = document.createElement('canvas');
          c.width = w; c.height = h;
          c.getContext('2d').drawImage(v, 0, 0, w, h);
          var blob = await toJpeg(c, 0.65);
          if (blob && blob.size > 45000) blob = await toJpeg(c, 0.4);
          if (!blob) return finish(null);
          finish(new Uint8Array(await blob.arrayBuffer()));
        } catch (e) { finish(null); }
      };
      v.src = url;
    });
  };
})();
