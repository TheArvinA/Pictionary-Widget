import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/util/today.dart';
import '../../models/app_user.dart';
import '../../models/player_round.dart';
import '../../widgets/error_state.dart';

final _userProvider = StreamProvider.autoDispose<AppUser?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).watchUser(uid);
});

final _selfRoundProvider = StreamProvider.autoDispose<PlayerRound?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).watchPlayerRound(
        date: todayKey(),
        drawerId: uid,
      );
});

// The owner can read their own secret word from its owner-only private doc.
final _myWordProvider = StreamProvider.autoDispose<String?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).watchMyChosenWord(
        date: todayKey(),
        drawerId: uid,
      );
});

final _friendDrawingsProvider =
    StreamProvider.autoDispose.family<List<PlayerRound>, List<String>>(
  (ref, friendIds) {
    return ref.watch(firestoreServiceProvider).watchFriendDrawings(
          date: todayKey(),
          friendIds: friendIds,
        );
  },
);

class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(_userProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("Today's results")),
      body: user.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: 'Something went wrong',
          onRetry: () => ref.invalidate(_userProvider),
        ),
        data: (appUser) {
          if (appUser == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "We couldn't load your profile. Try again later.",
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _ResultsBody(user: appUser);
        },
      ),
    );
  }
}

class _ResultsBody extends ConsumerWidget {
  const _ResultsBody({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selfRound = ref.watch(_selfRoundProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daily summary',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  _SummaryRow(
                    icon: Icons.local_fire_department,
                    label: 'Streak',
                    value: '${user.streakCount} '
                        '${user.streakCount == 1 ? 'day' : 'days'}',
                  ),
                  const Divider(height: 28),
                  selfRound.when(
                    loading: () => const _SummaryRow(
                      icon: Icons.brush,
                      label: 'Your word',
                      value: '…',
                    ),
                    error: (e, _) => const _SummaryRow(
                      icon: Icons.brush,
                      label: 'Your word',
                      value: 'unavailable',
                    ),
                    data: (round) {
                      final submitted = round?.hasSubmittedDrawing ?? false;
                      final word = ref.watch(_myWordProvider);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SummaryRow(
                            icon: Icons.brush,
                            label: 'Your word',
                            value: word.maybeWhen(
                              data: (w) => w ?? 'not picked',
                              orElse: () => '…',
                            ),
                          ),
                          const SizedBox(height: 16),
                          _SummaryRow(
                            icon: submitted
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            label: 'Your drawing',
                            value: submitted ? 'submitted' : 'not submitted',
                          ),
                          const Divider(height: 28),
                          // Anti-cheat: only read friends' rounds once the
                          // user has submitted their own drawing. Until then
                          // the read is forbidden by firestore.rules, so we
                          // don't subscribe to it at all.
                          if (submitted)
                            _FriendsDrewRow(friendIds: user.friendIds)
                          else
                            const _SummaryRow(
                              icon: Icons.people,
                              label: 'Friends drew',
                              value: 'draw first',
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _FriendsDrewRow extends ConsumerWidget {
  const _FriendsDrewRow({required this.friendIds});
  final List<String> friendIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(_friendDrawingsProvider(friendIds));
    return friends.when(
      loading: () => const _SummaryRow(
        icon: Icons.people,
        label: 'Friends drew',
        value: '…',
      ),
      error: (e, _) => const _SummaryRow(
        icon: Icons.people,
        label: 'Friends drew',
        value: 'unavailable',
      ),
      data: (rounds) {
        final count = rounds.where((r) => r.hasSubmittedDrawing).length;
        return _SummaryRow(
          icon: Icons.people,
          label: 'Friends drew',
          value: '$count ${count == 1 ? 'drawing' : 'drawings'}',
        );
      },
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 16),
        Expanded(
          child: Text(label, style: theme.textTheme.bodyLarge),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
