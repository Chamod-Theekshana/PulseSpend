import 'package:flutter_riverpod/flutter_riverpod.dart';

class MyNotifier extends Notifier<int> {
  MyNotifier(this.arg);
  final String arg;
  
  @override
  int build() => 0;
}

final myProvider = NotifierProvider.autoDispose.family<MyNotifier, int, String>(
  (String arg) => MyNotifier(arg),
);
