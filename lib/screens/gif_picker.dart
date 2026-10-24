import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../services/gif_service.dart';
import '../theme.dart';

/// ورقة اختيار GIF: بحث بكلمة، وبلا كلمة تُعرض الأكثر رواجاً.
/// تُرجِع [GifItem] المختار عبر Navigator.pop.
class GifPickerSheet extends StatefulWidget {
  const GifPickerSheet({super.key});

  @override
  State<GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends State<GifPickerSheet> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  final List<GifItem> _items = [];
  Timer? _debounce;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _failed = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _reload);
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 300) _loadMore();
  }

  Future<void> _reload() async {
    final id = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
      _hasMore = true;
      _items.clear();
    });
    try {
      final page = await GifService.load(_query.text);
      if (!mounted || id != _request) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length >= GifService.pageSize;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || id != _request) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _failed) return;
    final id = _request;
    setState(() => _loadingMore = true);
    try {
      final page =
          await GifService.load(_query.text, offset: _items.length);
      if (!mounted || id != _request) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length >= GifService.pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || id != _request) return;
      setState(() {
        _hasMore = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final height = MediaQuery.sizeOf(context).height * 0.62;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                child: TextField(
                  controller: _query,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    _debounce?.cancel();
                    _reload();
                  },
                  decoration: InputDecoration(
                    hintText: tr('ابحث عن GIF'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(child: _body(colors)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('Powered by GIPHY',
                    style: TextStyle(fontSize: 11, color: colors.textDim)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(AppPalette colors) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('تعذر تحميل الـ GIF'),
                style: TextStyle(color: colors.textDim)),
            TextButton(
                onPressed: _reload, child: Text(tr('إعادة المحاولة'))),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(tr('لا توجد نتائج'),
            style: TextStyle(color: colors.textDim)),
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: _items.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Center(
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final item = _items[index];
        return GestureDetector(
          onTap: () => Navigator.pop(context, item),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              color: colors.surfaceHigh,
              child: Image.network(
                item.previewUrl,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
    );
  }
}
