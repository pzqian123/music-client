import 'package:flutter/material.dart';

import '../platform/desktop_window_service.dart';
import 'widgets/window_title_bar.dart';

class AppWindowChrome extends StatelessWidget {
  const AppWindowChrome({
    super.key,
    required this.windowService,
    required this.child,
    this.showWindowControls = true,
    this.immersive = false,
  });

  final DesktopWindowService windowService;
  final Widget child;
  final bool showWindowControls;
  final bool immersive;

  @override
  Widget build(BuildContext context) {
    if (!showWindowControls) return child;
    return Column(
      children: [
        WindowTitleBar(windowService: windowService, immersive: immersive),
        Expanded(child: child),
      ],
    );
  }
}
