import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';

import '../../core/theme/theme_providers.dart';
import '../../data/providers.dart';
import '../../features/auth/auth_session.dart';
import '../../shared/models/models.dart';

/// Polls for newly-triggered alerts and surfaces them as native OS
/// notifications (Windows/macOS/Linux) alongside the in-app Alerts screen.
///
/// There's no push/websocket channel for alerts yet, so this just re-fetches
/// on an interval and diffs against the last-seen id set. The first poll
/// after (re)starting only seeds that set — it never notifies for alerts
/// that already existed before the service started, so logging in doesn't
/// replay the user's whole alert history as a flood of desktop popups.
class AlertNotificationService {
  AlertNotificationService(this._ref);

  final Ref _ref;
  Timer? _timer;
  Set<int>? _seenAlertIds;

  static const _pollInterval = Duration(seconds: 60);

  void start() {
    _timer?.cancel();
    _seenAlertIds = null;
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
    unawaited(_poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    final List<CroplooAlert> alerts;
    try {
      alerts = await _ref.read(repositoryProvider).alerts();
    } catch (_) {
      return; // offline/transient — the next tick will retry.
    }

    final seen = _seenAlertIds;
    if (seen == null) {
      _seenAlertIds = alerts.map((a) => a.id).toSet();
      return;
    }

    final newAlerts = alerts.where((a) => !seen.contains(a.id));
    seen.addAll(alerts.map((a) => a.id));

    for (final alert in newAlerts) {
      await _notify(alert);
    }
  }

  Future<void> _notify(CroplooAlert alert) async {
    final notification = LocalNotification(title: alert.title, body: alert.body);
    await notification.show();
  }
}

/// Keeps [AlertNotificationService] running for as long as someone is
/// logged in; watch this from the app root so it starts/stops with the
/// session automatically.
final alertNotificationServiceProvider = Provider<void>((ref) {
  final desktopNotifications = ref.watch(
    themeSettingsProvider.select((settings) => settings.desktopNotifications),
  );
  if (ref.watch(authSessionProvider) == null || !desktopNotifications) return;

  final service = AlertNotificationService(ref);
  service.start();
  ref.onDispose(service.stop);
});
