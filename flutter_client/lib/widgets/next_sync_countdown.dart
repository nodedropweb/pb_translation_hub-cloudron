import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../providers/sync_provider.dart';
import '../theme/app_theme.dart';

/// Shows "Nächste automatische Synchronisation in X Tagen X Std X Min" so
/// users notice the background auto-sync exists and know when it next runs.
class NextSyncCountdown extends StatefulWidget {
  final SyncStatus syncStatus;
  final ThemeAttributes attrs;

  const NextSyncCountdown({
    super.key,
    required this.syncStatus,
    required this.attrs,
  });

  @override
  State<NextSyncCountdown> createState() => _NextSyncCountdownState();
}

class _NextSyncCountdownState extends State<NextSyncCountdown> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatRemaining(Duration d) {
    if (d.isNegative) return 'in Kürze';
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    final parts = <String>[];
    if (days > 0) parts.add('$days Tag${days == 1 ? '' : 'e'}');
    if (hours > 0) parts.add('$hours Std');
    if (days == 0 && minutes > 0) parts.add('$minutes Min');
    if (parts.isEmpty) return 'in Kürze';
    return 'in ${parts.join(' ')}';
  }

  @override
  Widget build(BuildContext context) {
    final nextAt = widget.syncStatus.nextAutoSyncAt;
    if (nextAt == null) return const SizedBox.shrink();

    final remaining = nextAt.difference(DateTime.now());
    final attrs = widget.attrs;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: attrs.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: attrs.borderMain),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.clock, size: 13, color: attrs.textMuted),
          const SizedBox(width: 6),
          Text(
            'Nächste automatische Synchronisation ${_formatRemaining(remaining)}',
            style: TextStyle(
              color: attrs.textMuted,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
