import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';

/// Desktop keyboard shortcuts — traders work with the keyboard, not the
/// mouse. C/W/S switch the Basis Monitor's commodity filter, 1-4 jump
/// between the main sections, B toggles the CullyAI panel.
///
/// These are plain, unmodified letter/digit keys, so without a guard,
/// typing "s" or "c" into *any* text field anywhere in the app (chat
/// input, add-position dialog, search boxes, etc.) would also fire these
/// bindings as a side effect. [_typingInTextField] checks whether an
/// editable text field currently holds focus.
///
/// This deliberately does *not* use [CallbackShortcuts]: its internal
/// `Focus.onKeyEvent` returns `KeyEventResult.handled` whenever a key
/// matches one of its `SingleActivator`s, regardless of what the bound
/// callback actually does — so wrapping the callback in a guard that
/// no-ops while typing still left the key event marked "handled" and
/// swallowed before it could reach the focused text field, and the
/// letter itself never appeared. Owning the `Focus.onKeyEvent` handler
/// directly lets the guard return `KeyEventResult.ignored` instead,
/// letting the untouched event continue on to the text field.
class CroplooShortcuts extends ConsumerWidget {
  final Widget child;

  const CroplooShortcuts({super.key, required this.child});

  static bool _typingInTextField() {
    // `EditableText` builds `Focus(focusNode: widget.focusNode, child: this)`
    // around itself, so the focused node's own `context` always resolves to
    // that wrapping `Focus` widget, never to `EditableText` — walking
    // FocusNode.parent and comparing `.widget is EditableText` can never
    // match. `EditableText` is instead an *Element-tree* ancestor of that
    // Focus node, which is what this walks to find it.
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    var found = false;
    context.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyC): () =>
          ref.read(commodityFilterProvider.notifier).state = 'ZC',
      const SingleActivator(LogicalKeyboardKey.keyW): () =>
          ref.read(commodityFilterProvider.notifier).state = 'ZW',
      const SingleActivator(LogicalKeyboardKey.keyS): () =>
          ref.read(commodityFilterProvider.notifier).state = 'ZS',
      const SingleActivator(LogicalKeyboardKey.keyB): () => ref
          .read(cullyPanelOpenProvider.notifier)
          .update((open) => !open),
      const SingleActivator(LogicalKeyboardKey.digit1): () => context.go('/'),
      const SingleActivator(LogicalKeyboardKey.digit2): () => context.go('/basis'),
      const SingleActivator(LogicalKeyboardKey.digit3): () => context.go('/usda'),
      const SingleActivator(LogicalKeyboardKey.digit4): () => context.go('/alerts'),
    };

    return Focus(
      // No autofocus here: this Focus node intercepts key events by
      // walking up the focus tree from whatever currently holds focus, so
      // this ancestor Focus node doesn't need to hold focus itself — and
      // requesting it on every mount previously risked yanking focus away
      // from a text field the user had just clicked into.
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (_typingInTextField()) return KeyEventResult.ignored;
        for (final entry in bindings.entries) {
          if (entry.key.accepts(event, HardwareKeyboard.instance)) {
            entry.value();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
