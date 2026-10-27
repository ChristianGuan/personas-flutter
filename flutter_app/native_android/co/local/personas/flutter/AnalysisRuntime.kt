package co.local.personas.flutter

import android.content.Context
import android.app.ActivityManager
import android.net.Uri
import android.util.AtomicFile
import co.local.personas.data.*
import co.local.personas.domain.MatchDecision
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** Keep publication protected too: returning from NonCancellable+IO into a cancelled
 * caller may throw before the next statement. The outer block retains Main. */
internal suspend fun finishAnalysis(storage: CoroutineDispatcher,persist: ()->Unit,publish: ()->Unit) {
    withContext(NonCancellable) {
        try {withContext(storage) {persist()}} finally {publish()}
    }
}

/** Application-owned inference. Activities/channels may detach without stopping a search. */
class AnalysisRuntime internal constructor(private val context: Context) {
    companion object {
        @Volatile private var instance: AnalysisRuntime? = null
        fun get(context: Context): AnalysisRuntime = instance ?: synchronized(this) {
            instance ?: AnalysisRuntime(context.applicationContext).also { instance = it }
        }
    }
    val worker = Executors.newSingleThreadExecutor().asCoroutineDispatcher()
    val engine = OpenCvFaces(context)
    val source = ContentPhotos(context.contentResolver)
    val refs = ConcurrentHashMap<String, List<FoundFace>>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val storage = Executors.newSingleThreadExecutor().asCoroutineDispatcher()
    private val file = AtomicFile(File(context.cacheDir, "personas-last-analysis.json"))
    private val listeners = mutableSetOf<(Map<String, Any?>) -> Unit>()
    private var job: Job? = null
    private var current: Run? = null
    private var saved: Map<String, Any?>? = null
    private var loaded = false
    private var revision = 0
    private class Run(val id: Int, val ids: List<Uri>, val faces: List<FloatArray>, var context: Map<String, Any?>) {
        val token = UUID.randomUUID().toString()
        val events = mutableListOf<Map<String, Any?>>()
        var done: Map<String, Any?>? = null
        var interruption: String? = null
        var active = true
        var cancelling = false
        var cancelAt: Long? = null
        val diagnostics = mutableMapOf<String,Long>()
    }
    val active get() = current?.active == true
    val cancelling get() = current?.cancelling == true
    val token get() = current?.token
    val total get() = current?.ids?.size ?: 0
    val processed get() = current?.events?.size ?: 0
    val matches get() = current?.events?.count { it["outcome"] in listOf("match", "confirmed") } ?: 0
    fun observe(listener: (Map<String, Any?>) -> Unit) { listeners.add(listener) }
    fun detach(listener: (Map<String, Any?>) -> Unit) { listeners.remove(listener) }
    private fun emit(event: Map<String, Any?>) { listeners.toList().forEach { listener -> runCatching {listener(event)} } }
    private fun face(id: String): FloatArray = refs[id.substringBeforeLast(':')]
        ?.getOrNull(id.substringAfterLast(':').toInt())?.embedding ?: error("Referencia caducada")

