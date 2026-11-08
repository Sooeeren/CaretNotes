import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Combines exported ink with original PDF pages. [sources] has one entry per output
/// page: null for plain pages, or (original PDF bytes, page index) for imported pages.
typedef PdfStamper = Uint8List? Function(List<(Uint8List, int)?> sources, Uint8List overlayPdf);

typedef _Doc = Pointer<Void>;

final class _FileWrite extends Struct {
  @Int32()
  external int version;
  external Pointer<NativeFunction<Int32 Function(Pointer<_FileWrite>, Pointer<Void>, UnsignedLong)>> writeBlock;
}

/// PDFium-based stamping: imports each original page and draws the ink page over it
/// as a form XObject, so the original page content stays vector and full quality.
class PdfiumStamper {
  final DynamicLibrary _lib;
  PdfiumStamper._(this._lib);

  static PdfiumStamper? tryLoad([String? path]) {
    try {
      final lib = DynamicLibrary.open(path ?? (Platform.isWindows ? 'pdfium.dll' : 'libpdfium.so'));
      lib.lookup('FPDF_ImportPagesByIndex');
      lib.lookup('FPDF_NewXObjectFromPage');
      // No-op when pdfrx already initialized the library (PDFium guards repeated init).
      lib.lookupFunction<Void Function(), void Function()>('FPDF_InitLibrary')();
      return PdfiumStamper._(lib);
    } catch (_) {
      return null;
    }
  }

  late final _loadMem = _lib.lookupFunction<_Doc Function(Pointer<Void>, Int32, Pointer<Utf8>), _Doc Function(Pointer<Void>, int, Pointer<Utf8>)>('FPDF_LoadMemDocument');
  late final _create = _lib.lookupFunction<_Doc Function(), _Doc Function()>('FPDF_CreateNewDocument');
  late final _close = _lib.lookupFunction<Void Function(_Doc), void Function(_Doc)>('FPDF_CloseDocument');
  late final _import = _lib.lookupFunction<Int32 Function(_Doc, _Doc, Pointer<Int32>, UnsignedLong, Int32), int Function(_Doc, _Doc, Pointer<Int32>, int, int)>(
      'FPDF_ImportPagesByIndex');
  late final _newXObj = _lib.lookupFunction<Pointer<Void> Function(_Doc, _Doc, Int32), Pointer<Void> Function(_Doc, _Doc, int)>('FPDF_NewXObjectFromPage');
  late final _closeXObj = _lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('FPDF_CloseXObject');
  late final _formFromXObj =
      _lib.lookupFunction<Pointer<Void> Function(Pointer<Void>), Pointer<Void> Function(Pointer<Void>)>('FPDF_NewFormObjectFromXObject');
  late final _loadPage = _lib.lookupFunction<Pointer<Void> Function(_Doc, Int32), Pointer<Void> Function(_Doc, int)>('FPDF_LoadPage');
  late final _closePage = _lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('FPDF_ClosePage');
  late final _insert = _lib.lookupFunction<Void Function(Pointer<Void>, Pointer<Void>), void Function(Pointer<Void>, Pointer<Void>)>('FPDFPage_InsertObject');
  late final _generate = _lib.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('FPDFPage_GenerateContent');
  late final _save = _lib.lookupFunction<Int32 Function(_Doc, Pointer<_FileWrite>, Uint32), int Function(_Doc, Pointer<_FileWrite>, int)>('FPDF_SaveAsCopy');

  static BytesBuilder? _sink;
  static int _write(Pointer<_FileWrite> self, Pointer<Void> data, int size) {
    _sink!.add(data.cast<Uint8>().asTypedList(size));
    return 1;
  }

  Uint8List? stamp(List<(Uint8List, int)?> sources, Uint8List overlayPdf) {
    final buffers = <Pointer<Uint8>>[];
    final opened = <_Doc>[];
    _Doc open(Uint8List bytes) {
      final buf = calloc<Uint8>(bytes.length);
      buf.asTypedList(bytes.length).setAll(0, bytes);
      buffers.add(buf);
      final d = _loadMem(buf.cast(), bytes.length, nullptr);
      if (d == nullptr) throw StateError('PDFium could not open a document');
      opened.add(d);
      return d;
    }

    final idx = calloc<Int32>();
    final cb = NativeCallable<Int32 Function(Pointer<_FileWrite>, Pointer<Void>, UnsignedLong)>.isolateLocal(_write, exceptionalReturn: 0);
    final fw = calloc<_FileWrite>();
    try {
      final overlay = open(overlayPdf);
      final srcDocs = <Uint8List, _Doc>{};
      final dest = _create();
      if (dest == nullptr) return null;
      opened.add(dest);
      for (var i = 0; i < sources.length; i++) {
        final s = sources[i];
        if (s == null) {
          idx.value = i;
          if (_import(dest, overlay, idx, 1, i) == 0) return null;
          continue;
        }
        final src = srcDocs[s.$1] ??= open(s.$1);
        idx.value = s.$2;
        if (_import(dest, src, idx, 1, i) == 0) return null;
        final xobj = _newXObj(dest, overlay, i);
        if (xobj == nullptr) return null;
        final form = _formFromXObj(xobj);
        final page = _loadPage(dest, i);
        if (form == nullptr || page == nullptr) return null;
        _insert(page, form);
        _generate(page);
        _closePage(page);
        _closeXObj(xobj);
      }
      fw.ref
        ..version = 1
        ..writeBlock = cb.nativeFunction;
      _sink = BytesBuilder(copy: true);
      if (_save(dest, fw, 0) == 0) return null;
      return _sink!.takeBytes();
    } finally {
      _sink = null;
      for (final d in opened.reversed) {
        _close(d);
      }
      for (final b in buffers) {
        calloc.free(b);
      }
      calloc.free(idx);
      calloc.free(fw);
      cb.close();
    }
  }
}
