// مصدر الفيديو: يتعرّف على رابط الفيديو (يوتيوب، فيسبوك (غير الريلز)،
// ملف فيديو مباشر، بث HLS) ويحدد طريقة عرضه.
// لا يعتمد على Firebase، فيمكن اختباره وحده.
import 'dart:convert';
import 'dart:ui' show Color;

import 'l10n.dart';

enum VideoProvider {
  youtube,
  facebook, // الفيديوهات العادية فقط (ريلز فيسبوك غير مدعومة)
  file, // mp4 / webm ... رابط مباشر
  hls, // بث m3u8
}

/// مقبض للتحكم بمشغّل ملف مضمَّن (تشغيل/إيقاف) من خارج المشغّل.
/// يربطه المشغّل نفسه عند بنائه ويفكّه عند إزالته.
class VideoHandle {
  void Function(String cmd)? _sender;
  void attach(void Function(String cmd) sender) => _sender = sender;
  void detach() => _sender = null;

  /// الأوامر: toggle ، play ، pause.
  void send(String cmd) => _sender?.call(cmd);
}

class VideoSource {
  final VideoProvider provider;

  /// معرّف الفيديو على المنصة (لروابط الملفات والبث: بصمة قصيرة للرابط).
  final String id;

  /// الرابط الأصلي بعد تنظيفه (https). يُستعمل للتضمين والتعرّف فقط.
  final String url;

  /// فيديو عمودي (9:16): يظهر مع الشورتز.
  final bool isShort;

  /// بث مباشر (رابط HLS).
  final bool isLive;

  /// رابط صورة غلاف الفيديو المرفوع (لقطة من الفيديو تُرفع مع المنشور).
  /// null للمنشورات القديمة والمنصات الأخرى.
  final String? thumb;

  const VideoSource._(this.provider, this.id, this.url,
      {this.isShort = false, this.isLive = false, this.thumb});

  /// يعيد بناء المصدر من الحقول المحفوظة في المنشور.
  /// منشورات يوتيوب القديمة ليس فيها provider ولا url: يكفيها المعرّف.
  static VideoSource? fromStored(
      {String? provider,
      String? id,
      String? url,
      bool isShort = false,
      String? thumb}) {
    if ((provider == null || provider == 'youtube') && id != null) {
      if (!_ytId.hasMatch(id)) return null;
      // منشورات يوتيوب القديمة المعلَّمة شورتز تظهر الآن كفيديو عادي.
      return VideoSource._(VideoProvider.youtube, id, youtubeWatch(id));
    }
    if (url == null) return null;
    final v = parse(url);
    // الفيديو المرفوع: العلامة (عمودي/أفقي) محفوظة في المنشور وليست في الرابط.
    if (v != null && isShort && v.provider == VideoProvider.file) {
      return v.asShort().withThumb(thumb);
    }
    return v?.withThumb(thumb);
  }

  /// نسخة من المصدر بصورة غلاف (تُهمل إن لم تكن رابط https).
  VideoSource withThumb(String? t) {
    if (t == null || !t.startsWith('https://')) return this;
    return VideoSource._(provider, id, url,
        isShort: isShort, isLive: isLive, thumb: t);
  }

  /// نسخة من المصدر معلَّمة كفيديو عمودي (تظهر مع الشورتز).
  VideoSource asShort() => VideoSource._(provider, id, url,
      isShort: true, isLive: isLive, thumb: thumb);

  static final _ytId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static String youtubeWatch(String id) => 'https://www.youtube.com/watch?v=$id';

  // ───────────────────────── التعرّف على الرابط ─────────────────────────

  static const _fileExt = {'mp4', 'webm', 'm4v', 'mov', 'ogv'};

