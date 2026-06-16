import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/util/today.dart';
import '../../models/daily_words.dart';
import '../../models/player_round.dart';
import '../../widgets/error_state.dart';

final _todayWordsProvider = StreamProvider.autoDispose<DailyWords?>((ref) {
  return ref.watch(firestoreServiceProvider).watchDailyWords(todayKey());
});

/// The signed-in user's round for today. Drives the anti-cheat gate: once the
/// user has submitted a drawing we must NOT show tappable word choices (which
/// would let them draw twice and clobber `hasSubmittedDrawing` via chooseWord).
final _myRoundProvider = StreamProvider.autoDispose<PlayerRound?>((ref) {
  final uid = ref.watch(firebaseAuthProvider).currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).watchPlayerRound(
        date: todayKey(),
        drawerId: uid,
      );
});

class WordSelectionScreen extends ConsumerWidget {
  const WordSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(_todayWordsProvider);
    final myRound = ref.watch(_myRoundProvider);

    void retry() {
      ref.invalidate(_todayWordsProvider);
      ref.invalidate(_myRoundProvider);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's words"),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline),
            onPressed: () => context.push('/friends'),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: words.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: 'Something went wrong',
          onRetry: retry,
        ),
        data: (daily) => myRound.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorState(
            message: 'Something went wrong',
            onRetry: retry,
          ),
          data: (round) {
            // ANTI-CHEAT GATE: one drawing per UTC day. Once the user has
            // submitted today's drawing, never show tappable word cards again
            // (drawing twice would clobber `hasSubmittedDrawing` via chooseWord
            // and strand the home-screen widget on state 1).
            if (round != null && round.hasSubmittedDrawing) {
              return _AlreadyDrawnState(drawingUrl: round.drawingUrl);
            }
            if (daily == null || daily.wordChoices.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    "Today's words aren't ready yet. Check back in a moment.",
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Pick one to draw:'),
                  const SizedBox(height: 16),
                  for (final w in daily.wordChoices) ...[
                    _WordCard(
                      word: w,
                      onTap: () async {
                        final uid = FirebaseAuth.instance.currentUser?.uid;
                        if (uid == null) return;
                        await ref.read(firestoreServiceProvider).chooseWord(
                              date: todayKey(),
                              drawerId: uid,
                              word: w,
                            );
                        if (context.mounted) {
                          context.push('/canvas?word=$w');
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  const Spacer(),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.grid_view),
                    label: const Text("See friends' drawings"),
                    onPressed: () => context.go('/feed'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Shown on the Home tab once the user has already submitted today's drawing.
/// Replaces the tappable word cards so the user cannot draw a second time.
class _AlreadyDrawnState extends StatelessWidget {
  const _AlreadyDrawnState({this.drawingUrl});

  final String? drawingUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.celebration_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              "You've drawn today — come back tomorrow",
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (drawingUrl != null) ...[
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: drawingUrl!,
                  width: 160,
                  height: 160,
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      const SizedBox(width: 160, height: 160),
                  errorWidget: (context, url, error) =>
                      const SizedBox.shrink(),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.grid_view),
              label: const Text("See friends' drawings"),
              onPressed: () => context.go('/feed'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WordCard extends StatefulWidget {
  const _WordCard({required this.word, required this.onTap});
  final String word;
  final VoidCallback onTap;

  @override
  State<_WordCard> createState() => _WordCardState();
}

class _WordCardState extends State<_WordCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceController;
  late final Animation<double> _scaleAnimation;
  bool _tapped = false;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    // Shrink to 0.92 over 150ms then bounce back to 1.0 over 150ms.
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.92)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.92, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 50,
      ),
    ]).animate(_bounceController);
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_tapped) return;
    setState(() => _tapped = true);
    await _bounceController.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Card(
        elevation: _tapped ? 6 : 1,
        color: _tapped
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surface,
        child: InkWell(
          onTap: _handleTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Center(
              child: Text(
                widget.word,
                style: theme.textTheme.headlineSmall,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
