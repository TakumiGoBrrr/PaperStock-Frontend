import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Clean (path-based) web URLs so query params like ?q=/?ref= survive on the
  // web build - needed for shared QOTD challenge links. No-op on mobile.
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  runApp(const ProviderScope(child: App()));
}
  