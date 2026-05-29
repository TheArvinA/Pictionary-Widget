import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/util/today.dart';
import '../../models/app_user.dart';
import '../../models/player_round.dart';

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

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myRound = ref.watch(_myRoundProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("Friends' drawings")),
      body: myRound.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
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
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (appUser) {
        final friendIds = appUser?.friendIds ?? const <String>[];
        if (friendIds.isEmpty) {
          return const _EmptyState(
            message:
                'Add some friends to see their daily drawings here.',
          );
        }

        final drawings = ref.watch(_friendDrawingsProvider(friendIds));
        return drawings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
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

class _DrawingTile extends StatelessWidget {
  const _DrawingTile({required this.friendId, required this.drawingUrl});
  final String friendId;
  final String drawingUrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/guess/$friendId'),
        child: CachedNetworkImage(
          imageUrl: drawingUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) =>
              const Center(child: CircularProgressIndicator()),
          errorWidget: (context, url, error) =>
              const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      ),
    );
  }
}

class _PlaceholderTile extends StatelessWidget {
  const _PlaceholderTile({required this.friendId});
  final String friendId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
              'waiting for $friendId',
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
