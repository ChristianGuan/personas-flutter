package co.local.personas.flutter

import android.app.*
import android.content.Intent
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.*

/** User-started local file processing; no boot restart or detached Activity ownership. */
class AnalysisService : Service() {
    companion object {
        private const val PROGRESS = 701
        private const val COMPLETION = 702
        private const val WORK_CHANNEL = "personas_analysis"
        private const val DONE_CHANNEL = "personas_analysis_results"
        private const val LEGACY_DONE_CHANNEL = "personas_analysis_done"
        private const val CANCEL = "co.local.personas.CANCEL_ANALYSIS"
        fun completionChannel(context: Context): String {
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(DONE_CHANNEL) != null) return DONE_CHANNEL
            val previous = manager.getNotificationChannel(LEGACY_DONE_CHANNEL) ?: return DONE_CHANNEL
            // Never bypass a user's blocked, quiet or explicitly chosen channel.
            if (Build.VERSION.SDK_INT < 29 || previous.hasUserSetImportance() ||
                previous.importance != NotificationManager.IMPORTANCE_DEFAULT ||
                (Build.VERSION.SDK_INT >= 30 && previous.hasUserSetSound())) return LEGACY_DONE_CHANNEL
            return DONE_CHANNEL
        }
        fun removeCompletion(context: Context) {
            context.getSystemService(NotificationManager::class.java).cancel(COMPLETION)
        }
    }
    private lateinit var runtime: AnalysisRuntime
    private var wakeLock: PowerManager.WakeLock? = null
    private var lastUpdate = 0L
    private var runningToken: String? = null
    private lateinit var doneChannel: String
    private val timer = Handler(Looper.getMainLooper())
    private val timeout = Runnable { interrupt() }
    private val listener: (Map<String, Any?>) -> Unit = { event ->
        if (event["type"] == "done") finish(event)
        else if (event["cancelling"]==true || SystemClock.elapsedRealtime() - lastUpdate >= 1000) {
            getSystemService(NotificationManager::class.java).notify(PROGRESS, progress())
            lastUpdate = SystemClock.elapsedRealtime()
        }
    }
    override fun onCreate() {
        super.onCreate()
        runtime = AnalysisRuntime.get(this)
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(WORK_CHANNEL, "Análisis en curso", NotificationManager.IMPORTANCE_LOW))
        doneChannel = completionChannel(this)
        val completion = NotificationChannel(doneChannel, "Análisis terminado", NotificationManager.IMPORTANCE_HIGH)
        if (doneChannel == DONE_CHANNEL) manager.getNotificationChannel(LEGACY_DONE_CHANNEL)?.let { previous ->
            completion.setSound(previous.sound, previous.audioAttributes)
            completion.enableVibration(previous.shouldVibrate())
            completion.vibrationPattern = previous.vibrationPattern
            completion.enableLights(previous.shouldShowLights())
            completion.lightColor = previous.lightColor
            completion.setShowBadge(previous.canShowBadge())
            completion.lockscreenVisibility = previous.lockscreenVisibility
            previous.name = "Avisos de análisis anteriores"
            manager.createNotificationChannel(previous)
        }
        completion.description = "Te avisa cuando termina la búsqueda de tus fotos."
        manager.createNotificationChannel(completion)
        runtime.observe(listener)
    }
    override fun onBind(intent: Intent?) = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val token = intent?.getStringExtra("token")
        if (intent?.action == CANCEL) {
            runtime.cancel(token = token)
            if (!runtime.active) stopSelf()
            return START_NOT_STICKY
        }
        if (token == null || token != runtime.token || !runtime.active) {
            stopSelf(); return START_NOT_STICKY
        }
        runningToken = token
        try {
            if (Build.VERSION.SDK_INT >= 29) startForeground(PROGRESS, progress(), ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            else startForeground(PROGRESS, progress())
            wakeLock = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Personas:Analysis").apply {
                setReferenceCounted(false); acquire(6 * 60 * 60 * 1000L)
            }
            timer.postDelayed(timeout, 6 * 60 * 60 * 1000L)
            runtime.launch(token)
        } catch (_: Exception) {
            runtime.cancel(token = token, reason = "No se pudo mantener el análisis en segundo plano. Abre Halladin y vuelve a intentarlo.")
            cleanup(); stopSelf()
        }
        return START_NOT_STICKY
    }
    private fun open(): PendingIntent = PendingIntent.getActivity(this, 701,
        Intent(this, MainActivity::class.java).putExtra("openAnalysis", true).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun builder(channel: String) = Notification.Builder(this, channel)
        .setSmallIcon(co.local.personas.R.drawable.ic_analysis_notification)
        .setContentIntent(open()).setVisibility(Notification.VISIBILITY_PRIVATE)
        .setPublicVersion(Notification.Builder(this, channel).setSmallIcon(co.local.personas.R.drawable.ic_analysis_notification)
            .setContentTitle("Halladin").setContentText("Análisis de tus fotos").build())
    private fun progress(): Notification {
        val cancel = Intent(this, AnalysisService::class.java).setAction(CANCEL)
            .setData(android.net.Uri.parse("personas://analysis/${runtime.token}"))
            .putExtra("token", runtime.token)
        return builder(WORK_CHANNEL).setContentTitle(if(runtime.cancelling)"Cancelando análisis" else "Buscando en tus fotos")
            .setContentText(if(runtime.cancelling)"Terminando la foto en curso…" else "Procesadas ${runtime.processed} de ${runtime.total} fotos · ${runtime.matches} coincidencias")
            .setProgress(runtime.total, runtime.processed, runtime.total == 0)
            .setOngoing(true).setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, "Cancelar análisis",
                PendingIntent.getService(this, 702, cancel, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)).build()).build()
    }
    private fun finish(event: Map<String, Any?>) {
        cleanup(); stopForeground(STOP_FOREGROUND_REMOVE)
        if (event["cancelled"] != true || event["error"] != null) {
            val error = event["error"] != null
            val text = if (error) "El análisis se interrumpió. Abre Halladin para revisar lo encontrado."
                else "${runtime.matches} coincidencias · ${runtime.processed} fotos procesadas. Toca para revisarlas."
            try { getSystemService(NotificationManager::class.java).notify(COMPLETION,
                builder(doneChannel).setContentTitle(if (error) "Tu análisis necesita revisión" else "Tu análisis ha terminado")
                    .setContentText(text).setStyle(Notification.BigTextStyle().bigText(text)).setAutoCancel(true).build())
            } catch (_: SecurityException) { /* Permission is optional; results remain available in the app. */ }
        }
        runningToken = null; stopSelf()
    }
    private fun interrupt() {
        runtime.cancel(token = runningToken, reason = "Android detuvo el análisis en segundo plano. Revisa los resultados parciales y vuelve a buscar.")
        cleanup(); stopForeground(STOP_FOREGROUND_REMOVE); stopSelf()
    }
    override fun onTimeout(startId: Int, fgsType: Int) { interrupt() }
    private fun cleanup() { timer.removeCallbacks(timeout); wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null }
    override fun onDestroy() {
        runtime.detach(listener); cleanup()
        if (runningToken != null && runtime.active) runtime.cancel(token = runningToken,
            reason = "Android interrumpió el análisis. Revisa lo encontrado y vuelve a buscar.")
        super.onDestroy()
    }
}
