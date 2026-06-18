import 'dart:async';
import 'dart:math' as math;

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

const _maxAttempts = 3;

final _drawerRoundProvider =
    StreamProvider.autoDispose.family<PlayerRound?, String>((ref, drawerId) {
  return ref.watch(firestoreServiceProvider).watchPlayerRound(
        date: todayKey(),
        drawerId: drawerId,
      );
});

final _myRoundProvider =
    StreamProvider.autoDispose.family<PlayerRound?, String>((ref, uid) {
  return ref.watch(firestoreServiceProvider).watchPlayerRound(
        date: todayKey(),
        drawerId: uid,
      );
});

final _existingGuessProvider =
    StreamProvider.autoDispose.family<Guess?, String>((ref, drawerId) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).watchGuess(
        date: todayKey(),
        guesserId: uid,
        drawerId: drawerId,
      );
});

/// Server-side hint context for the drawer's secret word (length + first
/// letter). The word is owner-only, so the hint can only come from the
/// `getGuessHint` callable. Fetched once per drawer and cached.
final _hintProvider = FutureProvider.autoDispose
    .family<({int wordLength, String firstLetter}), String>((ref, drawerId) {
  return ref.watch(functionsServiceProvider).getGuessHint(
        date: todayKey(),
        drawerId: drawerId,
      );
});

class GuessingScreen extends ConsumerStatefulWidget {
  const GuessingScreen({super.key, required this.drawerId});
  final String drawerId;

  @override
  ConsumerState<GuessingScreen> createState() => _GuessingScreenState();
}

