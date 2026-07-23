import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';
import 'controls.dart';

/// Rectangular, desktop-friendly calendar picker dialog.
///
/// Shows a monthly grid with simple prev/next navigation and rectangular
/// selection. Returns the chosen [DateTime] or null when cancelled.
Future<DateTime?> showCroplooCalendar({
  required BuildContext context,
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  final now = DateTime.now();
  final effectiveFirst = firstDate ?? DateTime(now.year - 5);
  final effectiveLast = lastDate ?? now;

  return showDialog<DateTime>(
    context: context,
    builder: (context) => _CalendarDialog(
      initialDate: initialDate,
      firstDate: effectiveFirst,
      lastDate: effectiveLast,
    ),
  );
}

class _CalendarDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const _CalendarDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_CalendarDialog> createState() => _CalendarDialogState();
}

class _CalendarDialogState extends State<_CalendarDialog> {
  late DateTime _selected;
  late DateTime _viewedMonth;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
    _viewedMonth = DateTime(_selected.year, _selected.month);
  }

  void _previousMonth() {
    setState(() {
      _viewedMonth = DateTime(_viewedMonth.year, _viewedMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _viewedMonth = DateTime(_viewedMonth.year, _viewedMonth.month + 1);
    });
  }

  List<DateTime> _daysInMonth() {
    final firstOfMonth = DateTime(_viewedMonth.year, _viewedMonth.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(_viewedMonth.year, _viewedMonth.month);
    final startOffset = firstOfMonth.weekday % 7;
    final totalCells = ((startOffset + daysInMonth) / 7).ceil() * 7;
    return List.generate(
      totalCells,
      (index) {
        final dayNumber = index - startOffset + 1;
        if (dayNumber < 1 || dayNumber > daysInMonth) {
          return DateTime(_viewedMonth.year, _viewedMonth.month, dayNumber);
        }
        return DateTime(_viewedMonth.year, _viewedMonth.month, dayNumber);
      },
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isInRange(DateTime date) =>
      !date.isBefore(widget.firstDate) && !date.isAfter(widget.lastDate);

  bool _isCurrentMonth(DateTime date) =>
      date.year == _viewedMonth.year && date.month == _viewedMonth.month;

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final days = _daysInMonth();
    final weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Dialog(
      backgroundColor: theme.bgSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    _monthYearLabel(_viewedMonth),
                    style: CroplooText.h3,
                  ),
                  const Spacer(),
                  CroplooIconButton(
                    icon: PhosphorIconsRegular.caretLeft,
                    size: 28,
                    iconColor: theme.textSecondary,
                    onPressed: _previousMonth,
                  ),
                  const SizedBox(width: 4),
                  CroplooIconButton(
                    icon: PhosphorIconsRegular.caretRight,
                    size: 28,
                    iconColor: theme.textSecondary,
                    onPressed: _nextMonth,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (final d in weekdays)
                    SizedBox(
                      width: 36,
                      child: Text(
                        d,
                        textAlign: TextAlign.center,
                        style: CroplooText.label
                            .copyWith(color: theme.textMuted, fontSize: 11),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final day in days)
                    _DayCell(
                      date: day,
                      selected: _isSameDay(day, _selected),
                      inRange: _isInRange(day),
                      currentMonth: _isCurrentMonth(day),
                      today: _isSameDay(day, DateTime.now()),
                      onTap: _isInRange(day) && _isCurrentMonth(day)
                          ? () => setState(() => _selected = day)
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CroplooButton(
                    label: 'Cancel',
                    variant: CroplooButtonVariant.ghost,
                    expanded: false,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    borderRadius: 0,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  CroplooButton(
                    label: 'Select',
                    expanded: false,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    borderRadius: 0,
                    onPressed: () => Navigator.of(context).pop(_selected),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _monthYearLabel(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[d.month - 1]} ${d.year}';
  }
}

class _DayCell extends StatelessWidget {
  final DateTime date;
  final bool selected;
  final bool inRange;
  final bool currentMonth;
  final bool today;
  final VoidCallback? onTap;

  const _DayCell({
    required this.date,
    required this.selected,
    required this.inRange,
    required this.currentMonth,
    required this.today,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    final Color textColor;
    if (!currentMonth) {
      textColor = Colors.transparent;
    } else if (selected) {
      textColor = theme.contrastColor(theme.accent);
    } else if (today) {
      textColor = theme.accent;
    } else if (!inRange) {
      textColor = theme.textMuted;
    } else {
      textColor = theme.textPrimary;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? theme.accent : Colors.transparent,
          borderRadius: BorderRadius.zero,
          border: today && !selected && theme.settings.useBorders ? Border.all(color: theme.accent) : null,
        ),
        child: Text(
          '${date.day}',
          style: CroplooText.bodyStrong.copyWith(
            fontSize: 13,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
