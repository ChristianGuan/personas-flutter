package co.local.personas.flutter

import android.Manifest
import android.os.Build
import android.content.Intent
import android.os.Bundle
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    private lateinit var bridge: PhotosBridge
    private var pendingIntent: Intent?=null
    private val referencePicker=registerForActivityResult(ActivityResultContracts.PickVisualMedia()) {bridge.picked(listOfNotNull(it))}
    private val photosPicker=registerForActivityResult(ActivityResultContracts.PickMultipleVisualMedia()) {bridge.picked(it)}
    private val filesPicker=registerForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) {bridge.picked(it)}
    private val notificationPicker=registerForActivityResult(ActivityResultContracts.RequestPermission()) {bridge.notificationsResult()}
    private val accessPicker=registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {bridge.accessResult()}
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        bridge=PhotosBridge(this,engine.dartExecutor.binaryMessenger)
        pendingIntent?.let {bridge.receive(it)}
        pendingIntent=null
    }
    private fun receive(intent: Intent) {if(::bridge.isInitialized) bridge.receive(intent) else pendingIntent=intent}
    override fun onCreate(savedInstanceState: Bundle?) {super.onCreate(savedInstanceState);if(savedInstanceState==null) receive(intent)}
    override fun onNewIntent(intent: Intent) {super.onNewIntent(intent);setIntent(intent);receive(intent)}
    override fun onDestroy() {if(::bridge.isInitialized) bridge.close();super.onDestroy()}
    fun pick(kind: String) {
        when(kind) {
            "reference" -> referencePicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            "files" -> filesPicker.launch(arrayOf("image/*"))
            else -> photosPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
        }
    }
    fun requestNotifications() {if(Build.VERSION.SDK_INT>=33) notificationPicker.launch(Manifest.permission.POST_NOTIFICATIONS) else bridge.notificationsResult()}
    fun requestAccess() = accessPicker.launch(co.local.personas.data.libraryPermissions())
}
