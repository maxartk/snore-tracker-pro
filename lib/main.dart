import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

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
  final RecordAudio _recordAudio = RecordAudio();
  bool _isRecording = false;
  double _snoreLevel = 0.0;
  int _snoreCount = 0;
  double _damagePerSnore = 100.0; // 100 гривень за храп
  double _totalDamage = 0.0;
  final List<double> _volumeHistory = [];
  Timer? _historyTimer;
  Timer? _snoreTimer;

  // Пороги для детекції храпу
  final double _snoreThreshold = 0.25; // 25% від максимального
  final int _snoreDurationSeconds = 3; // тривалість храпу в секундах

  // Логіка детекції
  bool _snoreInProgress = false;
  DateTime? _snoreStartTime;
  final List<double> _calibrationSamples = [];
  double _backgroundLevel = 0.0;
  int _calibrationCount = 0;

  @override
  void initState() {
    super.initState();
    _historyTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_isRecording) {
        _updateAudioLevel();
      }
      setState(() {});
    });

    // Оновлення графіка кожні 0.5 секунди
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_volumeHistory.length > 60) {
        _volumeHistory.removeRange(0, _volumeHistory.length - 60);
      }
    });
  }

  void _updateAudioLevel() async {
    try {
      final level = await _recordAudio.getCurrentLevel();
      final amplitude = level.amplitude ?? 0.0;

      // Нормалізація (предполагаем максимум 1.0)
      final normalizedLevel = amplitude.clamp(0.0, 1.0);

      if (_calibrationCount < 30) {
        // Калібрування фону перші 3 секунди (30 * 100мс)
        _calibrationSamples.add(normalizedLevel);
        _calibrationCount++;
        if (_calibrationCount == 30) {
          _backgroundLevel = _calibrationSamples.reduce((a, b) => a > b ? a : b);
        }
      }

      // Видаляємо фоновий шум
      final adjustedLevel = max(0.0, normalizedLevel - _backgroundLevel);
      _snoreLevel = adjustedLevel;

      // Обмежуємо рівень для відображення
      final displayLevel = adjustedLevel.clamp(0.0, 1.0);
      _volumeHistory.add(displayLevel);

      // Детекція храпу
      if (!_snoreInProgress && displayLevel > _snoreThreshold) {
        _snoreStartTime = DateTime.now();
        _snoreInProgress = true;
      } else if (_snoreInProgress) {
        final duration = DateTime.now().difference(_snoreStartTime!);
        if (duration.inMilliseconds >= _snoreDurationSeconds * 1000) {
          // Храп підтверджений
          _completeSnore();
        } else if (displayLevel <= _snoreThreshold * 0.5) {
          // Храп зупинився рано
          _snoreInProgress = false;
        }
      }
    } catch (e) {
      debugPrint('Error getting audio level: $e');
    }
  }

  void _completeSnore() {
    _snoreCount++;
    _totalDamage += _damagePerSnore;
    _snoreInProgress = false;
    _snoreStartTime = null;
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    _snoreTimer?.cancel();
    _recordAudio.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!await _recordAudio.hasPermission()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Потрібен доступ до мікрофону')),
      );
      return;
    }
    await _recordAudio.start();
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
      SnackBar(content: Text('Запис аудіо запущено. Калібрування...')),
    );
  }

  Future<void> _stopRecording() async {
    await _recordAudio.stop();
    setState(() {
      _isRecording = false;
    });
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
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

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