  /// يحلّل الرابط. يعيد null إن لم يكن رابط فيديو مدعوماً.
  static VideoSource? parse(String input) {
    var text = input.trim();
    if (text.isEmpty || text.contains(RegExp(r'\s'))) return null;
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    final host = uri.host.toLowerCase();
    final bare = host.replaceFirst(
        RegExp(r'^(www|m|mobile|web|music|player|clips|mbasic)\.'), '');
    final seg = [for (final s in uri.pathSegments) if (s.isNotEmpty) s];

    // يوتيوب
    if (bare == 'youtu.be' ||
        bare == 'youtube.com' ||
        bare == 'youtube-nocookie.com') {
      final id = youtubeIdOf(uri);
      if (id == null) return null;
      // روابط شورتز يوتيوب تُعامل كفيديو عادي (قسم الشورتز للفيديو المرفوع فقط).
      return VideoSource._(VideoProvider.youtube, id, youtubeWatch(id));
    }
    // فيسبوك
    if (bare == 'facebook.com' || bare == 'fb.com') return _facebook(uri, seg);

    // ملف فيديو مباشر أو بث HLS: الامتداد في المسار (نتجاهل الاستعلام).
    final last = seg.isEmpty ? '' : seg.last.toLowerCase();
    final dot = last.lastIndexOf('.');
    final ext = dot < 0 ? '' : last.substring(dot + 1);
    final clean = uri.replace(scheme: 'https', fragment: '').toString();
    if (ext == 'm3u8') {
      return VideoSource._(VideoProvider.hls, _hash(clean), clean,
          isLive: true);
    }
    if (_fileExt.contains(ext)) {
      return VideoSource._(VideoProvider.file, _hash(clean), clean);
    }
    return null;
  }

  /// روابط مختصرة/مشاركة لا يمكن حلّها دون فتحها (تعيد توجيهاً).
  static bool isUnresolvableShortLink(String input) {
    var text = input.trim();
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    final first = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    return host == 'fb.watch' ||
        (host.endsWith('facebook.com') && first == 'share');
  }

  /// رابط ريلز فيسبوك (غير مدعوم: الريلز فيديوهات عمودية).
  static bool isFacebookReel(String input) {
    var text = input.trim();
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (!(host == 'facebook.com' || host.endsWith('.facebook.com') ||
        host == 'fb.com' || host.endsWith('.fb.com'))) {
      return false;
    }
    final first = uri.pathSegments.where((s) => s.isNotEmpty).firstOrNull;
    return first == 'reel' || first == 'reels';
  }

