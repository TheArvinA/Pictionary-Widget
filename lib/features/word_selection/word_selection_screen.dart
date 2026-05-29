import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/util/today.dart';
import '../../models/daily_words.dart';

final _todayWordsProvider = StreamProvider.autoDispose<DailyWords?>((ref) {
  return ref.watch(firestoreServiceProvider).watchDailyWords(todayKey());
});

class WordSelectionScreen extends ConsumerWidget {
  const WordSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(_todayWordsProvider);

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
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (daily) {
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
                  onPressed: () => context.push('/feed'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WordCard extends StatelessWidget {
  const _WordCard({required this.word, required this.onTap});
  final String word;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Center(
            child: Text(
              word,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        ),
      ),
    );
  }
}
