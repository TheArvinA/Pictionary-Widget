import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/util/today.dart';
import '../../models/app_user.dart';
import '../../models/guess.dart';
import '../../models/player_round.dart';
import '../../widgets/error_state.dart';

final _currentUserProvider = StreamProvider.autoDispose<AppUser?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).watchUser(uid);
});

final _myRoundProvider = StreamProvider.autoDispose<PlayerRound?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).watchPlayerRound(
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

// Your guess (if any) for a given friend's drawing today — drives the
// correct/incorrect badge on each tile. Reading a not-yet-created guess doc is
// allowed by firestore.rules (resource == null), so this never 403s.
final _myGuessProvider =
    StreamProvider.autoDispose.family<Guess?, String>((ref, drawerId) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).watchGuess(
        date: todayKey(),
        guesserId: uid,
        drawerId: drawerId,
      );
});

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myRound = ref.watch(_myRoundProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("Friends' drawings")),
      body: myRound.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: 'Something went wrong',
          onRetry: () => ref.invalidate(_myRoundProvider),
        ),
        data: (round) {
          // ANTI-CHEAT GATE: must submit your own drawing first.
          if (round == null || !round.hasSubmittedDrawing) {
            return _DrawFirstGate();
          }
          return const _FriendsFeed();
        },
      ),
    );
  }
}

class _DrawFirstGate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 16),
            Text(
              "Draw today's word first to see friends' drawings.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.brush),
              label: const Text('Draw now'),
              onPressed: () => context.go('/'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendsFeed extends ConsumerWidget {
  const _FriendsFeed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(_currentUserProvider);

    return user.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(
        message: 'Something went wrong',
        onRetry: () => ref.invalidate(_currentUserProvider),
      ),
      data: (appUser) {
        final friendIds = appUser?.friendIds ?? const <String>[];
        if (friendIds.isEmpty) {
          return const _EmptyState(
            message: 'Add some friends to see their daily drawings here.',
          );
        }

        final drawings = ref.watch(_friendDrawingsProvider(friendIds));
        return drawings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(
            message: 'Something went wrong',
            onRetry: () =>
                ref.invalidate(_friendDrawingsProvider(friendIds)),
          ),
          data: (rounds) {
            final byDrawer = {for (final r in rounds) r.drawerId: r};
            final submittedCount = rounds
                .where((r) => r.hasSubmittedDrawing && r.drawingUrl != null)
                .length;
            if (submittedCount == 0) {
              return const _EmptyState(
                message:
                    "None of your friends have drawn yet today. Check back later!",
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: friendIds.length,
              itemBuilder: (context, index) {
                final friendId = friendIds[index];
                final round = byDrawer[friendId];
                final hasDrawing = round != null &&
                    round.hasSubmittedDrawing &&
                    round.drawingUrl != null;
                if (!hasDrawing) {
                  return _PlaceholderTile(friendId: friendId);
                }
                return _DrawingTile(
                  friendId: friendId,
                  drawingUrl: round.drawingUrl!,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _DrawingTile extends ConsumerWidget {
  const _DrawingTile({
    required this.friendId,
    required this.drawingUrl,
  });
  final String friendId;
  final String drawingUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guess = ref.watch(_myGuessProvider(friendId)).valueOrNull;
    // Resolve this drawer's name per-uid; falls back to the uid while loading.
    final friendName =
        ref.watch(userDisplayNameProvider(friendId)).valueOrNull ?? friendId;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/guess/$friendId'),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: drawingUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) =>
                  const Center(child: CircularProgressIndicator()),
              errorWidget: (context, url, error) =>
                  const Center(child: Icon(Icons.broken_image_outlined)),
            ),
            // Bottom scrim: drawer's name (left) + your guess result (right),
            // so you can tell whose drawing it is and whether you've solved it.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        friendName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _GuessBadge(guess: guess),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small status badge for the feed tile: green check once you've guessed the
/// drawing correctly, red X once you're out of attempts without solving it, and
/// nothing while you haven't finished (so the tile stays tappable to keep going).
class _GuessBadge extends StatelessWidget {
  const _GuessBadge({required this.guess});
  final Guess? guess;

  @override
  Widget build(BuildContext context) {
    final g = guess;
    if (g == null) return const SizedBox.shrink();
    // completedAt is set by the submitGuess callable only when the round is
    // finished (solved or out of attempts).
    final finished = g.correct || g.completedAt != null;
    if (!finished) return const SizedBox.shrink();
    return Icon(
      g.correct ? Icons.check_circle : Icons.cancel,
      color: g.correct ? Colors.green : Colors.red,
      size: 22,
    );
  }
}

class _PlaceholderTile extends ConsumerWidget {
  const _PlaceholderTile({required this.friendId});
  final String friendId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final friendName =
        ref.watch(userDisplayNameProvider(friendId)).valueOrNull ?? friendId;
    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_empty, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              'waiting for $friendName',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
