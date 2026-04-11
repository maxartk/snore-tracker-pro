import 'dart:math';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
          surface: const Color(0xFF161B22),
          primary: const Color(0xFF6366F1),
          secondary: const Color(0xFF10B981),
          error: const Color(0xFFEF4444),
        ),
        fontFamily: 'SF Pro Display',
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

class _SnoreCostPageState extends State<SnoreCostPage>
    with TickerProviderStateMixin {
  bool _isRecording = false;
  double _snoreLevel = 0.0;
  int _snoreCount = 0;
  double _damagePerSnore = 100.0;
  double _totalDamage = 0.0;
  final List<double> _volumeHistory = [];
  Timer? _historyTimer;
  StreamSubscription<dynamic>? _micSubscription;
  AudioRecorder? _recorder;

  late AnimationController _pulseController;
  late AnimationController _bounceController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _bounceAnimation;

  // Налаштування (можна змінювати)
  double _snoreThreshold = 0.04;
  int _snoreDurationSeconds = 1;
  double _audioGain = 10.0; // Підсилення сигналу (1.0 = без підсилення, 3.0 = 3x)

  bool _snoreInProgress = false;
  DateTime? _snoreStartTime;
  double _backgroundLevel = 0.0;
  int _calibrationCount = 0;
  final List<double> _calibrationSamples = [];
  bool _inCooldown = false;
  final List<String> _debugLog = [];

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _bounceAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
    );

    _historyTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_isRecording) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    _micSubscription?.cancel();
    _recorder?.dispose();
    _pulseController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  void _updateAudioLevel(Uint8List bytes) {
    if (bytes.length < 2) return;

    double sum = 0;
    int count = bytes.length ~/ 2;
    
    for (int i = 0; i < count * 2; i += 2) {
      // Little-endian: перший байт = молодший, другий = старший
      final raw = bytes[i] | (bytes[i + 1] << 8);
      // Конвертуємо unsigned в signed int16
      final signed = raw > 32767 ? raw - 65536 : raw;
      sum += signed * signed.toDouble();
    }
    
    if (count == 0) return;

    final rms = sqrt(sum / count);
    // Застосовуємо підсилення для збільшення чутливості на відстані
    final amplifiedRms = rms * _audioGain;
    final normalizedLevel = (amplifiedRms / 32768.0).clamp(0.0, 1.0);
    
    // Debug log
    if (_debugLog.length > 50) _debugLog.removeAt(0);
    if (_calibrationCount >= 30) {
      final adjustedLevel = (normalizedLevel - _backgroundLevel).clamp(0.0, 1.0);
      _debugLog.add('${DateTime.now().toString().substring(11,19)} | raw:${normalizedLevel.toStringAsFixed(3)} bg:${_backgroundLevel.toStringAsFixed(3)} adj:${adjustedLevel.toStringAsFixed(3)} thr:${_snoreThreshold.toStringAsFixed(2)}');
    }
    
    if (_calibrationCount < 30) {
      _calibrationSamples.add(normalizedLevel);
      _calibrationCount++;
      if (_calibrationCount == 30) {
        // Сортуємо і беремо нижні 10 (найтихіші) — це фоновий шум
        _calibrationSamples.sort();
        _backgroundLevel = _calibrationSamples.sublist(0, 10).reduce((a, b) => a + b) / 10;
      }
      return;
    }

    if (normalizedLevel < 0.02) {
      _snoreLevel = 0;
      return;
    }
    final adjustedLevel = (normalizedLevel - _backgroundLevel).clamp(0.0, 1.0);
    _snoreLevel = adjustedLevel;

    final displayLevel = adjustedLevel.clamp(0.0, 1.0);
    _volumeHistory.add(displayLevel);
    if (_volumeHistory.length > 200) _volumeHistory.removeAt(0);

    if (!_snoreInProgress && !_inCooldown && displayLevel > _snoreThreshold) {
      _snoreStartTime = DateTime.now();
      _snoreInProgress = true;
    } else if (_snoreInProgress) {
      final duration = DateTime.now().difference(_snoreStartTime!);
      if (duration.inMilliseconds >= _snoreDurationSeconds * 1000) {
        _completeSnore();
      } else if (displayLevel <= _snoreThreshold * 0.3) {
        _snoreInProgress = false;
      }
    }
  }

  void _completeSnore() {
    setState(() {
      _snoreCount++;
      _totalDamage += _damagePerSnore;
    });
    _snoreInProgress = false;
    _snoreStartTime = null;
    _inCooldown = true;
    _bounceController.forward().then((_) => _bounceController.reverse());
    
    // Cooldown 1.5 сек перед наступною детекцією
    Future.delayed(const Duration(milliseconds: 1500), () {
      _inCooldown = false;
    });
  }

  Future<void> _startRecording() async {
    try {
      final recorder = AudioRecorder();
      if (!await recorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Дозвіл на мікрофон не надано'),
              backgroundColor: Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      _recorder = recorder;
      final stream = await recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));
      _micSubscription = stream.listen(_updateAudioLevel, cancelOnError: true);

      setState(() {
        _isRecording = true;
        _snoreCount = 0;
        _totalDamage = 0.0;
        _volumeHistory.clear();
        _calibrationCount = 0;
        _calibrationSamples.clear();
        _backgroundLevel = 0.0;
      });

      _pulseController.repeat(reverse: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Запис аудіо запущено. Калібрування 3 сек...'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Помилка: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _micSubscription?.cancel();
      _micSubscription = null;
      await _recorder?.stop();
      _recorder = null;
      _pulseController.stop();
      _pulseController.value = 1.0;
      setState(() {
        _isRecording = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Помилка: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _resetStats() {
    setState(() {
      _snoreCount = 0;
      _totalDamage = 0.0;
      _volumeHistory.clear();
      _snoreLevel = 0.0;
      _debugLog.clear();
    });
  }

  void _copyDebugLogs() {
    final logs = _debugLog.isEmpty ? 'No logs yet' : _debugLog.join('\n');
    Clipboard.setData(ClipboardData(text: logs));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_debugLog.isEmpty ? 'Немає логів' : 'Скопійовано ${_debugLog.length} записів'),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C2128),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Налаштування',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Чутливість
              _buildStepperSetting(
                label: 'Чутливість',
                subtitle: 'Поріг детекції (менше = чутливіше)',
                value: '${(_snoreThreshold * 100).toInt()}%',
                icon: Icons.tune,
                iconColor: const Color(0xFF6366F1),
                onDecrement: () {
                  if (_snoreThreshold > 0.01) {
                    setState(() => _snoreThreshold = double.parse((_snoreThreshold - 0.01).toStringAsFixed(2)));
                    setSheetState(() {});
                  }
                },
                onIncrement: () {
                  if (_snoreThreshold < 0.50) {
                    setState(() => _snoreThreshold = double.parse((_snoreThreshold + 0.01).toStringAsFixed(2)));
                    setSheetState(() {});
                  }
                },
                canDecrement: _snoreThreshold > 0.01,
                canIncrement: _snoreThreshold < 0.50,
              ),
              const SizedBox(height: 20),

              // Ціна за храп
              _buildStepperSetting(
                label: 'Ціна за храп',
                subtitle: 'Скільки коштує 1 храп',
                value: '${_damagePerSnore.toInt()} ₴',
                icon: Icons.attach_money,
                iconColor: const Color(0xFFEF4444),
                onDecrement: () {
                  if (_damagePerSnore > 10) {
                    setState(() => _damagePerSnore -= 10);
                    setSheetState(() {});
                  }
                },
                onIncrement: () {
                  if (_damagePerSnore < 500) {
                    setState(() => _damagePerSnore += 10);
                    setSheetState(() {});
                  }
                },
                canDecrement: _damagePerSnore > 10,
                canIncrement: _damagePerSnore < 500,
              ),
              const SizedBox(height: 20),

              // Тривалість
              _buildStepperSetting(
                label: 'Тривалість храпу',
                subtitle: 'Мін. час звуку (сек)',
                value: '$_snoreDurationSeconds сек',
                icon: Icons.timer_outlined,
                iconColor: const Color(0xFF10B981),
                onDecrement: () {
                  if (_snoreDurationSeconds > 1) {
                    setState(() => _snoreDurationSeconds--);
                    setSheetState(() {});
                  }
                },
                onIncrement: () {
                  if (_snoreDurationSeconds < 5) {
                    setState(() => _snoreDurationSeconds++);
                    setSheetState(() {});
                  }
                },
                canDecrement: _snoreDurationSeconds > 1,
                canIncrement: _snoreDurationSeconds < 5,
              ),
              const SizedBox(height: 20),

              // Підсилення (Gain)
              _buildStepperSetting(
                label: 'Підсилення мікрофона',
                subtitle: 'Збільшує чутливість на відстані',
                value: '${_audioGain.toStringAsFixed(1)}x',
                icon: Icons.volume_up,
                iconColor: const Color(0xFF8B5CF6),
                onDecrement: () {
                  if (_audioGain > 1.0) {
                    setState(() => _audioGain = double.parse((_audioGain - 0.5).toStringAsFixed(1)));
                    setSheetState(() {});
                  }
                },
                onIncrement: () {
                  if (_audioGain < 10.0) {
                    setState(() => _audioGain = double.parse((_audioGain + 0.5).toStringAsFixed(1)));
                    setSheetState(() {});
                  }
                },
                canDecrement: _audioGain > 1.0,
                canIncrement: _audioGain < 10.0,
              ),
              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _snoreThreshold = 0.04;
                      _damagePerSnore = 100;
                      _snoreDurationSeconds = 1;
                      _audioGain = 3.0;
                    });
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.restore, color: Color(0xFF6366F1)),
                  label: const Text(
                    'Скинути налаштування',
                    style: TextStyle(color: Color(0xFF6366F1)),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepperSetting({
    required String label,
    required String subtitle,
    required String value,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
    required bool canDecrement,
    required bool canIncrement,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _buildStepperButton(
                icon: Icons.remove,
                onTap: canDecrement ? onDecrement : null,
                enabled: canDecrement,
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: iconColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _buildStepperButton(
                icon: Icons.add,
                onTap: canIncrement ? onIncrement : null,
                enabled: canIncrement,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepperButton({
    required IconData icon,
    required VoidCallback? onTap,
    required bool enabled,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFF6366F1)
              : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: enabled ? Colors.white : Colors.white.withOpacity(0.3),
          size: 20,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0D1117),
              Color(0xFF161B22),
              Color(0xFF1C2128),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildSnoreCounter(),
                const SizedBox(height: 24),
                _buildDamageCard(),
                const SizedBox(height: 24),
                Expanded(child: _buildGraph()),
                _buildDebugPanel(),
                _buildControls(),
                const SizedBox(height: 16),
                _buildInfoPanel(),
                const SizedBox(height: 16),
                _buildCalibrationBar(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ХрапОмстр',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _isRecording
                    ? (_inCooldown ? '⏳ Cooldown...' : 'Активний запис')
                    : 'Готовий до роботи',
                style: TextStyle(
                  fontSize: 14,
                  color: _isRecording
                      ? (_inCooldown ? const Color(0xFFF59E0B) : const Color(0xFF10B981))
                      : Colors.white.withOpacity(0.5),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Row(
            children: [
              _buildGlassIconBtn(
                icon: Icons.bug_report_outlined,
                onTap: _copyDebugLogs,
                color: const Color(0xFFF59E0B),
              ),
              const SizedBox(width: 8),
              _buildGlassIconBtn(
                icon: Icons.settings_outlined,
                onTap: _showSettings,
              ),
              const SizedBox(width: 8),
              _buildGlassIconBtn(
                icon: Icons.refresh_rounded,
                onTap: _resetStats,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlassIconBtn({required IconData icon, required VoidCallback onTap, Color? color}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.08),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: color ?? Colors.white.withOpacity(0.8)),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildSnoreCounter() {
    return ScaleTransition(
      scale: _bounceAnimation,
      child: Container(
        width: 180,
        height: 180,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              _snoreCount > 0
                  ? const Color(0xFFEF4444).withOpacity(0.3)
                  : const Color(0xFF6366F1).withOpacity(0.2),
              _snoreCount > 0
                  ? const Color(0xFFEF4444).withOpacity(0.05)
                  : const Color(0xFF6366F1).withOpacity(0.05),
            ],
          ),
          border: Border.all(
            color: _snoreCount > 0
                ? const Color(0xFFEF4444).withOpacity(0.6)
                : const Color(0xFF6366F1).withOpacity(0.4),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: (_snoreCount > 0
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF6366F1))
                  .withOpacity(0.3),
              blurRadius: 24,
              spreadRadius: _snoreCount > 0 ? 2 : 0,
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'ХРАПИ',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.6),
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _snoreCount.toString(),
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.bold,
                  color: _snoreCount > 0
                      ? const Color(0xFFEF4444)
                      : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDamageCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFEF4444).withOpacity(0.2),
            const Color(0xFFEF4444).withOpacity(0.08),
          ],
        ),
        border: Border.all(
          color: const Color(0xFFEF4444).withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.favorite_rounded,
                color: const Color(0xFFEF4444).withOpacity(0.8),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'ШКОДА ВІКТОРІЇ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFEF4444).withOpacity(0.9),
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '₴${_totalDamage.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.bold,
              color: Color(0xFFEF4444),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white.withOpacity(0.08),
            ),
            child: Text(
              '${_damagePerSnore.toInt()} ₴ за храп',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildDebugPanel() {
    if (!_isRecording) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.yellow.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '🔍 DEBUG',
                style: TextStyle(
                  color: Colors.yellow,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'logs: ${_debugLog.length}',
                style: TextStyle(
                  color: Colors.yellow.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'raw: ${(_snoreLevel * 100).toInt()}% | bg: ${(_backgroundLevel * 100).toInt()}% | thr: ${(_snoreThreshold * 100).toInt()}%',
            style: const TextStyle(color: Colors.yellow, fontSize: 11, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 4),
          Text(
            'cooldown: $_inCooldown | progress: $_snoreInProgress | dur: ${_snoreDurationSeconds}s',
            style: const TextStyle(color: Colors.yellow, fontSize: 11, fontFamily: 'monospace'),
          ),
          if (_debugLog.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              height: 60,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: ListView.builder(
                itemCount: _debugLog.length > 5 ? 5 : _debugLog.length,
                itemBuilder: (ctx, i) => Text(
                  _debugLog[_debugLog.length - 5 + i],
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 9, fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGraph() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withOpacity(0.03),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Рівень аудіо',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.5),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: _snoreLevel > _snoreThreshold
                      ? const Color(0xFFEF4444).withOpacity(0.2)
                      : const Color(0xFF10B981).withOpacity(0.2),
                ),
                child: Text(
                  '${(_snoreLevel * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _snoreLevel > _snoreThreshold
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _volumeHistory.isEmpty && !_isRecording
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.mic_none_rounded,
                          size: 48,
                          color: Colors.white.withOpacity(0.15),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Увімкни запис аудіо для старту',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                      ],
                    ),
                  )
                : CustomPaint(
                    painter: VolumeGraphPainter(
                      _volumeHistory,
                      _snoreThreshold,
                      _snoreLevel > _snoreThreshold,
                    ),
                    size: Size.infinite,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _isRecording ? _pulseAnimation.value : 1.0,
          child: child,
        );
      },
      child: GestureDetector(
        onTap: _isRecording ? _stopRecording : _startRecording,
        child: Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: _isRecording
                  ? [
                      const Color(0xFFEF4444),
                      const Color(0xFFDC2626),
                    ]
                  : [
                      const Color(0xFF10B981),
                      const Color(0xFF059669),
                    ],
            ),
            boxShadow: [
              BoxShadow(
                color: (_isRecording
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF10B981))
                    .withOpacity(0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                _isRecording ? 'ЗУПИНИТИ ЗАПИС' : 'УВІМКНУТИ ЗАПИС',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildInfoItem(
            'Поріг детекції',
            '${(_snoreThreshold * 100).toInt()}%',
            Icons.signal_cellular_alt,
            const Color(0xFF6366F1),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.white.withOpacity(0.1),
          ),
          _buildInfoItem(
            'Лінія шкоди',
            '₴${_damagePerSnore.toInt()}',
            Icons.attach_money,
            const Color(0xFFEF4444),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.white.withOpacity(0.1),
          ),
          _buildInfoItem(
            'Тривалість',
            '${_snoreDurationSeconds}с',
            Icons.timer_outlined,
            const Color(0xFF10B981),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color.withOpacity(0.8)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildCalibrationBar() {
    if (_calibrationCount == 0 || _calibrationCount >= 30) {
      return const SizedBox(height: 48);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFFF59E0B).withOpacity(0.1),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.sync, color: Color(0xFFF59E0B), size: 18),
              const SizedBox(width: 8),
              Text(
                'Калібрування фону...',
                style: TextStyle(
                  fontSize: 13,
                  color: const Color(0xFFF59E0B).withOpacity(0.9),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '${((_calibrationCount / 30) * 100).toInt()}%',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFFF59E0B),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _calibrationCount / 30,
              backgroundColor: const Color(0xFFF59E0B).withOpacity(0.2),
              color: const Color(0xFFF59E0B),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

class VolumeGraphPainter extends CustomPainter {
  final List<double> data;
  final double threshold;
  final bool isSnoring;

  VolumeGraphPainter(this.data, this.threshold, this.isSnoring);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final stepX = size.width / (data.length.clamp(1, 200));

    final fillPath = Path();
    fillPath.moveTo(0, size.height);

    for (int i = 0; i < data.length.clamp(0, 200); i++) {
      final x = i * stepX;
      final y = size.height - (data[i] * size.height * 0.9);
      if (i == 0) {
        fillPath.lineTo(x, y);
      } else {
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(data.length.clamp(0, 200) * stepX, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          (isSnoring ? const Color(0xFFEF4444) : const Color(0xFF10B981))
              .withOpacity(0.3),
          (isSnoring ? const Color(0xFFEF4444) : const Color(0xFF10B981))
              .withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);

    final linePath = Path();
    for (int i = 0; i < data.length.clamp(0, 200); i++) {
      final x = i * stepX;
      final y = size.height - (data[i] * size.height * 0.9);

      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = isSnoring ? const Color(0xFFEF4444) : const Color(0xFF10B981)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(linePath, linePaint);

    final thresholdY = size.height * (1 - threshold * 0.9);
    final thresholdPaint = Paint()
      ..color = const Color(0xFFEF4444).withOpacity(0.4)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(0, thresholdY),
      Offset(size.width, thresholdY),
      thresholdPaint,
    );

    final glowPaint = Paint()
      ..color = const Color(0xFFEF4444).withOpacity(0.15)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawLine(
      Offset(0, thresholdY),
      Offset(size.width, thresholdY),
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant VolumeGraphPainter oldDelegate) {
    return true;
  }
}
