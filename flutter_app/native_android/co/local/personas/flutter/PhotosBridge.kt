package co.local.personas.flutter

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.ClipData
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.RectF
import android.net.Uri
import android.os.Build
import android.os.ext.SdkExtensions
import android.provider.MediaStore
import android.provider.Settings
import co.local.personas.data.*
import co.local.personas.domain.MatchDecision
import co.local.personas.domain.Matching
import io.flutter.plugin.common.*
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** Platform integration only: production inference/HEIC/cache are the existing Android source. */
class PhotosBridge(private val activity: MainActivity,messenger: BinaryMessenger) : MethodChannel.MethodCallHandler,EventChannel.StreamHandler {
    private val methods=MethodChannel(messenger,"co.local.personas/photos")
    private val events=EventChannel(messenger,"co.local.personas/events")
    private var sink: EventChannel.EventSink?=null
    private val scope=CoroutineScope(SupervisorJob()+Dispatchers.Main.immediate)
    private val runtime=AnalysisRuntime.get(activity)
    private val worker get()=runtime.worker
    private val engine get()=runtime.engine
    private val source get()=runtime.source
    private val albums=MediaStoreAlbums(activity.applicationContext)
    private val refs get()=runtime.refs
    private val previews=Semaphore(2)
    private var job: Job?=null
    private var notificationRequest: MethodChannel.Result?=null
    private val notificationPrefs=activity.getSharedPreferences("personas-notifications",Context.MODE_PRIVATE)
    private val analysisListener: (Map<String,Any?>)->Unit={event -> sink?.success(event)}
    private var picker: MethodChannel.Result?=null
    private var accessRequest: MethodChannel.Result?=null
    private var incoming=emptyList<Uri>()
    init {methods.setMethodCallHandler(this);events.setStreamHandler(this);runtime.observe(analysisListener)}
    override fun onListen(arguments: Any?,sink: EventChannel.EventSink) {
        this.sink=sink
        if(incoming.isNotEmpty()) {
            sink.success(mapOf("type" to "incoming","ids" to incoming.map(Uri::toString)))
            incoming=emptyList()
        }
    }
    override fun onCancel(arguments: Any?) {sink=null}
    private fun error(result: MethodChannel.Result,e: Throwable) {
        val message=when(e) {
            is PhotoDecodeException -> "No pudimos leer esta imagen. Puede estar incompleta o usar una variante HEIC no compatible. Vuelve a descargar el original o elige otra foto."
            is SecurityException -> "No tenemos acceso a estas fotos. Vuelve a elegirlas o revisa el permiso."
            is CancellationException -> "Acción cancelada."
            else -> if(Build.VERSION.SDK_INT>=31 && e is android.app.ForegroundServiceStartNotAllowedException)
                "Vuelve a Personas y pulsa Buscar para iniciar el análisis antes de cambiar de app."
                else "No se pudo completar la acción. Revisa el acceso y, si la foto está en la nube, la conexión."
        }
        result.error(if(e is CancellationException) "cancelled" else "photo_error",message,null)
    }
    private fun async(result: MethodChannel.Result,block: suspend ()->Any?) {scope.launch {
        try {result.success(block())} catch(e: Exception) {error(result,e)}
    }}
    private fun access()=libraryAccess(activity).name.lowercase()
    private fun albumMap(album: LocalAlbum)=mapOf("id" to "${album.key.volume}:${album.key.bucketId}","name" to album.name,"cover" to album.cover.toString(),"count" to album.count)
    private suspend fun catalog(): Map<String,Any> {
        val access=access()
        return mapOf("access" to access,"albums" to if(access=="none") emptyList() else albums.albums().map(::albumMap))
    }
    private fun key(id: String): AlbumKey {val parts=id.split(':',limit=2);require(parts.size==2);return AlbumKey(parts[0],parts[1])}
    private fun uri(id: String): Uri {
        val uri=Uri.parse(id)
        // file:// is used only by public instrumentation fixtures inside our private cache.
        require(uri.scheme=="content" || (uri.scheme=="file" && uri.path?.let {File(it).canonicalPath.startsWith(activity.cacheDir.canonicalPath+"/")}==true))
        return uri
    }
    private fun notifications(): Map<String,Boolean> {
        val manager=activity.getSystemService(NotificationManager::class.java)
        val granted=Build.VERSION.SDK_INT<33 || activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED
        val channelAllowed=manager.getNotificationChannel(AnalysisService.completionChannel(activity))?.importance!=NotificationManager.IMPORTANCE_NONE
        val asked=notificationPrefs.getBoolean("asked",false)
        return mapOf("enabled" to (granted && manager.areNotificationsEnabled() && channelAllowed),"asked" to asked,
            "canAsk" to (Build.VERSION.SDK_INT>=33 && !granted && (!asked || activity.shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS))))
    }
    fun notificationsResult() {notificationRequest?.success(notifications());notificationRequest=null}
    override fun onMethodCall(call: MethodCall,result: MethodChannel.Result) {
        try {when(call.method) {
            "initialize" -> async(result) {mapOf("platform" to "android","access" to access(),"incoming" to incoming.map(Uri::toString),
                "notifications" to notifications(),"backgroundMode" to "androidService","search" to runtime.snapshot()).also {incoming=emptyList()}}
            "searchSnapshot" -> async(result) {runtime.snapshot()}
            "updateSearch" -> async(result) {runtime.update(call.arguments as Map<String,Any?>);null}
            "notifications" -> result.success(notifications())
            "notificationSettings" -> {
                activity.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,activity.packageName));result.success(null)
            }
            "requestNotifications" -> {
                check(notificationRequest==null)
                if(notifications()["canAsk"]!=true) result.success(notifications())
                else {
                    notificationRequest=result
                    notificationPrefs.edit().putBoolean("asked",true).apply()
                    try {activity.requestNotifications()} catch(e: Exception) {notificationRequest=null;throw e}
                }
            }
            "pick" -> {
                check(picker==null && job?.isActive!=true && !runtime.active)
                picker=result
                try {activity.pick(call.argument<String>("kind") ?: "photos")} catch(e: Exception) {picker=null;throw e}
            }
            "albums" -> async(result) {catalog()}
            "requestAccess" -> {
                check(accessRequest==null);accessRequest=result
                try {activity.requestAccess()} catch(e: Exception) {accessRequest=null;throw e}
            }
            "albumPhotos" -> async(result) {albums.photos(key(call.argument<String>("id")!!)).map(Uri::toString)}
            "reference" -> {
                check(job?.isActive!=true && !runtime.active)
                val id=call.argument<String>("id")!!
                job=scope.launch {
                    try {
                        val bitmap=source.decode(uri(id))
                        try {
                            val faces=withContext(worker) {engine.analyzeReference(bitmap)}
                            ensureActive()
                            val token=UUID.randomUUID().toString();refs[token]=faces
                            result.success(mapOf("token" to token,"image" to id,"width" to bitmap.width,"height" to bitmap.height,
                                "faces" to faces.mapIndexed {index,f -> mapOf("id" to "$token:$index",
                                    "x" to (f.bounds.left/bitmap.width).toDouble(),"y" to (f.bounds.top/bitmap.height).toDouble(),
                                    "width" to (f.bounds.width()/bitmap.width).toDouble(),"height" to (f.bounds.height()/bitmap.height).toDouble())}))
                        } finally {bitmap.recycle()}
                    } catch(e: Exception) {error(result,e)}
                }
            }
            "releaseReference" -> {refs.remove(call.argument<String>("token"));result.success(null)}
            "image" -> async(result) {previews.withPermit {withContext(Dispatchers.IO) {
                val edge=(call.argument<Int>("edge") ?: 512).coerceIn(64,1600)
                val bitmap=ContentPhotos(activity.contentResolver,edge).decode(uri(call.argument<String>("id")!!))
                var cropped: Bitmap?=null
                try {
                    val crop=call.argument<List<Number>>("crop")
                    val display=if(crop!=null && crop.size==4) {
                        val x=crop[0].toFloat()*bitmap.width;val y=crop[1].toFloat()*bitmap.height
                        faceThumbnail(bitmap,RectF(x,y,x+crop[2].toFloat()*bitmap.width,y+crop[3].toFloat()*bitmap.height)).also {cropped=it}
                    } else bitmap
                    ByteArrayOutputStream().use {output -> display.compress(Bitmap.CompressFormat.JPEG,94,output);output.toByteArray()}
                } finally {cropped?.let {if(it!==bitmap) it.recycle()};bitmap.recycle()}
            }}}
            "search" -> {
                check(job?.isActive!=true && !runtime.active)
                val run=call.argument<Int>("runId")!!
                val ids=call.argument<List<String>>("ids")!!.distinct().map(::uri)
                val faces=call.argument<List<String>>("faces")!!
                val context=call.argument<Map<String,Any?>>("context") ?: emptyMap()
                val token=runtime.prepare(run,ids,faces,context)
                try {activity.startForegroundService(Intent(activity,AnalysisService::class.java).putExtra("token",token))}
                catch(e: Exception) {runtime.cancel(run,reason="No se pudo iniciar el análisis en segundo plano. Vuelve a abrir Personas e inténtalo otra vez.");throw e}
                result.success(mapOf("backgroundMode" to "androidService"))
            }
            "cancel" -> {
                if(runtime.active) runtime.cancel(call.argument<Int>("runId")) else job?.cancel()
                result.success(null)
            }
            "clear" -> async(result) {
                check(job?.isActive!=true && !runtime.active);incoming=emptyList();runtime.clear();null
            }
            "share" -> {
                val ids=call.argument<List<String>>("ids")!!.distinct().map(::uri)
                require(ids.isNotEmpty() && ids.all {it.scheme=="content"})
                val share=Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                    type="image/*";putParcelableArrayListExtra(Intent.EXTRA_STREAM,ArrayList(ids))
                    clipData=ClipData.newUri(activity.contentResolver,"Fotos seleccionadas",ids.first()).apply {ids.drop(1).forEach {addItem(ClipData.Item(it))}}
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                activity.startActivity(Intent.createChooser(share,"Compartir fotos"));result.success(null)
            }
            "settings" -> {activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:"+activity.packageName)));result.success(null)}
            "cloudSettings" -> {
                check(Build.VERSION.SDK_INT>=33 || (Build.VERSION.SDK_INT>=30 && SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R)>=3))
                activity.startActivity(Intent(MediaStore.ACTION_PICK_IMAGES_SETTINGS));result.success(null)
            }
            else -> result.notImplemented()
        }} catch(e: Exception) {error(result,e)}
    }
    fun picked(uris: List<Uri>) {
        uris.distinct().forEach {uri ->
            try {activity.contentResolver.takePersistableUriPermission(uri,Intent.FLAG_GRANT_READ_URI_PERMISSION)} catch(_: SecurityException) { /* Provider may grant only temporary access. */ }
        }
        picker?.success(uris.distinct().map(Uri::toString));picker=null
    }
    fun accessResult() {val result=accessRequest ?: return;accessRequest=null;async(result) {catalog()}}
    fun receive(intent: Intent) {scope.launch {
        if(intent.getBooleanExtra("openAnalysis",false)) {
            sink?.success(mapOf("type" to "openAnalysis"));return@launch
        }
        val uris=sharedImageUris(intent,activity.contentResolver)
        if(uris.isNotEmpty()) {
            if(sink==null) incoming=uris else sink?.success(mapOf("type" to "incoming","ids" to uris.map(Uri::toString)))
        }
    }}
    fun close() {runtime.detach(analysisListener);job?.cancel();scope.cancel();methods.setMethodCallHandler(null);events.setStreamHandler(null)}
}
