import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/util/today.dart';
import '../../models/guess.dart';
import '../../models/player_round.dart';
import '../../widgets/error_state.dart';

/// This user's personal 3-word subset for today, drawn from the shared daily
/// pool and persisted to their private round doc (see
/// [FirestoreService.ensureMyWords]). Each user gets a different subset so
/// friends rarely draw the same word. Returns `const []` until the pool exists.
final _todayWordsProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final uid = ref.watch(firebaseAuthProvider).currentUser?.uid;
  if (uid == null) return const [];
  return ref.watch(firestoreServiceProvider).ensureMyWords(
        date: todayKey(),
        drawerId: uid,
      );
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

/// Every guess made against the signed-in drawer's drawing today, so the
/// already-drawn state can show who's guessed it and how they did.
final _guessesForMeProvider = StreamProvider.autoDispose<List<Guess>>((ref) {
  final uid = ref.watch(firebaseAuthProvider).currentUser?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(firestoreServiceProvider).watchGuessesForDrawer(
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
        data: (words) => myRound.when(
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
            if (words.isEmpty) {
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
                  for (final w in words) ...[
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
/// Replaces the tappable word cards so the user cannot draw a second time, and
/// shows who's guessed the drawing today and how they did.
class _AlreadyDrawnState extends StatelessWidget {
  const _AlreadyDrawnState({this.drawingUrl});

  final String? drawingUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrollable so the guessers list never overflows on small screens.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
            Center(
              child: ClipRRect(
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
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.grid_view),
            label: const Text("See friends' drawings"),
            onPressed: () => context.go('/feed'),
          ),
          const SizedBox(height: 32),
          const _GuessersSection(),
        ],
      ),
    );
  }
}

/// Lists everyone who has guessed the signed-in user's drawing today and how
/// they did. Resolves guesser display names via [friendNamesProvider], exactly
/// like the friends' feed does.
class _GuessersSection extends ConsumerWidget {
  const _GuessersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final guesses = ref.watch(_guessesForMeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Who's guessed your drawing",
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        guesses.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => ErrorState(
            message: 'Something went wrong',
            onRetry: () => ref.invalidate(_guessesForMeProvider),
          ),
          data: (list) {
            if (list.isEmpty) {
              return Text(
                "No one's guessed your drawing yet.",
                style: theme.textTheme.bodyMedium,
              );
            }
            final guesserIds = <String>{
              for (final g in list) g.guesserId,
            }.toList();
            final names = ref.watch(friendNamesProvider(guesserIds));
            final nameMap = names.valueOrNull ?? const <String, String>{};
            return Column(
              children: [
                for (final g in list)
                  _GuesserRow(
                    name: nameMap[g.guesserId] ?? g.guesserId,
                    guess: g,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// A single guesser row: their name plus how they did against this drawing.
class _GuesserRow extends StatelessWidget {
  const _GuesserRow({required this.name, required this.guess});

  final String name;
  final Guess guess;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget status;
    if (guess.correct) {
      status = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 18),
          const SizedBox(width: 4),
          Text(
            'guessed in ${guess.solvedOnAttempt ?? guess.attempts.length}',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: Colors.green),
          ),
        ],
      );
    } else if (guess.completedAt != null) {
      status = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cancel, color: Colors.red, size: 18),
          const SizedBox(width: 4),
          Text(
            "didn't get it",
            style:
                theme.textTheme.bodyMedium?.copyWith(color: Colors.red),
          ),
        ],
      );
    } else {
      status = Text(
        'guessing…',
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: scheme.onSurfaceVariant),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge,
            ),
          ),
          status,
        ],
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
