import 'package:flutter_riverpod/flutter_riverpod.dart';

class Test extends Notifier<int> {
  Test(this.arg);
  final String arg;

  @override
  int build() => 0;
}
