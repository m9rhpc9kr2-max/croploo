import 'package:flutter/foundation.dart';

/// Tracks whether the mouse is currently over an "interactive" widget
/// (buttons, nav tiles, …) so [CursorOverlay]'s ring can grow the way the
/// marketing website's cursor does when hovering a button or card.
///
/// A counter rather than a bool: nested/overlapping hover regions can fire
/// enter/exit out of matching order (e.g. moving straight from one button
/// into another), and a bool would risk getting stuck "on".
class CursorHover {
  CursorHover._();

  /// Mirrors `ThemeSettings.customCursor`, kept in sync by [CroplooApp] on
  /// every rebuild (the same pattern `Fmt.configure` uses for formatting
  /// prefs) so widgets that hardcode `SystemMouseCursors.click` can suppress
  /// it in favor of [CursorOverlay]'s ring when the custom cursor is on.
  static bool enabled = true;

  static final ValueNotifier<int> count = ValueNotifier(0);

  static void enter() => count.value++;
  static void exit() => count.value = (count.value - 1).clamp(0, 1 << 30);
}
