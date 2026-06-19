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
    final maxWin = [stats.win1, stats.win2, stats.win3]
        .fold<int>(1, (m, v) => v > m ? v : m);

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
            ],
          ),
          const SizedBox(height: 16),
          _WinBar(label: '1 try', value: stats.win1, max: maxWin),
          const SizedBox(height: 8),
          _WinBar(label: '2 tries', value: stats.win2, max: maxWin),
          const SizedBox(height: 8),
          _WinBar(label: '3 tries', value: stats.win3, max: maxWin),
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

class _WinBar extends StatelessWidget {
  const _WinBar({required this.label, required this.value, required this.max});

  final String label;
  final int value;
  final int max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 16,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
