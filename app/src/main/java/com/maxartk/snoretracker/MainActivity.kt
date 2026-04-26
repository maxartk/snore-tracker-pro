package com.maxartk.snoretracker

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.*
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.delay

class MainActivity : ComponentActivity() {
    private lateinit var audioProcessor: AudioProcessor

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        audioProcessor = AudioProcessor(this)

        setContent {
            MaterialTheme(
                colorScheme = darkColorScheme(
                    primary = Color(0xFF6366F1),
                    secondary = Color(0xFF10B981),
                    background = Color(0xFF0D1117),
                    surface = Color(0xFF161B22),
                    error = Color(0xFFEF4444),
                )
            ) {
                SnoreApp(audioProcessor)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        audioProcessor.destroy()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SnoreApp(ap: AudioProcessor) {
    val state by ap.state.collectAsState()
    val settings = ap.settings
    val history = remember { mutableListOf<Float>() }
    var showDebug by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }

    // Permission launcher
    val permLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) ap.start()
        else ap._state.value = ap._state.value.copy(error = "Дозвіл на мікрофон відхилено")
    }

    // Collect history on main thread
    val isLoud = state.level > settings.threshold

    LaunchedEffect(state.level) {
        if (state.isRecording && !state.isCalibrating && state.level > 0) {
            history.add(state.level)
            if (history.size > 250) history.removeAt(0)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(
                colors = listOf(Color(0xFF0D1117), Color(0xFF161B22), Color(0xFF1C2128))
            ))
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp)
                .padding(top = 48.dp, bottom = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text("ХрапОмстр", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = Color.White)
                    val statusText = when {
                        state.error != null -> "Помилка мікрофона"
                        !state.isRecording -> "Готовий до роботи"
                        state.isCalibrating -> "Калібрування ${(state.calibrationProgress * 100).toInt()}%..."
                        state.isCooldown -> "⏳ Cooldown..."
                        else -> "Активний запис"
                    }
                    val statusColor = when {
                        state.error != null -> Color(0xFFEF4444)
                        !state.isRecording -> Color.White.copy(alpha = 0.5f)
                        state.isCalibrating -> Color(0xFFF59E0B)
                        state.isCooldown -> Color(0xFFF59E0B)
                        else -> Color(0xFF10B981)
                    }
                    Text(statusText, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = statusColor)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    IconButton(onClick = { showDebug = !showDebug }, modifier = Modifier
                        .size(44.dp)
                        .background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(14.dp))
                        .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(14.dp))
                    ) {
                        Icon(Icons.Default.BugReport, "Debug", tint = Color(0xFFF59E0B), modifier = Modifier.size(20.dp))
                    }
                    IconButton(onClick = { showSettings = true }, modifier = Modifier
                        .size(44.dp)
                        .background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(14.dp))
                        .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(14.dp))
                    ) {
                        Icon(Icons.Default.Settings, "Settings", tint = Color.White.copy(alpha = 0.8f), modifier = Modifier.size(20.dp))
                    }
                    IconButton(onClick = { ap.reset() }, modifier = Modifier
                        .size(44.dp)
                        .background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(14.dp))
                        .border(1.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(14.dp))
                    ) {
                        Icon(Icons.Default.Refresh, "Reset", tint = Color(0xFF6366F1), modifier = Modifier.size(20.dp))
                    }
                }
            }

            Spacer(Modifier.height(24.dp))

            // Snore Counter Circle
            val pulseAnim = remember { Animatable(1f) }
            LaunchedEffect(state.snoreCount) {
                if (state.snoreCount > 0) {
                    pulseAnim.snapTo(1.2f)
                    pulseAnim.animateTo(1f, animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy))
                }
            }
            val circleColor = if (state.snoreCount > 0) Color(0xFFEF4444) else Color(0xFF6366F1)
            Box(
                modifier = Modifier
                    .size(180.dp)
                    .graphicsLayer { scaleX = pulseAnim.value; scaleY = pulseAnim.value }
                    .clip(CircleShape)
                    .background(Brush.radialGradient(
                        colors = listOf(circleColor.copy(alpha = 0.3f), circleColor.copy(alpha = 0.05f))
                    ))
                    .border(2.dp, circleColor.copy(alpha = 0.6f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("ХРАПИ", fontSize = 11.sp, fontWeight = FontWeight.W600, color = Color.White.copy(alpha = 0.6f), letterSpacing = 2.sp)
                    Spacer(Modifier.height(8.dp))
                    Text(state.snoreCount.toString(), fontSize = 56.sp, fontWeight = FontWeight.Bold,
                        color = if (state.snoreCount > 0) Color(0xFFEF4444) else Color.White)
                }
            }

            Spacer(Modifier.height(24.dp))

            // Damage Card
            Card(
                modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = Color(0xFFEF4444).copy(alpha = 0.12f)),
                shape = RoundedCornerShape(24.dp),
                border = BorderStroke(1.dp, Brush.horizontalGradient(listOf(Color(0xFFEF4444).copy(alpha=0.3f), Color(0xFFEF4444).copy(alpha=0.1f))))
            ) {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
                        Icon(Icons.Default.Favorite, "heart", tint = Color(0xFFEF4444).copy(alpha = 0.8f), modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text("ШКОДА ВІКТОРІЇ", fontSize = 12.sp, fontWeight = FontWeight.W600, color = Color(0xFFEF4444).copy(alpha = 0.9f), letterSpacing = 1.5.sp)
                    }
                    Spacer(Modifier.height(12.dp))
                    Text("₴${state.totalDamage}", fontSize = 52.sp, fontWeight = FontWeight.Bold, color = Color(0xFFEF4444))
                    Spacer(Modifier.height(8.dp))
                    Text("${settings.pricePerSnore} ₴ за храп", fontSize = 13.sp, color = Color.White.copy(alpha = 0.6f),
                        modifier = Modifier.background(Color.White.copy(alpha=0.08f), RoundedCornerShape(20.dp)).padding(horizontal = 16.dp, vertical = 6.dp))
                }
            }

            Spacer(Modifier.height(24.dp))

            // Audio Graph
            Card(
                modifier = Modifier.weight(1f).fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.03f)),
                shape = RoundedCornerShape(20.dp),
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(modifier = Modifier.size(8.dp).clip(CircleShape).background(Color(0xFF10B981)))
                            Spacer(Modifier.width(8.dp))
                            Text("Рівень аудіо", fontSize = 12.sp, color = Color.White.copy(alpha = 0.5f), fontWeight = FontWeight.W500)
                        }
                        val pct = (state.level * 100).toInt()
                        Surface(
                            color = if (isLoud) Color(0xFFEF4444).copy(alpha = 0.2f) else Color(0xFF10B981).copy(alpha = 0.2f),
                            shape = RoundedCornerShape(8.dp)
                        ) {
                            Text("$pct%", fontSize = 12.sp, fontWeight = FontWeight.W700,
                                color = if (isLoud) Color(0xFFEF4444) else Color(0xFF10B981),
                                modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp))
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                    Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                        if (!state.isRecording && history.isEmpty()) {
                            Column(
                                modifier = Modifier.align(Alignment.Center),
                                horizontalAlignment = Alignment.CenterHorizontally
                            ) {
                                Icon(Icons.Default.MicNone, "mic", tint = Color.White.copy(alpha = 0.15f), modifier = Modifier.size(48.dp))
                                Spacer(Modifier.height(12.dp))
                                Text("Увімкни запис аудіо для старту", fontSize = 14.sp, color = Color.White.copy(alpha = 0.3f))
                            }
                        } else {
                            val hist = history.toList()
                            Canvas(modifier = Modifier.fillMaxSize()) {
                                val w = size.width
                                val h = size.height
                                if (hist.size < 2) return@Canvas

                                // Threshold line
                                val thy = h - (settings.threshold * h)
                                drawLine(Color(0xFFEF4444).copy(alpha = 0.5f), Offset(0f, thy), Offset(w, thy), strokeWidth = 1.5f)

                                // Volume line
                                val step = w / 250f
                                val path = Path()
                                for (i in hist.indices) {
                                    val x = i * step
                                    val y = h - (hist[i].coerceIn(0f, 1f) * h)
                                    if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
                                }
                                drawPath(path, if (isLoud) Color(0xFFEF4444) else Color(0xFF10B981), style = Stroke(width = 2f))

                                // Fill
                                val lastX = (hist.size - 1) * step
                                path.lineTo(lastX, h)
                                path.lineTo(0f, h)
                                path.close()
                                drawPath(path, if (isLoud) Color(0xFFEF4444).copy(alpha = 0.15f) else Color(0xFF10B981).copy(alpha = 0.15f))
                            }
                        }
                    }
                }
            }

            Spacer(Modifier.height(16.dp))

            // Debug panel
            if (showDebug && state.isRecording) {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = Color.Black.copy(alpha = 0.3f)),
                    shape = RoundedCornerShape(12.dp),
                ) {
                    Column(modifier = Modifier.padding(12.dp)) {
                        Text("🔍 DEBUG", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.Yellow)
                        Spacer(Modifier.height(4.dp))
                        Text("raw:${(state.rawLevel*100).toInt()}% bg:${(state.backgroundLevel*100).toInt()}% thr:${(settings.threshold*100).toInt()}% cd:${state.isCooldown}", fontSize = 11.sp, color = Color.Yellow, fontFamily = FontFamily.Monospace)
                    }
                }
                Spacer(Modifier.height(16.dp))
            }

            // Controls
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(
                    onClick = {
                        if (state.isRecording) {
                            ap.stop()
                        } else {
                            if (ap.hasPermission()) ap.start()
                            else permLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        }
                    },
                    modifier = Modifier.weight(1f).height(56.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (state.isRecording) Color(0xFFEF4444) else Color(0xFF10B981)
                    ),
                    shape = RoundedCornerShape(16.dp)
                ) {
                    Icon(
                        if (state.isRecording) Icons.Default.Stop else Icons.Default.Mic,
                        null, modifier = Modifier.size(20.dp)
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(if (state.isRecording) "Зупинити" else "Почати запис", fontSize = 16.sp, fontWeight = FontWeight.W600)
                }
                OutlinedButton(
                    onClick = { ap.reset() },
                    modifier = Modifier.size(56.dp),
                    shape = RoundedCornerShape(16.dp),
                    border = BorderStroke(1.dp, Brush.horizontalGradient(listOf(Color(0xFF6366F1), Color(0xFF6366F1)))),
                    contentPadding = PaddingValues(0.dp)
                ) {
                    Icon(Icons.Default.Refresh, null, tint = Color(0xFF6366F1))
                }
            }

            Spacer(Modifier.height(16.dp))

            // Info row
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                InfoCard("Поріг", "${(settings.threshold * 100).toInt()}%", Modifier.weight(1f))
                InfoCard("Підсилення", "${settings.gain}x", Modifier.weight(1f))
                InfoCard("Тривалість", "${settings.durationSeconds}с", Modifier.weight(1f))
            }

            // Calibration bar
            if (state.isCalibrating) {
                Spacer(Modifier.height(16.dp))
                LinearProgressIndicator(
                    progress = { state.calibrationProgress },
                    modifier = Modifier.fillMaxWidth().height(4.dp).clip(RoundedCornerShape(2.dp)),
                    color = Color(0xFF10B981),
                )
            }

            // Error
            state.error?.let { err ->
                Spacer(Modifier.height(16.dp))
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = Color(0xFFEF4444).copy(alpha = 0.15f)),
                    shape = RoundedCornerShape(16.dp),
                ) {
                    Text(err, color = Color(0xFFEF4444), fontSize = 13.sp, modifier = Modifier.padding(16.dp), textAlign = TextAlign.Center)
                }
            }
        }
    }

    // Settings Modal
    if (showSettings) {
        SettingsModal(settings = settings, onDismiss = { showSettings = false }, onReset = {
            settings.threshold = 0.04f
            settings.pricePerSnore = 100
            settings.durationSeconds = 1
            settings.gain = 10f
        })
    }
}

