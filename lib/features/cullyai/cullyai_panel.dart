import 'dart:convert';
import 'dart:math' as math;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';
import '../../core/utils/desktop_platform.dart';
import '../../data/providers.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/controls.dart';
import '../../shared/widgets/formatted_ai_text.dart';
import '../auth/auth_session.dart';
import 'ai_chart_widget.dart';

const _quickPrompts = [
  "Today's corn outlook",
  'Explain this basis spike',
  'USDA report summary',
];

/// Right-hand CullyAI chat panel (320px, collapsible). Can be popped out
/// into its own native OS window via the detach button — see
/// [CullyAiWindowApp] and the `kind: 'cullyai'` window payload handled in
/// `main.dart`.
class CullyAiPanel extends ConsumerWidget {
  const CullyAiPanel({super.key});

  Future<void> _detach(WidgetRef ref) async {
    ref.read(cullyPanelOpenProvider.notifier).state = false;
    final session = ref.read(authSessionProvider);
    final payload = jsonEncode({
      'kind': 'cullyai',
      if (session != null) ...{
        'accessToken': session.accessToken,
        'email': session.email,
        'username': session.username,
        'name': session.name,
      },
    });
    final controller = await DesktopMultiWindow.createWindow(payload);
    await controller.setFrame(const Rect.fromLTWH(0, 0, 420, 720));
    await controller.center();
    await controller.setTitle('CullyAI');
    await controller.show();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final open = ref.watch(cullyPanelOpenProvider);

    if (!open) {
      return Container(
        width: 48,
        decoration: BoxDecoration(
          color: theme.bgPrimary,
          border: Border(left: BorderSide(color: theme.bgBorder)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            CroplooIconButton(
              icon: PhosphorIconsRegular.sparkle,
              size: 36,
              iconColor: theme.accent,
              backgroundColor: theme.bgElevated,
              onPressed: () =>
                  ref.read(cullyPanelOpenProvider.notifier).state = true,
            ),
          ],
        ),
      );
    }

    final panelWidth = ref.watch(cullyPanelWidthProvider);

    return Row(
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: (details) {
              final newWidth = (panelWidth - details.delta.dx).clamp(240.0, 600.0);
              ref.read(cullyPanelWidthProvider.notifier).state = newWidth;
            },
            child: Container(
              width: 6,
              color: Colors.transparent,
              child: Center(
                child: Container(
                  width: 2,
                  height: 48,
                  decoration: BoxDecoration(
                    color: theme.border,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(
          width: panelWidth,
          decoration: BoxDecoration(
            color: theme.bgPrimary,
            border: Border(left: BorderSide(color: theme.bgBorder)),
          ),
          child: CullyAiChatView(
            headerActions: [
              CroplooIconButton(
                icon: PhosphorIconsRegular.filePdf,
                size: 32,
                iconColor: theme.textSecondary,
                onPressed: () => launchUrl(
                  Uri.parse(ref.read(repositoryProvider).weeklyReportUrl()),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              if (supportsMultiWindow)
                CroplooIconButton(
                  icon: PhosphorIconsRegular.arrowSquareOut,
                  size: 32,
                  iconColor: theme.textSecondary,
                  onPressed: () => _detach(ref),
                ),
              CroplooIconButton(
                icon: PhosphorIconsRegular.x,
                size: 32,
                iconColor: theme.textSecondary,
                onPressed: () =>
                    ref.read(cullyPanelOpenProvider.notifier).state = false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The chat itself (header, message history, quick prompts, input) —
/// shared between the docked [CullyAiPanel] and the standalone
/// `CullyAiWindowApp` window, which supply their own [headerActions]
/// (detach/close behave differently docked vs. in a separate window).
class CullyAiChatView extends ConsumerStatefulWidget {
  final List<Widget> headerActions;
  final Widget? headerLeading;

  const CullyAiChatView({
    super.key,
    required this.headerActions,
    this.headerLeading,
  });

  @override
  ConsumerState<CullyAiChatView> createState() => _CullyAiChatViewState();
}

class _CullyAiChatViewState extends ConsumerState<CullyAiChatView> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = preset ?? _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    final future = ref.read(cullyThreadsProvider.notifier).send(text);
    // Keep pinned to bottom while streaming.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    await future;
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final threadsState = ref.watch(cullyThreadsProvider);
    final messages = threadsState.active.messages;
    final isStreaming = threadsState.active.streaming;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.headerLeading != null) widget.headerLeading!,
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.bgBorder)),
          ),
          child: Row(
            children: [
              Icon(PhosphorIconsRegular.sparkle, color: theme.accent, size: 16),
              const SizedBox(width: 8),
              Text('CULLYAI', style: CroplooText.label),
              const Spacer(),
              ...widget.headerActions,
            ],
          ),
        ),
        _ThreadTabBar(threadsState: threadsState),
        // Chat history
        Expanded(
          child: messages.isEmpty
              ? _EmptyChat(onPrompt: (p) => _send(p), showWelcomeBack: true)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, i) => _ChatBubble(
                    message: messages[i],
                    isThinking: isStreaming &&
                        i == messages.length - 1 &&
                        !messages[i].fromUser,
                  ),
                ),
        ),
        // Quick prompts (when history exists, show compact row)
        if (messages.isNotEmpty)
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final p in _quickPrompts)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _QuickPromptChip(text: p, onTap: () => _send(p)),
                  ),
              ],
            ),
          ),
        // Input
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.bgBorder)),
          ),
          child: Row(
            children: [
              Expanded(
                child: CroplooTextField(
                  controller: _controller,
                  hintText: 'Ask about markets...',
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              CroplooIconButton(
                icon: PhosphorIconsRegular.play,
                size: 36,
                iconColor: theme.accent,
                onPressed: _send,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Horizontal strip of chat-thread tabs (browser-tab style) so several
/// independent CullyAI conversations can stay open side by side — each
/// keeps its own history and in-flight streaming state (see
/// [CullyThreadsNotifier] in providers.dart). A small pulsing dot marks a
/// tab that's still streaming while the user has switched away from it.
class _ThreadTabBar extends ConsumerWidget {
  final CullyThreadsState threadsState;

  const _ThreadTabBar({required this.threadsState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    return Container(
      height: 34,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.bgBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final thread in threadsState.threads)
                  _ThreadTab(
                    thread: thread,
                    active: thread.id == threadsState.activeId,
                    closable: threadsState.threads.length > 1,
                    onTap: () =>
                        ref.read(cullyThreadsProvider.notifier).switchTo(thread.id),
                    onClose: () =>
                        ref.read(cullyThreadsProvider.notifier).closeThread(thread.id),
                  ),
              ],
            ),
          ),
          CroplooIconButton(
            icon: PhosphorIconsRegular.plus,
            size: 28,
            iconColor: theme.textSecondary,
            onPressed: () => ref.read(cullyThreadsProvider.notifier).newThread(),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _ThreadTab extends StatelessWidget {
  final ChatThread thread;
  final bool active;
  final bool closable;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _ThreadTab({
    required this.thread,
    required this.active,
    required this.closable,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? theme.bgSurface : Colors.transparent,
          border: Border(
            right: BorderSide(color: theme.bgBorder),
            bottom: BorderSide(
                color: active ? theme.accent : Colors.transparent, width: 2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (thread.streaming) ...[
              Container(
                width: 5,
                height: 5,
                color: theme.accent,
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                thread.title,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: CroplooText.bodyStrong.copyWith(
                  fontSize: 11,
                  color: active ? theme.textPrimary : theme.textMuted,
                ),
              ),
            ),
            if (closable) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: onClose,
                child: Icon(PhosphorIconsRegular.x,
                    size: 12, color: theme.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyChat extends ConsumerWidget {
  final void Function(String) onPrompt;
  final bool showWelcomeBack;

  const _EmptyChat({required this.onPrompt, this.showWelcomeBack = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = CroplooTheme.of(context);
    final welcomeBack = showWelcomeBack
        ? ref.watch(cullyAiContextProvider).valueOrNull?.welcomeBack
        : null;
    final username = ref.watch(authSessionProvider)?.username;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (welcomeBack != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: theme.settings.useBorders ? theme.accent.withValues(alpha: 0.35) : Colors.transparent),
              ),
              child: Text(welcomeBack,
                  style: CroplooText.body.copyWith(fontSize: 12, color: theme.textPrimary)),
            ),
            const SizedBox(height: 16),
          ],
          if (username != null) ...[
            Text.rich(
              TextSpan(
                style: CroplooText.bodyStrong.copyWith(fontSize: 15),
                children: [
                  const TextSpan(text: 'Hey '),
                  TextSpan(
                    text: '@$username',
                    style: TextStyle(color: theme.accent),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text('Ask CullyAI about basis moves, USDA reports, or market direction.',
              style: CroplooText.body),
          const SizedBox(height: 20),
          Text('QUICK PROMPTS', style: CroplooText.label.copyWith(fontSize: 10)),
          const SizedBox(height: 10),
          for (final p in _quickPrompts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _QuickPromptChip(text: p, onTap: () => onPrompt(p)),
            ),
        ],
      ),
    );
  }
}

class _QuickPromptChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _QuickPromptChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.bgElevated,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: theme.bgBorder),
        ),
        child: Text(text,
            style: CroplooText.bodyStrong
                .copyWith(fontSize: 12, color: theme.textSecondary)),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isThinking;

  const _ChatBubble({required this.message, this.isThinking = false});

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final isUser = message.fromUser;
    final showThinkingIndicator = isThinking && message.text.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(isUser ? 'YOU' : 'CULLYAI',
              style: CroplooText.label.copyWith(
                  fontSize: 9,
                  color: isUser
                      ? theme.textMuted
                      : theme.accent)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isUser ? theme.bgElevated : theme.bgSurface,
              borderRadius: BorderRadius.zero,
              border: Border.all(
                  color: isUser
                      ? theme.bgBorder
                      : theme.accent.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isUser)
                  Text(
                    message.text.isEmpty ? '…' : message.text,
                    style: CroplooText.body
                        .copyWith(color: theme.textPrimary, fontSize: 13),
                  )
                else if (showThinkingIndicator)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _ThinkingIndicator(),
                      if (message.statusLabel != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          message.statusLabel!,
                          style: CroplooText.body
                              .copyWith(color: theme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ],
                  )
                else ...[
                  FormattedAiText(
                    text: message.text,
                    baseColor: theme.textPrimary,
                    headingColor: theme.textPrimary,
                    accentColor: theme.accent,
                  ),
                  if (isThinking) ...[
                    const SizedBox(height: 6),
                    const _ThinkingIndicator(compact: true),
                  ],
                ],
                for (final chart in message.charts)
                  AiChartWidget(spec: chart),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Modern "thinking" indicator for CullyAI: three square dots (sharp
/// corners, matching the app's [BorderRadius.zero] language) rising and
/// fading in a traveling wave. Shown full-size while waiting for the first
/// token, and in a smaller `compact` form trailing already-streamed text
/// while later tool-call turns are still in flight.
class _ThinkingIndicator extends StatefulWidget {
  final bool compact;

  const _ThinkingIndicator({this.compact = false});

  @override
  State<_ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<_ThinkingIndicator>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _controller.stop();
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final size = widget.compact ? 4.0 : 6.0;
    final gap = widget.compact ? 4.0 : 6.0;
    final travel = widget.compact ? 2.0 : 4.0;

    return SizedBox(
      height: size + travel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final t = (_controller.value + i * 0.18) % 1.0;
              final wave = (math.sin(t * 2 * math.pi) + 1) / 2; // 0..1
              return Padding(
                padding: EdgeInsets.only(right: i < 2 ? gap : 0),
                child: Transform.translate(
                  offset: Offset(0, -wave * travel),
                  child: Container(
                    width: size,
                    height: size,
                    color: theme.accent.withValues(alpha: 0.3 + wave * 0.7),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
