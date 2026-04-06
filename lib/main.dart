import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mic_stream/mic_stream.dart';

void main() {
  runApp(const SnoreCostApp());
}

class SnoreCostApp extends StatelessWidget {
  const SnoreCostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ХрапОмстр - Вартість храпу',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.dark,
        ),
      ),
      home: const SnoreCostPage(),
    );
  }
}

class SnoreCostPage extends StatefulWidget {
  const SnoreCostPage({super.key});

  @override
  State<SnoreCostPage> createState() => _SnoreCostPageState();
}

class _SnoreCostPageState extends State<SnoreCostPage> {
  bool _isRecording = false;
  double _snoreLevel = 0.0;
  int _snoreCount = 0;
  double _damagePerSnore = 100.0;
  double _totalDamage = 0.0;
  final List<double> _volumeHistory = [];
  Timer? _historyTimer;
  Timer? _streamTimer;
  final MicStream _micStream = MicStream();

  // Пороги для детекції храпу
  final double _snoreThreshold = 0.25;
  final int _snoreDurationSeconds = 3;

  // Логіка детекції
  bool _snoreInProgress = false;
  DateTime? _snoreStartTime;
  double _backgroundLevel = 0.0;
  int _calibrationCount = 0;
  final List<double> _calibrationSamples = [];

  @override
  void initState() {
    super.initState();
    _historyTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_isRecording) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    _streamTimer?.cancel();
    _micStream.dispose();
    super.dispose();
  }

  void _updateAudioLevel(double level) {
    // Нормалізація (припускаємо максимум ~1.0)
    final normalizedLevel = (level.abs() / 32768.0).clamp(0.0, 1.0);

    if (_calibrationCount < 30) {
      // Калібрування фону
      _calibrationSamples.add(normalizedLevel);
      _calibrationCount++;
      if (_calibrationCount == 30) {
        _backgroundLevel = _calibrationSamples.reduce((a, b) => a > b ? a : b);
      }
    }

    // Видаляємо фоновий шум
    final adjustedLevel = (normalizedLevel - _backgroundLevel).clamp(0.0, 1.0);
    _snoreLevel = adjustedLevel;

    final displayLevel = adjustedLevel.clamp(0.0, 1.0);
    _volumeHistory.add(displayLevel);

    // Детекція храпу
    if (!_snoreInProgress && displayLevel > _snoreThreshold) {
      _snoreStartTime = DateTime.now();
      _snoreInProgress = true;
    } else if (_snoreInProgress) {
      final duration = DateTime.now().difference(_snoreStartTime!);
      if (duration.inMilliseconds >= _snoreDurationSeconds * 1000) {
        _completeSnore();
      } else if (displayLevel <= _snoreThreshold * 0.5) {
        _snoreInProgress = false;
      }
    }
  }

  void _completeSnore() {
    _snoreCount++;
    _totalDamage += _damagePerSnore;
    _snoreInProgress = false;
    _snoreStartTime = null;
  }

  Future<void> _startRecording() async {
    try {
      await _micStream.startMicStream((level) {
        if (mounted) {
          _updateAudioLevel(level);
        }
      });
      setState(() {
        _isRecording = true;
        _snoreCount = 0;
        _totalDamage = 0.0;
        _volumeHistory.clear();
        _calibrationCount = 0;
        _calibrationSamples.clear();
        _backgroundLevel = 0.0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Запис аудіо запущено. Калібрування...')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Помилка: $e')),
      );
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _micStream.stop();
      setState(() {
        _isRecording = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Помилка: $e')),
      );
    }
  }

  void _resetStats() {
    setState(() {
      _snoreCount = 0;
      _totalDamage = 0.0;
      _volumeHistory.clear();
      _snoreLevel = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('ХрапОмстр'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetStats,
            tooltip: 'Скинути статистику',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Лічильник храпів
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _snoreCount > 0
                    ? Colors.redAccent.withOpacity(0.2)
                    : Colors.blueGrey.withOpacity(0.2),
                border: Border.all(
                  color: _snoreCount > 0
                      ? Colors.redAccent
                      : Colors.blueGrey,
                  width: 3,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Храпи',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _snoreCount.toString(),
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: _snoreCount > 0
                            ? Colors.redAccent
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Вартість шкоди
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.redAccent.withOpacity(0.3),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Шкода Вікторії',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₴${_totalDamage.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent,
                    ),
                  ),
                  Text(
                    '($_damagePerSnore ₴ за храп)',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.redAccent.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Графік гучності
            Expanded(
              child: Stack(
                children: [
                  if (_volumeHistory.isEmpty && !_isRecording)
                    Center(
                      child: Text(
                        'Увімкни запис аудіо для старту',
                        style: TextStyle(
                          color: Colors.grey.withOpacity(0.5),
                        ),
                      ),
                    ),
                  if (_volumeHistory.isNotEmpty || _isRecording)
                    CustomPaint(
                      painter: VolumeGraphPainter(_volumeHistory),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Кнопка запису
            ElevatedButton(
              onPressed: _isRecording ? _stopRecording : _startRecording,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _isRecording ? 'Зупинити запис' : 'Увімкнути запис',
                style: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 16),

            // Інфо панель
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blueGrey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text(
                        'Рівень храпу',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        '${(_snoreLevel * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _snoreLevel > _snoreThreshold
                              ? Colors.redAccent
                              : Colors.green,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        'Лінія шкоди',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        '₴${_damagePerSnore}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Калібрування
            if (_calibrationCount > 0 && _calibrationCount < 30)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.yellow.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sync, color: Colors.yellow),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Калібрування фону...',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.yellow[700],
                            ),
                          ),
                          SizedBox(
                            width: double.infinity,
                            child: LinearProgressIndicator(
                              value: _calibrationCount / 30,
                              backgroundColor: Colors.yellow[100],
                              color: Colors.yellow[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class VolumeGraphPainter extends CustomPainter {
  final List<double> data;

  VolumeGraphPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final thresholdPaint = Paint()
      ..color = Colors.redAccent.withOpacity(0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final path = Path();
    final stepX = size.width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final y = size.height - (data[i] * size.height);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);

    // Малюємо лінію порогу
    final thresholdY = size.height * (1 - 0.25);
    canvas.drawLine(
      Offset(0, thresholdY),
      Offset(size.width, thresholdY),
      thresholdPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
