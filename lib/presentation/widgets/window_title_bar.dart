import 'dart:async';

import 'package:flutter/material.dart';

import '../../platform/desktop_window_service.dart';

class WindowTitleBar extends StatefulWidget {
  const WindowTitleBar({
    super.key,
    required this.windowService,
    this.immersive = false,
  });

  final DesktopWindowService windowService;
  final bool immersive;

  @override
  State<WindowTitleBar> createState() => _WindowTitleBarState();
}

class _WindowTitleBarState extends State<WindowTitleBar> {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMaximized());
  }

  Future<void> _loadMaximized() async {
    final maximized = await widget.windowService.isMaximized();
    if (!mounted) return;
    setState(() => _maximized = maximized);
  }

  Future<void> _toggleMaximize() async {
    await widget.windowService.toggleMaximize();
    final maximized = await widget.windowService.isMaximized();
    if (!mounted) return;
    setState(() => _maximized = maximized);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('window-title-bar'),
      color: widget.immersive
          ? const Color(0xA60B0B0F)
          : const Color(0xFF111117),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showLabel = constraints.maxWidth >= 520;
            return Stack(
              children: [
                Positioned(
                  left: 14,
                  top: 0,
                  bottom: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary
                              .withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(
                          Icons.graphic_eq_rounded,
                          size: 15,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      if (showLabel) ...[
                        const SizedBox(width: 9),
                        const Text(
                          '音乐聚合',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  left: showLabel ? 105 : 48,
                  right: 138,
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    key: const Key('window-drag-region'),
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) {
                      unawaited(widget.windowService.startDragging());
                    },
                    onDoubleTap: () {
                      unawaited(_toggleMaximize());
                    },
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _WindowCircleButton(
                        key: const Key('window-minimize'),
                        tooltip: '最小化',
                        icon: Icons.remove,
                        baseColor: const Color(0xFF24242C),
                        hoverColor: const Color(0xFF3A3A42),
                        onPressed: widget.windowService.minimize,
                      ),
                      _WindowCircleButton(
                        key: const Key('window-maximize'),
                        tooltip: _maximized ? '还原' : '最大化',
                        icon: _maximized
                            ? Icons.filter_none_rounded
                            : Icons.crop_square_rounded,
                        baseColor: const Color(0xFF1E3025),
                        hoverColor: const Color(0xFF275C3A),
                        onPressed: _toggleMaximize,
                      ),
                      _WindowCircleButton(
                        key: const Key('window-close'),
                        tooltip: '关闭',
                        icon: Icons.close,
                        baseColor: const Color(0xFF352226),
                        hoverColor: const Color(0xFF8F3438),
                        onPressed: widget.windowService.close,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WindowCircleButton extends StatefulWidget {
  const _WindowCircleButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.baseColor,
    required this.hoverColor,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color baseColor;
  final Color hoverColor;
  final Future<void> Function() onPressed;

  @override
  State<_WindowCircleButton> createState() => _WindowCircleButtonState();
}

class _WindowCircleButtonState extends State<_WindowCircleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(widget.onPressed()),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _hovered ? widget.hoverColor : widget.baseColor,
                  ),
                  child: Icon(widget.icon, size: 14, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
