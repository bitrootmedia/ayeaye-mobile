/// Tolerant JSON readers.
///
/// The server is allowed to surprise us: a field can arrive null, as a number
/// where a string was documented, or missing entirely. A mobile client that
/// throws on that shows a red screen where it could have shown a blank field,
/// so every generated model reads through these.
String? asString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

int? asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double? asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

bool? asBool(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == '1';
  return null;
}

/// Parses both `2026-09-09` and full ISO timestamps. Dates without a zone are
/// read as local so "due today" lines up with the phone's calendar.
DateTime? asDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  final s = asString(v);
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}

Map<String, dynamic>? asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.cast<String, dynamic>();
  return null;
}

List<dynamic> asList(dynamic v) {
  if (v is List) return v;
  return const [];
}

/// `yyyy-MM-dd` — the shape every `format: date` field on the API wants.
String? fmtDate(DateTime? d) {
  if (d == null) return null;
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

String? fmtDateTime(DateTime? d) => d?.toUtc().toIso8601String();