    suspend fun snapshot(): Map<String, Any?>? {
        if (!loaded) {
            val revision = this.revision
            val disk = withContext(storage) {
                synchronized(this@AnalysisRuntime) { runCatching { file.openRead().use { jsonValue(JSONObject(it.reader().readText())) as Map<String, Any?> } }.getOrNull() }
            }
            if (!loaded && this.revision == revision) {
                loaded = true
                if (current == null) saved = disk?.let {
                    val inactive = it + ("referencesAvailable" to false)
                    if (inactive["active"] == true) inactive + mapOf("active" to false,
                        "done" to mapOf("type" to "done", "runId" to inactive["runId"], "cancelled" to true,
                            "error" to if(inactive["cancelling"]==true)null else "Android interrumpió el análisis. Revisa los resultados parciales y elige de nuevo tu referencia."))
                    else inactive
                }
            }
        }
        return current?.let { snapshot(it) } ?: saved
    }
    private fun snapshot(run: Run) = mapOf(
        "runId" to run.id, "context" to run.context, "events" to run.events.toList(),
        "active" to run.active, "cancelling" to run.cancelling, "done" to run.done, "referencesAvailable" to true,
        "backgroundMode" to "androidService"
    )
    fun prepare(run: Int, ids: List<Uri>, faces: List<String>, context: Map<String, Any?>): String {
        check(!active)
        require(ids.isNotEmpty() && faces.isNotEmpty())
        val next = Run(run, ids, faces.map(::face), context)
        revision++
        current = next; saved = null; loaded = true
        val initial = snapshot(next)
        scope.launch(storage) { persist(initial) }
        AnalysisService.removeCompletion(context = this.context)
        return next.token
    }
    fun launch(token: String) {
        val run = current ?: return
        if (run.token != token || !run.active || run.cancelling || job != null) return
        job = scope.launch {
            var cancelled = false
            var failure: String? = null
            try {
                val feedback = run.context["feedback"] as? Map<*, *> ?: emptyMap<String, Boolean>()
                val memoryManager=context.getSystemService(ActivityManager::class.java)
                val memory=ActivityManager.MemoryInfo().also(memoryManager::getMemoryInfo)
                val prefetch=BatchPhotoSearch.recommendedPrefetchBitmapBytes(Runtime.getRuntime().maxMemory(),memoryManager.isLowRamDevice || memory.lowMemory)
                BatchPhotoSearch(source, engine, worker,prefetch).run(run.ids, run.faces,onMetrics={ values ->
                    if(!run.cancelling && run.active) for((key,value) in values) run.diagnostics[key]=(run.diagnostics[key] ?: 0)+value
                }) { id, outcome ->
                    if(run.cancelling || !run.active)return@run
                    val found = outcome.getOrNull()
                    var decision = when {
                        found == null -> "unreadable"
                        !found.hasFaces -> "noFace"
                        found.decision == MatchDecision.MATCH -> "match"
                        found.decision == MatchDecision.REVIEW -> "review"
                        else -> "none"
                    }
                    if (decision != "unreadable" && feedback.containsKey(found?.inputKey)) {
                        decision = if (feedback[found?.inputKey] == true) "confirmed" else "rejected"
                    }
                    val event = mapOf("type" to "photo", "runId" to run.id, "id" to id.toString(),
                        "outcome" to decision, "key" to found?.inputKey)
                    run.events.add(event); emit(event)
                    if (run.events.size % 25 == 0) {
                        val checkpoint = snapshot(run)
                        scope.launch(storage) { persist(checkpoint) }
                    }
                }
            } catch (_: CancellationException) { cancelled = true }
            catch (_: Exception) { failure = "No se pudo terminar el análisis. Revisa los resultados parciales y vuelve a intentarlo." }
            finally {
                run.cancelAt?.let {run.diagnostics["cancelLatencyMs"]=(System.nanoTime()-it)/1_000_000}
                val done = mapOf("type" to "done", "runId" to run.id, "cancelled" to cancelled, "diagnostics" to run.diagnostics.toMap(),
                    "error" to (run.interruption ?: failure))
                val final = snapshot(run) + mapOf("active" to false, "done" to done)
                finishAnalysis(storage,{persist(final)}) {
                    if (current === run) {
                        run.done=done;run.active=false;job=null
                        emit(done)
                    }
                }
            }
        }
    }
    fun cancel(id: Int? = null, token: String? = null, reason: String? = null) {
        val run = current ?: return
        if (!run.active || run.cancelling || (id != null && run.id != id) || (token != null && run.token != token)) return
        run.cancelAt=System.nanoTime()
        run.cancelling=true
        run.interruption = reason
        emit(mapOf("type" to "status","runId" to run.id,"cancelling" to true))
        val requested=snapshot(run)
        scope.launch(storage){persist(requested)}
        if (job != null) job?.cancel()
        else {
            // Cancellation while the foreground service is still starting.
            job = scope.launch {
                val done = mapOf("type" to "done", "runId" to run.id, "cancelled" to true, "error" to reason)
                val final = snapshot(run) + mapOf("active" to false, "done" to done)
                finishAnalysis(storage,{persist(final)}) {
                    if(current===run){run.active=false;run.done=done;job=null;emit(done)}
                }
            }
        }
    }
    suspend fun update(context: Map<String, Any?>) {
        val run = current
        val state = if (run != null) {
            if (run.active || run.id != context["runId"]) return
            run.context = context; snapshot(run)
        } else {
            val previous = saved ?: return
            if (previous["runId"] != context["runId"]) return
            (previous + ("context" to context)).also { saved = it }
        }
        withContext(storage) { persist(state) }
    }
    suspend fun clear() {
        check(!active)
        revision++
        current = null; saved = null; loaded = true; refs.clear()
        withContext(worker) { engine.clearAnalysisCache() }
        withContext(storage) { synchronized(this@AnalysisRuntime) { file.delete() } }
        AnalysisService.removeCompletion(context)
    }
    @Synchronized private fun persist(value: Map<String, Any?>) {
        var stream: java.io.FileOutputStream? = null
        try {
            stream = file.startWrite()
            stream.write(JSONObject(value).toString().toByteArray(Charsets.UTF_8))
            file.finishWrite(stream)
        } catch (_: Exception) { stream?.let { file.failWrite(it) } }
    }
    private fun jsonValue(value: Any?): Any? = when (value) {
        JSONObject.NULL -> null
        is JSONObject -> value.keys().asSequence().associateWith { jsonValue(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { jsonValue(value.get(it)) }
        else -> value
    }
}
