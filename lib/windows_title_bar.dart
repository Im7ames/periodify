import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

bool get usesWindowsTitleBar =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

Future<void> configureWindowsTitleBar() async {
  await windowManager.ensureInitialized();
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
  await windowManager.setMinimumSize(const Size(360, 360));
}

class WindowsTitleBar extends StatelessWidget implements PreferredSizeWidget {
  const WindowsTitleBar({
    super.key,
    required this.title,
    this.leading,
    this.navigation,
    this.actions = const [],
  });

  final Widget title;
  final Widget? leading;
  final Widget? navigation;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final caption = DragToMoveArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child: DefaultTextStyle(
            style: theme.textTheme.titleSmall!.copyWith(
              fontWeight: FontWeight.w700,
            ),
            child: title,
          ),
        ),
      ),
    );
    return Material(
      color: colors.surfaceContainerLow,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        child: SizedBox(
          height: preferredSize.height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (leading case final leading?) Center(child: leading),
              if (navigation case final navigation?) ...[
                caption,
                Center(child: navigation),
                const Expanded(child: DragToMoveArea(child: SizedBox.expand())),
              ] else
                Expanded(child: caption),
              ...actions.map((action) => Center(child: action)),
              const _WindowControls(),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowControls extends StatefulWidget {
  const _WindowControls();

  @override
  State<_WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<_WindowControls> with WindowListener {
  bool? maximized;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    readWindowState();
  }

  Future<void> readWindowState() async {
    final initialState = await windowManager.isMaximized();
    if (mounted && maximized == null) setState(() => maximized = initialState);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => maximized = false);

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _button(
        'Minimize',
        Icons.horizontal_rule_rounded,
        windowManager.minimize,
      ),
      maximized == true
          ? _button(
              'Restore',
              Icons.filter_none_rounded,
              windowManager.unmaximize,
            )
          : _button(
              'Maximize',
              Icons.crop_square_rounded,
              windowManager.maximize,
            ),
      _button('Close', Icons.close, windowManager.close, close: true),
    ],
  );

  Widget _button(
    String label,
    IconData icon,
    VoidCallback onPressed, {
    bool close = false,
  }) => SizedBox(
    width: 46,
    child: IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        overlayColor: close
            ? const WidgetStatePropertyAll(Color(0xffc42b1c))
            : null,
        foregroundColor: close
            ? WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.focused) ||
                        states.contains(WidgetState.pressed)
                    ? Colors.white
                    : null;
              })
            : null,
      ),
    ),
  );
}