  static String? youtubeIdOf(Uri uri) {
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www\.|m\.|music\.)'), '');
    String? id;
    if (host == 'youtu.be') {
      if (uri.pathSegments.isNotEmpty) id = uri.pathSegments.first;
    } else if (host == 'youtube.com' || host == 'youtube-nocookie.com') {
      final seg = uri.pathSegments;
      if (seg.isNotEmpty && seg.first == 'watch') {
        id = uri.queryParameters['v'];
      } else if (seg.length >= 2 &&
          const {'shorts', 'live', 'embed', 'v'}.contains(seg.first)) {
        id = seg[1];
      }
    }
    return (id != null && _ytId.hasMatch(id)) ? id : null;
  }

  static VideoSource? _facebook(Uri uri, List<String> seg) {
    final idRe = RegExp(r'^\d{6,20}$');
    String? id;
    var path = '';
    // ريلز فيسبوك (فيديوهات عمودية) غير مدعومة.
    if (seg.isNotEmpty && (seg.first == 'reel' || seg.first == 'reels')) {
      return null;
    }
    if (seg.isNotEmpty && seg.first == 'watch') {
      id = uri.queryParameters['v'];
      path = '/watch/?v=$id';
    } else if (seg.isNotEmpty && seg.first == 'video.php') {
      id = uri.queryParameters['v'];
      path = '/watch/?v=$id';
    } else {
      final i = seg.indexOf('videos');
      if (i >= 0 && i + 1 < seg.length) {
        // /page/videos/ID  أو  /page/videos/عنوان/ID
        id = seg.sublist(i + 1).lastWhere(idRe.hasMatch, orElse: () => '');
        path = i == 0 ? '/watch/?v=$id' : '/${seg.take(i).join('/')}/videos/$id';
      }
    }
    if (id == null || !idRe.hasMatch(id)) return null;
    return VideoSource._(
        VideoProvider.facebook, id, 'https://www.facebook.com$path');
  }

  /// بصمة قصيرة ثابتة للرابط (FNV-1a) لاستعمالها كمعرّف.
  static String _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(36);
  }

  // ───────────────────────── العرض ─────────────────────────

  /// مفتاح فريد لهذا الفيديو (لمشغّلات الويب والمفاتيح).
  String get key => '${provider.name}-$id';

  /// نسبة العرض إلى الارتفاع.
  double get aspect {
    if (isShort) return 9 / 16;
    return 16 / 9;
  }

  /// يعمل المشغّل بصفحة HTML نصنعها (ملف أو HLS) بدل رابط جاهز.
  bool get usesPlayerHtml =>
      provider == VideoProvider.file || provider == VideoProvider.hls;

  String get platformName => switch (provider) {
        VideoProvider.youtube => 'YouTube',
        VideoProvider.facebook => 'Facebook',
        VideoProvider.file => tr('فيديو'),
        VideoProvider.hls => tr('بث مباشر'),
      };

  /// النص المعروض على غلاف الملف المباشر والبث (بجانب شعار Haigram).
  String get coverLabel =>
      provider == VideoProvider.hls ? tr('شاهد البث المباشر') : tr('شاهد الفيديو');

  /// صورة مصغّرة جاهزة إن وفّرتها المنصة برابط ثابت، وإلا null (يُرسم غلاف).
  String? get thumbUrl {
    if (provider == VideoProvider.youtube) {
      return 'https://img.youtube.com/vi/$id/hqdefault.jpg';
    }
    final t = thumb;
    if (t == null) return null;
    // Cloudinary: نصغّر الصورة ونحسّن صيغتها لتوفير الحصة والسرعة.
    const marker = '/image/upload/';
    if (t.startsWith('https://res.cloudinary.com/') && t.contains(marker)) {
      return t.replaceFirst(marker, '${marker}f_auto,q_auto,w_720/');
    }
    return t;
  }

  /// ألوان غلاف المنصة (تدرّج).
  List<Color> get brandColors => switch (provider) {
        VideoProvider.youtube => const [Color(0xFFFF0000), Color(0xFF8A0000)],
        VideoProvider.facebook => const [Color(0xFF1877F2), Color(0xFF0A3A7A)],
        VideoProvider.file || VideoProvider.hls =>
          const [Color(0xFF1B1F2A), Color(0xFF0B0D12)],
      };

  /// رابط التضمين (iframe). null للملف والبث: يستعملان [playerHtml].
  /// [parentHost]: نطاق الصفحة (غير مستعمل حالياً، محفوظ للتوافق).
  String? embedUrl({String parentHost = 'haigram.web.app'}) {
    switch (provider) {
      case VideoProvider.youtube:
        return 'https://www.youtube.com/embed/$id?autoplay=1&playsinline=1&rel=0';
      case VideoProvider.facebook:
        return 'https://www.facebook.com/plugins/video.php'
            '?href=${Uri.encodeQueryComponent(url)}&show_text=false&autoplay=true';
      case VideoProvider.file:
      case VideoProvider.hls:
        return null;
    }
  }

  /// نطاقات مسموح للـ WebView التنقل إليها (الإطار الرئيسي). غيرها يُمنع (التشغيل داخل التطبيق فقط).
  bool allowsNavigation(Uri uri) {
    final h = uri.host.toLowerCase();
    bool inDomain(List<String> ds) =>
        ds.any((d) => h == d || h.endsWith('.$d'));
    return switch (provider) {
      VideoProvider.youtube =>
        inDomain(['youtube.com']) && uri.path.startsWith('/embed/'),
      VideoProvider.facebook => inDomain(['facebook.com']),
      VideoProvider.file || VideoProvider.hls => inDomain(['haigram.web.app']),
    };
  }

  /// صفحة HTML لمشغّل الملف المباشر أو البث. تُرسل نتيجة التشغيل عبر
  /// postMessage (الويب) أو قناة HaigramVideo (التطبيق): 'ok' أو 'error'.
  /// [short]: نمط الشورتز (تيك توك): بلا أزرار المشغّل، يملأ الإطار، يتكرر،
  /// وشريط تقدّم رفيع. التشغيل والإيقاف يأتيان من الخارج عبر [VideoHandle].
  /// [gestures] (للويب): تتولى الصفحة نفسها اللمس (نقرة=إيقاف/تشغيل، نقرتان=إعجاب،
  /// سحب/عجلة/أسهم=التنقل) وترسلها للتطبيق عبر postMessage بالمفتاح haigramGesture،
  /// لأن الـ iframe يلتقط اللمس فلا تصله طبقة فلتر.
  String playerHtml({bool short = false, bool gestures = false}) {
    final src = _jsString(url);
    final failText = _jsString(tr('تعذر تشغيل هذا الفيديو'));
    final isHls = provider == VideoProvider.hls;
    return '''<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
html,body{margin:0;height:100%;background:#000;overflow:hidden${gestures ? ';touch-action:none;user-select:none;-webkit-user-select:none' : ''}}
video{width:100%;height:100%;object-fit:${short ? 'cover' : 'contain'};background:#000}
${short ? '#pb{position:absolute;left:0;bottom:0;height:3px;width:0;background:#fff;opacity:.85;pointer-events:none}' : ''}
#e{position:absolute;inset:0;display:none;align-items:center;justify-content:center;
color:#fff;font:15px sans-serif;text-align:center;padding:16px;background:#000}
</style>
${isHls ? '<script src="https://cdn.jsdelivr.net/npm/hls.js@1.5.17/dist/hls.min.js"></script>' : ''}
</head><body>
<video id="v" ${short ? 'loop' : 'controls'} autoplay playsinline preload="auto"></video>${short ? '<div id="pb"></div>' : ''}<div id="e"></div>
<script>
var src=$src, isHls=$isHls, v=document.getElementById('v'), done=false;
function notify(s){
  try{ parent.postMessage({haigramVideo:s},'*'); }catch(_){}
  try{ HaigramVideo.postMessage(s); }catch(_){}
}
function fail(){ if(done) return; done=true;
  var e=document.getElementById('e'); e.textContent=$failText; e.style.display='flex';
  notify('error'); }
v.addEventListener('error',fail);
function ok(){ if(!done){done=true;notify('ok');} }
// على الموبايل (خصوصاً آيفون) قد لا يُحمَّل أي بيانات قبل الضغط على تشغيل،
// فيكفي نجاح قراءة معلومات الملف (loadedmetadata) لاعتبار الفيديو صالحاً.
v.addEventListener('loadedmetadata',ok);
v.addEventListener('loadeddata',ok);
v.addEventListener('canplay',ok);
function haigramCmd(c){
  if(c==='toggle'){ if(v.paused){ v.play(); } else { v.pause(); } }
  else if(c==='play'){ v.play(); } else if(c==='pause'){ v.pause(); }
}
window.addEventListener('message',function(e){
  var d=e.data; if(d && d.haigramCmd) haigramCmd(d.haigramCmd);
});
${gestures ? r'''
(function(){
  function g(m){ try{ parent.postMessage({haigramGesture:m},'*'); }catch(_){} }
  function toggle(){ haigramCmd('toggle'); g(v.paused ? 'paused' : 'playing'); }
  var down=null, lastTap=0, tapTimer=null;
  document.addEventListener('pointerdown',function(e){ down={x:e.clientX,y:e.clientY}; });
  document.addEventListener('pointerup',function(e){
    if(!down) return;
    var dx=e.clientX-down.x, dy=e.clientY-down.y; down=null;
    if(Math.abs(dy)>40 && Math.abs(dy)>Math.abs(dx)){ g(dy<0 ? 'next' : 'prev'); return; }
    if(Math.abs(dx)>12 || Math.abs(dy)>12) return;
    var now=Date.now();
    if(now-lastTap<300){
      clearTimeout(tapTimer); lastTap=0;
      g('dbl:'+e.clientX+','+e.clientY);
    } else {
      lastTap=now;
      tapTimer=setTimeout(toggle,300);
    }
  });
  document.addEventListener('pointercancel',function(){ down=null; });
  document.addEventListener('wheel',function(e){ e.preventDefault(); g(e.deltaY>0 ? 'next' : 'prev'); },{passive:false});
  document.addEventListener('keydown',function(e){
    if(e.key==='ArrowDown'){ e.preventDefault(); g('next'); }
    else if(e.key==='ArrowUp'){ e.preventDefault(); g('prev'); }
    else if(e.key===' '){ e.preventDefault(); toggle(); }
  });
})();
''' : ''}
${short ? "var pb=document.getElementById('pb'); v.addEventListener('timeupdate',function(){ if(v.duration) pb.style.width=(100*v.currentTime/v.duration)+'%'; });" : ''}
if(isHls && !v.canPlayType('application/vnd.apple.mpegurl')){
  if(window.Hls && Hls.isSupported()){
    var h=new Hls(); h.loadSource(src); h.attachMedia(v);
    h.on(Hls.Events.ERROR,function(_,d){ if(d&&d.fatal) fail(); });
  } else fail();
} else { v.src=src; }
setTimeout(function(){ if(!done && v.readyState===0) fail(); },25000);
</script></body></html>''';
  }

  static String _jsString(String s) =>
      jsonEncode(s)
          .replaceAll('<', r'\u003c')
          .replaceAll('\u2028', r'\u2028')
          .replaceAll('\u2029', r'\u2029');
}
