import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// New random UUID v4 for any note object.
String newId() => _uuid.v4();
