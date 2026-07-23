import 'package:flutter_riverpod/flutter_riverpod.dart';

const double kDefaultSidebarWidth = 200.0;
const double kCollapsedSidebarWidth = 64.0;
const double kMinSidebarWidth = 64.0;
const double kMaxSidebarWidth = 320.0;

/// Current width of the desktop navigation sidebar.
final sidebarWidthProvider = StateProvider<double>((ref) => kDefaultSidebarWidth);

/// Whether the sidebar is collapsed to icon-only mode.
final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);
