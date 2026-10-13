import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// مسار صفحة قابل للاستعادة بعد تحديث المتصفح.
///
/// [name] اسم نوع الصفحة (user / post / video / sound / chat / notifications /
/// editProfile / settings) و[args] معاملات نصية فقط (قابلة للتحويل إلى JSON).
/// الصفحات التي لا تُفتح بهذه الدالة (مثل شاشة الإنشاء) لا تُستعاد.
Route<T> appRoute<T>(
  String name,
  Map<String, dynamic> args,
  WidgetBuilder builder,
) =>
    MaterialPageRoute<T>(
      settings: RouteSettings(name: name, arguments: args),
      builder: builder,
    );

/// وصف صفحة محفوظة.
class SavedRoute {
  final String name;
  final Map<String, dynamic> args;
  const SavedRoute(this.name, this.args);
}

/// الحالة المحفوظة: التبويب الحالي + الصفحات المفتوحة داخل كل تبويب.
class SavedNavState {
  final int tab;
  final Map<int, List<SavedRoute>> stacks;
  const SavedNavState(this.tab, this.stacks);
}

class _Entry {
  final Route<dynamic> route;
  final String name;
  final Map<String, dynamic> args;
  _Entry(this.route, this.name, this.args);
}

/// يحفظ حالة التنقل في SharedPreferences (localStorage على الويب).
class RouteStore {
  RouteStore._();

  static const _storageKey = 'nav_state_v1';
  static const restorable = {
    'user',
    'post',
    'video',
    'sound',
    'chat',
    'notifications',
    'editProfile',
    'settings',
    'search',
  };

  static final Map<int, List<_Entry>> _stacks = {};
  static int _tab = 0;
  static SharedPreferences? _prefs;

  /// يقرأ الحالة المحفوظة. يعيد null إذا لم توجد، أو كانت لمستخدم آخر،
  /// أو لرابط مشاركة مختلف عن الرابط الحالي (حتى يعمل الرابط الجديد).
  static Future<SavedNavState?> loadSaved() async {
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['uid'] != FirebaseAuth.instance.currentUser?.uid) return null;
      if (data['q'] != Uri.base.query) return null;
      final stacks = <int, List<SavedRoute>>{};
      final rawStacks = (data['stacks'] as Map<String, dynamic>?) ?? {};
      for (final entry in rawStacks.entries) {
        final tab = int.tryParse(entry.key);
        if (tab == null) continue;
        stacks[tab] = [
          for (final item in (entry.value as List<dynamic>))
            SavedRoute(
              (item as Map<String, dynamic>)['n'] as String,
              Map<String, dynamic>.from(item['a'] as Map),
            ),
        ];
      }
      final tab = (data['tab'] as num?)?.toInt() ?? 0;
      return SavedNavState(tab, stacks);
    } catch (_) {
      return null;
    }
  }

  /// تسجيل التبويب الحالي. [persist] = false أثناء الاستعادة.
  static void setTab(int tab, {bool persist = true}) {
    _tab = tab;
    if (persist) _persist();
  }

  static void _add(int tab, Route<dynamic> route) {
    final name = route.settings.name;
    final args = route.settings.arguments;
    if (name == null || !restorable.contains(name) || args is! Map) return;
    (_stacks[tab] ??= []).add(
      _Entry(route, name, Map<String, dynamic>.from(args)),
    );
    _persist();
  }

  static void _remove(int tab, Route<dynamic> route) {
    final list = _stacks[tab];
    if (list == null) return;
    final before = list.length;
    list.removeWhere((entry) => identical(entry.route, route));
    if (list.length != before) _persist();
  }

  /// يمسح الحالة (عند تسجيل الخروج).
  static void clear() {
    _stacks.clear();
    _tab = 0;
    _prefs?.remove(_storageKey);
  }

  static void _persist() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final data = <String, dynamic>{
      'uid': uid,
      'q': Uri.base.query,
      'tab': _tab,
      'stacks': {
        for (final entry in _stacks.entries)
          '${entry.key}': [
            for (final item in entry.value) {'n': item.name, 'a': item.args},
          ],
      },
    };
    _write(jsonEncode(data));
  }

  static Future<void> _write(String json) async {
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, json);
    } catch (_) {}
  }
}

/// رقم مكدّس الصفحات المفتوحة فوق الشريط السفلي (Navigator الجذر).
const rootStackIndex = 5;

/// يفتح صفحة فوق الشريط السفلي (تغطيه) بدل أن تبقى داخل التبويب.
NavigatorState rootNavigatorOf(BuildContext context) =>
    Navigator.of(context, rootNavigator: true);

/// يراقب الصفحات المفتوحة داخل تبويب معيّن ويحفظها.
class TabRouteObserver extends NavigatorObserver {
  final int tab;
  TabRouteObserver(this.tab);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      RouteStore._add(tab, route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      RouteStore._remove(tab, route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      RouteStore._remove(tab, route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) RouteStore._remove(tab, oldRoute);
    if (newRoute != null) RouteStore._add(tab, newRoute);
  }
}

/// مراقب الـ Navigator الجذر: يحفظ الصفحات المفتوحة فوق الشريط السفلي.
final TabRouteObserver rootRouteObserver = TabRouteObserver(rootStackIndex);