class _GuessingScreenState extends ConsumerState<GuessingScreen>
    with TickerProviderStateMixin {
  final _controller = TextEditingController();
  final List<String> _attempts = [];
  bool _correct = false;
  int? _solvedOnAttempt;
  String? _revealedWord;
  bool _submitting = false;
  bool _seeded = false;
  bool _hintRevealed = false;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  bool get _finished => _correct || _attempts.length >= _maxAttempts;
  int get _remaining => _maxAttempts - _attempts.length;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  String _normalize(String s) => s.trim().toLowerCase();

  /// Submits the guess to the server, which holds the secret word and decides
  /// correctness. The client never sees the word until the round is finished
  /// (solved or out of attempts), when the server returns `revealedWord`.
  Future<void> _submitGuess() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final raw = _controller.text;
    if (uid == null || _normalize(raw).isEmpty || _finished || _submitting) {
      return;
    }

    setState(() => _submitting = true);
    try {
      final res = await ref.read(functionsServiceProvider).submitGuess(
            date: todayKey(),
            drawerId: widget.drawerId,
            guess: raw.trim(),
          );

      if (!res.correct) {
        // Shake animation on wrong guess, then clear and update state.
        await _shakeController.forward(from: 0);
        _shakeController.reset();
      }
      if (!mounted) return;
      setState(() {
        _controller.clear();
        _attempts
          ..clear()
          ..addAll(res.attempts);
        _correct = res.correct;
        _solvedOnAttempt = res.solvedOnAttempt;
        if (res.finished) _revealedWord = res.revealedWord;
      });

      // Reflect the new solved/total (and possible state 3) on the widget.
      unawaited(ref.read(widgetServiceProvider).refresh(
            firestore: ref.read(firestoreServiceProvider),
            uid: uid,
          ));

      if (res.correct && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade600,
            duration: const Duration(milliseconds: 1500),
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 10),
                Text(
                  'Correct! Well done!',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        if (mounted) context.go('/feed');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save your guess: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Guess')),
      body: uid == null
          ? const Center(child: Text('You need to be signed in to guess.'))
          : _buildGated(context, uid),
    );
  }

  Widget _buildGated(BuildContext context, String uid) {
    final myRound = ref.watch(_myRoundProvider(uid));

    return myRound.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(
        message: 'Something went wrong',
        onRetry: () => ref.invalidate(_myRoundProvider(uid)),
      ),
      data: (mine) {
        // Anti-cheat gate: must have submitted own drawing first.
        if (mine == null || !mine.hasSubmittedDrawing) {
          return const _Gate();
        }
        return _buildBody(context);
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final round = ref.watch(_drawerRoundProvider(widget.drawerId));

    return round.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(
        message: 'Something went wrong',
        onRetry: () => ref.invalidate(_drawerRoundProvider(widget.drawerId)),
      ),
      data: (pr) {
        if (pr == null || !pr.hasSubmittedDrawing || pr.drawingUrl == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                "This friend hasn't submitted a drawing yet.",
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final theme = Theme.of(context);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CachedNetworkImage(
                    imageUrl: pr.drawingUrl!,
                    fit: BoxFit.contain,
                    placeholder: (_, __) =>
                        const Center(child: CircularProgressIndicator()),
                    errorWidget: (_, __, ___) =>
                        const Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildGuessSection(context, theme),
            ],
          ),
        );
      },
    );
  }

  /// Seeds local attempt state from any previously-recorded guess so the
  /// 3-attempt cap (and a finished result) survives leaving and re-entering
  /// the screen. Restores `revealedWord` too, so re-entry after a finished
  /// round still shows the "the word was X" reveal.
  Widget _buildGuessSection(BuildContext context, ThemeData theme) {
    final existing = ref.watch(_existingGuessProvider(widget.drawerId));

    return existing.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(
        message: 'Something went wrong',
        onRetry: () =>
            ref.invalidate(_existingGuessProvider(widget.drawerId)),
      ),
      data: (saved) {
        if (!_seeded) {
          _seeded = true;
          if (saved != null) {
            _attempts
              ..clear()
              ..addAll(saved.attempts);
            _correct = saved.correct;
            _solvedOnAttempt = saved.solvedOnAttempt;
            _revealedWord = saved.revealedWord;
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHint(theme),
            _buildAttempts(theme),
            const SizedBox(height: 16),
            _buildResultOrInput(context),
          ],
        );
      },
    );
  }

  /// A hangman-style hint row showing the word length as underscores, plus a
  /// free one-time "Hint" button that reveals the first letter. Hints come
  /// from the server (the word is owner-only). On error the row is hidden so
  /// guessing is never blocked.
  Widget _buildHint(ThemeData theme) {
    final hint = ref.watch(_hintProvider(widget.drawerId));

    return hint.when(
      // Subtle placeholder while loading; never blocks guessing.
      loading: () => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Loading hint…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      // On error just hide the hint row.
      error: (_, __) => const SizedBox.shrink(),
      data: (h) {
        if (h.wordLength <= 0) return const SizedBox.shrink();

        final slots = <Widget>[];
        for (var i = 0; i < h.wordLength; i++) {
          final revealed = _hintRevealed && i == 0;
          slots.add(
            Text(
              revealed && h.firstLetter.isNotEmpty ? h.firstLetter : '_',
              style: theme.textTheme.titleLarge?.copyWith(
                color: revealed
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        final canReveal = !_hintRevealed && h.firstLetter.isNotEmpty;

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: slots,
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${h.wordLength} letter${h.wordLength == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (canReveal)
                    TextButton.icon(
                      icon: const Icon(Icons.lightbulb_outline, size: 18),
                      label: const Text('Hint'),
                      onPressed: () => setState(() => _hintRevealed = true),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAttempts(ThemeData theme) {
    if (_attempts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _attempts.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  _correct && i == _attempts.length - 1
                      ? Icons.check_circle
                      : Icons.cancel_outlined,
                  color: _correct && i == _attempts.length - 1
                      ? Colors.green
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _attempts[i],
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildResultOrInput(BuildContext context) {
    final theme = Theme.of(context);

    if (_correct) {
      return Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.celebration, size: 40),
              const SizedBox(height: 8),
              Text(
                _solvedOnAttempt == 1
                    ? 'Correct on the first try!'
                    : 'Correct on attempt $_solvedOnAttempt!',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_attempts.length >= _maxAttempts) {
      return Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.sentiment_dissatisfied, size: 40),
              const SizedBox(height: 8),
              Text(
                'Out of attempts!',
                style: theme.textTheme.titleMedium,
              ),
              if (_revealedWord != null) ...[
                const SizedBox(height: 4),
                Text(
                  'The word was "$_revealedWord".',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) {
            // Sin-wave horizontal shake offset
            final offset =
                math.sin(_shakeAnimation.value * math.pi * 5) * 8.0;
            return Transform.translate(
              offset: Offset(offset, 0),
              child: child,
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$_remaining attempt${_remaining == 1 ? '' : 's'} remaining',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: _remaining == 1
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                enabled: !_submitting,
                decoration: const InputDecoration(
                  labelText: 'Your guess',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submitGuess(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send),
          label: const Text('Submit guess'),
          onPressed: _submitting ? null : () => _submitGuess(),
        ),
      ],
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate();

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
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
