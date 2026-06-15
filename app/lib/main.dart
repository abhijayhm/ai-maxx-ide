import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/background/workbench_foreground_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  WorkbenchForegroundService.init();
  runApp(const ProviderScope(child: AiMaxxIdeApp()));
}
