import 'dart:convert';
import 'dart:typed_data';

import '../ids.dart';
import '../model/elements.dart';
import '../model/note.dart';
import '../model/page.dart';

String _sig(Object j) => jsonEncode(j);

bool _sameEl(Element a, Element b) => _sig(a.toJson()) == _sig(b.toJson());

Map<String, dynamic> _pageProps(NotePage p) {
  final j = p.toJson();
  j.remove('elements');
  return j;
}

/// Three-way merge of two edited versions of the same note ("Combine both").
///
/// Objects are matched by id against [base], the last version both sides had in common:
/// * added on either side → kept
/// * deleted on one side, unchanged on the other → deleted
/// * deleted on one side, changed on the other → kept (the change wins)
/// * changed differently on both sides → both kept (the remote copy gets a new id)
Note mergeNotes({required Note? base, required Note local, required Note remote}) {
  final bp = {for (final p in base?.pages ?? const <NotePage>[]) p.id: p};
  final lp = {for (final p in local.pages) p.id: p};
  final rp = {for (final p in remote.pages) p.id: p};

  final kept = <String, NotePage>{};
  for (final id in {...lp.keys, ...rp.keys}) {
    final b = bp[id], l = lp[id], r = rp[id];
    if (l != null && r != null) {
      kept[id] = _mergePage(b, l, r);
    } else if (l != null) {
      if (b == null || _pageChanged(b, l)) kept[id] = l;
    } else if (r != null) {
      if (b == null || _pageChanged(b, r)) kept[id] = r;
    }
  }

  // Order: local order, then remote-only pages after their nearest preceding remote page.
  final order = <String>[for (final p in local.pages) if (kept.containsKey(p.id)) p.id];
  final remoteIds = remote.pages.map((p) => p.id).toList();
  for (var i = 0; i < remoteIds.length; i++) {
    final id = remoteIds[i];
    if (!kept.containsKey(id) || order.contains(id)) continue;
    var insertAt = 0;
    for (var j = i - 1; j >= 0; j--) {
      final idx = order.indexOf(remoteIds[j]);
      if (idx != -1) {
        insertAt = idx + 1;
        break;
      }
    }
    order.insert(insertAt, id);
  }

  final newer = remote.modified.isAfter(local.modified) ? remote : local;
  final assets = <String, Uint8List>{...remote.assets, ...local.assets};
  return newer.copyWith(
    pages: [for (final id in order) kept[id]!],
    assets: assets,
    modified: newer.modified,
  );
}

bool _pageChanged(NotePage base, NotePage other) => _sig(base.toJson()) != _sig(other.toJson());

NotePage _mergePage(NotePage? b, NotePage l, NotePage r) {
  final bm = {for (final e in b?.elements ?? const <Element>[]) e.id: e};
  final lm = {for (final e in l.elements) e.id: e};
  final rm = {for (final e in r.elements) e.id: e};

  final out = <Element>[];
  for (final le in l.elements) {
    final be = bm[le.id], re = rm[le.id];
    if (re != null) {
      if (_sameEl(le, re)) {
        out.add(le);
      } else if (be != null && _sameEl(le, be)) {
        out.add(re);
      } else if (be != null && _sameEl(re, be)) {
        out.add(le);
      } else {
        out.add(le);
        out.add(re.withId(newId()));
      }
    } else {
      // remote deleted it (or never had it)
      if (be == null || !_sameEl(le, be)) out.add(le);
    }
  }
  for (final re in r.elements) {
    if (lm.containsKey(re.id)) continue;
    final be = bm[re.id];
    if (be == null || !_sameEl(re, be)) out.add(re);
  }

  // Page properties: take whichever side changed them.
  final base = b ?? l;
  final useRemoteProps = _sig(_pageProps(l)) == _sig(_pageProps(base)) && _sig(_pageProps(r)) != _sig(_pageProps(base));
  final props = useRemoteProps ? r : l;
  return NotePage(
    id: l.id,
    width: props.width,
    height: l.height > r.height ? l.height : r.height,
    templateOverride: props.templateOverride,
    pdf: props.pdf,
    elements: out,
  );
}
