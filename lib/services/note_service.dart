import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../l10n.dart';
import 'social_service.dart';

/// ملاحظة قصيرة (مثل «Notes» في إنستغرام): نص حتى 60 حرفاً يظهر فوق صورة
/// صاحبه في صندوق البريد ويختفي بعد 24 ساعة.
///
/// المخزَّن في Firestore: notes/{uid} => { uid, text, createdAt, viewers }
///  - مستند واحد لكل مستخدم: ملاحظة جديدة تستبدل القديمة.
///  - viewers: معرّفات الأصدقاء (متابعة متبادلة) وقت النشر، ومنها تقرأ القواعد.
///  - الانتهاء = createdAt + 24 ساعة (يُحسب في العميل، لا يمكن تزويره).
class UserNote {
  static const maxLength = 60;
  static const lifetime = Duration(hours: 24);

  final String uid;
  final String text;
  final DateTime createdAt;

  const UserNote({
    required this.uid,
    required this.text,
    required this.createdAt,
  });

  DateTime get expiresAt => createdAt.add(lifetime);

  bool get isActive => DateTime.now().isBefore(expiresAt);

  /// مثل إنستغرام: «ينتهي بعد كذا» تحت الملاحظة.
  Duration get remaining => expiresAt.difference(DateTime.now());

  static UserNote? tryFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    final text = data['text'];
    if (text is! String || text.trim().isEmpty) return null;
    final created = data['createdAt'];
    return UserNote(
      uid: doc.id,
      text: text,
      // الكتابة المعلّقة (serverTimestamp لم يصل بعد) تأتي null: نعتبرها «الآن».
      createdAt: created is Timestamp ? created.toDate() : DateTime.now(),
    );
  }
}

class NoteService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String get _uid => FirebaseAuth.instance.currentUser!.uid;
  static bool get _isGuest => FirebaseAuth.instance.currentUser == null;

  static CollectionReference<Map<String, dynamic>> get _notes =>
      _db.collection('notes');

  /// معرّف الرسالة المرجعية عند الردّ على ملاحظة (يميّزها عن الردّ على رسالة).
  static String replyIdFor(String ownerUid) => 'note_$ownerUid';
  static bool isNoteReplyId(String? id) => id != null && id.startsWith('note_');

  /// ملاحظتي (أو null إن لم توجد أو انتهت). تُحذف المنتهية تلقائياً.
  static Stream<UserNote?> myNote() {
    if (_isGuest) return Stream.value(null);
    return _notes.doc(_uid).snapshots().map((snapshot) {
      final note = UserNote.tryFromDoc(snapshot);
      if (note == null) return null;
      if (!note.isActive) {
        unawaited(_notes.doc(_uid).delete().catchError((Object _) {}));
        return null;
      }
      return note;
    });
  }

  /// ملاحظات الأصدقاء الفعّالة (مفتاحها معرّف صاحب الملاحظة).
  static Stream<Map<String, UserNote>> friendsNotes() {
    if (_isGuest) return Stream.value(const {});
    return _notes
        .where('viewers', arrayContains: _uid)
        .snapshots()
        .map((snapshot) {
      final out = <String, UserNote>{};
      for (final doc in snapshot.docs) {
        final note = UserNote.tryFromDoc(doc);
        if (note != null && note.isActive && note.uid != _uid) {
          out[note.uid] = note;
        }
      }
      return out;
    });
  }

  /// ينشر ملاحظة جديدة (تستبدل السابقة) لأصدقائي: المتابعة المتبادلة.
  static Future<void> post(String text) async {
    final trimmed = text.trim();
    // الحد الظاهر 60 حرفاً (يفرضه حقل الكتابة بعدّ الحروف المرئية)؛ هذا حدّ أمان
    // أوسع لأن بعض الإيموجي يشغل أكثر من وحدة نصية واحدة.
    if (trimmed.isEmpty || trimmed.length > UserNote.maxLength * 4) {
      throw ArgumentError(tr('يجب أن تكون الملاحظة بين حرف واحد و60 حرفاً'));
    }
    final friends = await SocialService.mutualFriendIds();
    final blocked = await SocialService.blockedUserIds().first;
    final viewers = [
      for (final id in friends)
        if (id != _uid && !blocked.contains(id)) id,
    ].take(1000).toList();
    await _notes.doc(_uid).set({
      'uid': _uid,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
      'viewers': viewers,
    });
  }

  static Future<void> delete() => _notes.doc(_uid).delete();

  /// ردّ على ملاحظة: رسالة في المحادثة الخاصة تقتبس الملاحظة.
  static Future<void> reply(UserNote note, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final conversationId = await SocialService.startConversation(note.uid);
    await SocialService.sendMessage(
      conversationId,
      trimmed,
      replyToMessageId: replyIdFor(note.uid),
      replyToText: note.text,
      replyToSenderUid: note.uid,
    );
  }
}
