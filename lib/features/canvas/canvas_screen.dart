import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/util/today.dart';

class DrawingStroke {
  DrawingStroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });

  final List<Offset> points;
  final Color color;
  final double strokeWidth;
}

const _palette = <Color>[
  Color(0xFF000000),
  Color(0xFFE53935),
  Color(0xFFFB8C00),
  Color(0xFFFDD835),
  Color(0xFF43A047),
  Color(0xFF1E88E5),
  Color(0xFF8E24AA),
  Color(0xFF6D4C41),
];

class CanvasScreen extends ConsumerStatefulWidget {
  const CanvasScreen({super.key, required this.word});
  final String word;

  @override
  ConsumerState<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends ConsumerState<CanvasScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  final List<DrawingStroke> _strokes = <DrawingStroke>[];

  Color _color = _palette.first;
  double _strokeWidth = 6;
  bool _uploading = false;

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _strokes.add(DrawingStroke(
        points: [details.localPosition],
        color: _color,
        strokeWidth: _strokeWidth,
      ));
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _strokes.last.points.add(details.localPosition);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    // Stroke is complete; nothing further needed.
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
  }

  void _clear() {
    if (_strokes.isEmpty) return;
    setState(_strokes.clear);
  }

  Future<void> _submit() async {
    if (_strokes.isEmpty || _uploading) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _uploading = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('Canvas not ready');
      }

      final image = await boundary.toImage(pixelRatio: 3);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Could not encode drawing');
      }
      final Uint8List bytes = byteData.buffer.asUint8List();

      final date = todayKey();
      final url = await ref.read(storageServiceProvider).uploadDrawing(
            date: date,
            drawerId: uid,
            pngBytes: bytes,
          );
      await ref.read(firestoreServiceProvider).submitDrawing(
            date: date,
            drawerId: uid,
            drawingUrl: url,
          );

      // Reflect the new state on the home-screen widget (best-effort).
      unawaited(ref.read(widgetServiceProvider).refresh(
            firestore: ref.read(firestoreServiceProvider),
            uid: uid,
          ));

      if (mounted) {
        context.go('/feed');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit drawing: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _strokes.isNotEmpty && !_uploading;

    return Scaffold(
      appBar: AppBar(
        title: Text('Draw: ${widget.word}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
            onPressed: _uploading || _strokes.isEmpty ? null : _undo,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: _uploading || _strokes.isEmpty ? null : _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RepaintBoundary(
              key: _boundaryKey,
              child: GestureDetector(
                onPanStart: _uploading ? null : _onPanStart,
                onPanUpdate: _uploading ? null : _onPanUpdate,
                onPanEnd: _uploading ? null : _onPanEnd,
                child: Container(
                  color: Colors.white,
                  width: double.infinity,
                  height: double.infinity,
                  child: CustomPaint(
                    painter: _CanvasPainter(_strokes),
                  ),
                ),
              ),
            ),
          ),
          _Controls(
            palette: _palette,
            selectedColor: _color,
            strokeWidth: _strokeWidth,
            enabled: !_uploading,
            onColorSelected: (c) => setState(() => _color = c),
            onStrokeWidthChanged: (v) => setState(() => _strokeWidth = v),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: _uploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_uploading ? 'Submitting…' : 'Submit drawing'),
                  onPressed: canSubmit ? _submit : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.palette,
    required this.selectedColor,
    required this.strokeWidth,
    required this.enabled,
    required this.onColorSelected,
    required this.onStrokeWidthChanged,
  });

  final List<Color> palette;
  final Color selectedColor;
  final double strokeWidth;
  final bool enabled;
  final ValueChanged<Color> onColorSelected;
  final ValueChanged<double> onStrokeWidthChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final c in palette)
                GestureDetector(
                  onTap: enabled ? () => onColorSelected(c) : null,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c == selectedColor
                            ? Theme.of(context).colorScheme.primary
                            : Colors.black26,
                        width: c == selectedColor ? 3 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.brush, size: 18),
              Expanded(
                child: Slider(
                  min: 1,
                  max: 30,
                  value: strokeWidth,
                  label: strokeWidth.round().toString(),
                  onChanged: enabled ? onStrokeWidthChanged : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter(this.strokes);

  final List<DrawingStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.length == 1) {
        // A single tap renders as a dot.
        canvas.drawPoints(ui.PointMode.points, stroke.points, paint);
        continue;
      }

      final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (var i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) => true;
}