@Composable
fun InfoCard(label: String, value: String, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.03f)),
        shape = RoundedCornerShape(14.dp),
    ) {
        Column(
            modifier = Modifier.padding(12.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(value, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Color.White)
            Spacer(Modifier.height(4.dp))
            Text(label, fontSize = 10.sp, color = Color.White.copy(alpha = 0.6f), letterSpacing = 0.5.sp)
        }
    }
}

@Composable
fun SettingsModal(settings: SnoreSettings, onDismiss: () -> Unit, onReset: () -> Unit) {
    var threshold by remember { mutableFloatStateOf(settings.threshold) }
    var price by remember { mutableIntStateOf(settings.pricePerSnore) }
    var duration by remember { mutableIntStateOf(settings.durationSeconds) }
    var gain by remember { mutableFloatStateOf(settings.gain) }

    Box(
        modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.7f))
            .pointerInput(Unit) { detectTapGestures { onDismiss() } },
        contentAlignment = Alignment.BottomCenter
    ) {
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = Color(0xFF1C2128)),
            shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp),
        ) {
            Column(modifier = Modifier.padding(24.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("Налаштування", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Color.White)
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, null, tint = Color.White.copy(alpha = 0.7f))
                    }
                }
                Spacer(Modifier.height(24.dp))

                SettingRow("Чутливість", "Поріг детекції (менше = чутливіше)", "${(threshold*100).toInt()}%", Color(0xFF6366F1)) {
                    threshold = (threshold - 0.01f).coerceIn(0.01f, 0.50f).toBigDecimal().setScale(2, java.math.RoundingMode.HALF_UP).toFloat()
                    settings.threshold = threshold
                }
                SettingRow("", "", "", Color(0xFF6366F1), onPlus = {
                    threshold = (threshold + 0.01f).coerceIn(0.01f, 0.50f).toBigDecimal().setScale(2, java.math.RoundingMode.HALF_UP).toFloat()
                    settings.threshold = threshold
                })

                Spacer(Modifier.height(8.dp))

                SettingRow("Ціна за храп", "Скільки коштує 1 храп", "${price}₴", Color(0xFFEF4444), onMinus = {
                    price = (price - 10).coerceIn(10, 500); settings.pricePerSnore = price
                }, onPlus = {
                    price = (price + 10).coerceIn(10, 500); settings.pricePerSnore = price
                })

                Spacer(Modifier.height(8.dp))

                SettingRow("Тривалість", "Мін. час звуку (сек)", "${duration}с", Color(0xFF10B981), onMinus = {
                    duration = (duration - 1).coerceIn(1, 5); settings.durationSeconds = duration
                }, onPlus = {
                    duration = (duration + 1).coerceIn(1, 5); settings.durationSeconds = duration
                })

                Spacer(Modifier.height(8.dp))

                SettingRow("Підсилення", "Збільшує чутливість на відстані", String.format("%.1fx", gain), Color(0xFF8B5CF6), onMinus = {
                    gain = (gain - 0.5f).coerceIn(1f, 20f).toBigDecimal().setScale(1, java.math.RoundingMode.HALF_UP).toFloat(); settings.gain = gain
                }, onPlus = {
                    gain = (gain + 0.5f).coerceIn(1f, 20f).toBigDecimal().setScale(1, java.math.RoundingMode.HALF_UP).toFloat(); settings.gain = gain
                })

                Spacer(Modifier.height(24.dp))

                OutlinedButton(
                    onClick = { onReset(); threshold = 0.04f; price = 100; duration = 1; gain = 10f },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp),
                    border = BorderStroke(1.dp, Brush.horizontalGradient(listOf(Color(0xFF6366F1), Color(0xFF6366F1)))),
                    contentPadding = PaddingValues(vertical = 14.dp)
                ) {
                    Icon(Icons.Default.RestartAlt, null, tint = Color(0xFF6366F1))
                    Spacer(Modifier.width(8.dp))
                    Text("Скинути налаштування", color = Color(0xFF6366F1), fontWeight = FontWeight.W600)
                }
            }
        }
    }
}

@Composable
fun SettingRow(
    label: String, subtitle: String, value: String, color: Color,
    onMinus: () -> Unit = {}, onPlus: () -> Unit = {}
) {
    Row(
        modifier = Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.03f), RoundedCornerShape(16.dp)).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(label, fontSize = 15.sp, fontWeight = FontWeight.W600, color = Color.White)
            if (subtitle.isNotEmpty()) Text(subtitle, fontSize = 12.sp, color = Color.White.copy(alpha = 0.5f))
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconButton(onClick = onMinus, modifier = Modifier.size(40.dp).background(color.copy(alpha = 0.15f), RoundedCornerShape(10.dp))) {
                Text("−", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            }
            Text(value, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = color,
                modifier = Modifier.background(color.copy(alpha = 0.15f), RoundedCornerShape(10.dp)).padding(horizontal = 14.dp, vertical = 8.dp))
            IconButton(onClick = onPlus, modifier = Modifier.size(40.dp).background(color.copy(alpha = 0.15f), RoundedCornerShape(10.dp))) {
                Text("+", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

