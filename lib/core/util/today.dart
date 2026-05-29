import 'package:intl/intl.dart';

String todayKey({DateTime? now}) {
  final n = (now ?? DateTime.now()).toUtc();
  return DateFormat('yyyy-MM-dd').format(n);
}
