import 'package:flutter/material.dart';

/// Dialog actions inherit typography and hit targets, but never page-button fill.
/// Apply this to the route, so nested dialogs and buttons inside content get the
/// same transparent surface without changing buttons on the underlying page.
Future<T?> showCardDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  builder: (dialogContext) => TextButtonTheme(
    data: TextButtonThemeData(
      style: (TextButtonTheme.of(dialogContext).style ?? const ButtonStyle())
          .copyWith(
            backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(0),
            shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
    ),
    child: Builder(builder: builder),
  ),
);
