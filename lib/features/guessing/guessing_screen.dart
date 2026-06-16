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
  bool _submitting = false;
  bool _seeded = false;

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

  Future<void> _submitGuess(String chosenWord) async {
    final raw = _controller.text;
    if (_normalize(raw).isEmpty || _finished || _submitting) return;

    final isCorrect = _normalize(raw) == _normalize(chosenWord);

    if (!isCorrect) {
      // Shake animation on wrong guess, then clear and update state.
      await _shakeController.forward(from: 0);
      _shakeController.reset();
      setState(() {
        _attempts.add(raw.trim());
        _controller.clear();
      });
    } else {
      setState(() {
        _attempts.add(raw.trim());
        _controller.clear();
        _correct = true;
        _solvedOnAttempt = _attempts.length;
      });
    }

    if (_finished) {
      await _recordResult(isCorrect: isCorrect);
    }
  }

  Future<void> _recordResult({required bool isCorrect}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _submitting = true);
    final guess = Guess(
      guesserId: uid,
      drawerId: widget.drawerId,
      attempts: List<String>.from(_attempts),
      correct: _correct,
      solvedOnAttempt: _solvedOnAttempt,
    );
    try {
      await ref
          .read(firestoreServiceProvider)
          .recordGuess(date: todayKey(), guess: guess);

      // Reflect the new solved/total (and possible state 3) on the widget.
      unawaited(ref.read(widgetServiceProvider).refresh(
            firestore: ref.read(firestoreServiceProvider),
            uid: uid,
          ));

      if (isCorrect && mounted) {
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

        final chosenWord = pr.chosenWord;
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
              if (chosenWord == null)
                const Text(
                  "This drawing isn't ready to guess yet.",
                  textAlign: TextAlign.center,
                )
              else
                _buildGuessSection(context, theme, chosenWord),
            ],
          ),
        );
      },
    );
  }

  /// Seeds local attempt state from any previously-recorded guess so the
  /// 3-attempt cap (and a finished result) survives leaving and re-entering
  /// the screen. recordGuess() overwrites the doc, so without this a user
  /// could re-enter and clobber a completed guess with a fresh set of tries.
  Widget _buildGuessSection(
    BuildContext context,
    ThemeData theme,
    String chosenWord,
  ) {
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
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAttempts(theme),
            const SizedBox(height: 16),
            _buildResultOrInput(context, chosenWord),
          ],
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

  Widget _buildResultOrInput(BuildContext context, String chosenWord) {
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
              const SizedBox(height: 4),
              Text(
                'The word was "$chosenWord".',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
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
                onSubmitted: (_) => _submitGuess(chosenWord),
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
          onPressed: _submitting ? null : () => _submitGuess(chosenWord),
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
