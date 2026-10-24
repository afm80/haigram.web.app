import 'package:flutter/material.dart';

import '../l10n.dart';
import '../net_error.dart';
import '../services/post_service.dart';
import '../services/user_service.dart';
import '../theme.dart';
import 'common_widgets.dart';

/// إدارة خصوصية القصص: الحسابات التي كتمتُ قصصها، والتي أخفيتُ قصصي عنها.
class StoryPrivacyScreen extends StatelessWidget {
  const StoryPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('خصوصية القصص')),
          bottom: TabBar(tabs: [
            Tab(text: tr('قصص مكتومة')),
            Tab(text: tr('قصصي مخفية عنهم')),
          ]),
        ),
        body: TabBarView(children: [
          _UserList(
            stream: PostService.mutedStoryUids(),
            emptyText: tr('لم تكتم قصص أي حساب'),
            actionLabel: tr('إلغاء الكتم'),
            onRemove: (uid) => PostService.setStoryMuted(uid, false),
          ),
          _UserList(
            stream: PostService.hiddenFromUids(),
            emptyText: tr('لم تُخفِ قصصك عن أي حساب'),
            actionLabel: tr('إظهار'),
            onRemove: (uid) => PostService.setStoriesHiddenFrom(uid, false),
          ),
        ]),
      ),
    );
  }
}

class _UserList extends StatelessWidget {
  final Stream<Set<String>> stream;
  final String emptyText;
  final String actionLabel;
  final Future<void> Function(String uid) onRemove;
  const _UserList(
      {required this.stream,
      required this.emptyText,
      required this.actionLabel,
      required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text(tr('تعذّر تحميل القائمة')));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final ids = snap.data!.toList();
        if (ids.isEmpty) {
          return Center(
              child: Text(emptyText,
                  style: TextStyle(color: context.appColors.textDim)));
        }
        return ListView.builder(
          itemCount: ids.length,
          itemBuilder: (_, i) => _UserTile(
              uid: ids[i], actionLabel: actionLabel, onRemove: onRemove),
        );
      },
    );
  }
}

class _UserTile extends StatelessWidget {
  final String uid;
  final String actionLabel;
  final Future<void> Function(String uid) onRemove;
  const _UserTile(
      {required this.uid, required this.actionLabel, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: UserService.profileStream(uid),
      builder: (context, snap) {
        final u = snap.data;
        final name = u?.username ?? '';
        return ListTile(
          leading: UserAvatar(uid: uid, fallbackName: name, radius: 22, profile: u),
          title: Text(name.isEmpty ? '...' : name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await onRemove(uid);
              } catch (e) {
                messenger.showSnackBar(SnackBar(
                    content: Text(
                        friendlyError(e, fallback: tr('تعذّر تنفيذ الإجراء')))));
              }
            },
            child: Text(actionLabel),
          ),
        );
      },
    );
  }
}
