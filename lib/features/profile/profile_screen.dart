import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/app_user.dart';
import '../../widgets/error_state.dart';

final _meProvider = StreamProvider.autoDispose<AppUser?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).watchUser(uid);
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(_meProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: me.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: 'Something went wrong',
          onRetry: () => ref.invalidate(_meProvider),
        ),
        data: (user) {
          if (user == null) return const Center(child: Text('No profile yet.'));
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(user.displayName,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text('Invite code: ${user.inviteCode}'),
                const SizedBox(height: 8),
                Text('Streak: ${user.streakCount} days'),
                const SizedBox(height: 24),
                _GuessStatsSection(stats: user.guessStats),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: () =>
                      ref.read(authServiceProvider).signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GuessStatsSection extends StatelessWidget {
  const _GuessStatsSection({required this.stats});

  final GuessStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Guessing stats', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        if (stats.isEmpty)
          Text(
            'No guesses yet.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: _StatTile(label: 'Correct', value: stats.correct),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(label: 'Missed', value: stats.failed),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(label: 'Hints used', value: stats.hintsUsed),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _AttemptsChart(stats: stats),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text('$value', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Vertical bar chart of how many guesses it took to solve drawings: an
/// "Attempts" header, one bar per attempt count (1/2/3) with the frequency
/// shown just above each bar and the attempt number labelled below it.
class _AttemptsChart extends StatelessWidget {
  const _AttemptsChart({required this.stats});

  final GuessStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = [stats.win1, stats.win2, stats.win3];
    final maxWin = values.fold<int>(1, (m, v) => v > m ? v : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Attempts', style: theme.textTheme.titleSmall),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < values.length; i++)
              Expanded(
                child: _AttemptBar(
                  guesses: i + 1,
                  frequency: values[i],
                  fraction: values[i] / maxWin,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _AttemptBar extends StatelessWidget {
  const _AttemptBar({
    required this.guesses,
    required this.frequency,
    required this.fraction,
  });

  final int guesses;
  final int frequency;
  final double fraction;

  static const _maxBarHeight = 96.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barHeight = frequency <= 0
        ? 0.0
        : (_maxBarHeight * fraction).clamp(6.0, _maxBarHeight);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Frequency, just above the bar.
          Text(
            '$frequency',
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: barHeight,
            child: FractionallySizedBox(
              widthFactor: 0.8, // 20% narrower than the column slot
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Number of guesses, on the bottom (x-axis).
          Text('$guesses', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
