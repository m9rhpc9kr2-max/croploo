import 'package:flutter/foundation.dart';

/// True on platforms where we can spawn a real, separate native OS window
/// (desktop only — not web, not mobile). Used both for the login window's
/// hand-off to the dashboard window, and for detaching panels (e.g.
/// CullyAI chat) into their own window.
bool get supportsMultiWindow =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);
