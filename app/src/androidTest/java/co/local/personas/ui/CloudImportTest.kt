package co.local.personas.ui

import android.content.ClipData
import android.content.ContentValues
import android.content.Intent
import android.accessibilityservice.AccessibilityService
import android.graphics.Bitmap
import android.net.Uri
import android.provider.MediaStore
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.requiredSizeIn
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import co.local.personas.data.sharedImageUris
import co.local.personas.ui.theme.PersonasTheme
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class CloudImportTest {
    @get:Rule val compose=createAndroidComposeRule<MainActivity>()

    private fun vm(): SearchViewModel {
        lateinit var vm: SearchViewModel
        compose.runOnUiThread {vm=ViewModelProvider(compose.activity)[SearchViewModel::class.java]}
        return vm
    }
    private fun screenshot(name: String,dialog: Boolean=false) {
        compose.waitForIdle()
        File(compose.activity.cacheDir,"qa-$name.png").outputStream().use {
            (if(dialog) compose.onNode(isDialog()) else compose.onRoot()).captureToImage().asAndroidBitmap().compress(Bitmap.CompressFormat.PNG,100,it)
        }
    }
    private fun withImages(realFace: Boolean=false,block: (List<Uri>)->Unit) {
        assumeTrue(android.os.Build.VERSION.SDK_INT>=29)
        val sample=if(realFace) {
            val name=InstrumentationRegistry.getArguments().getString("faceFixture")
            assumeTrue("Optional public face stays outside the APK",name!=null)
            File(compose.activity.cacheDir,name!!).also {assertTrue(it.isFile)}
        } else null
        val blank=Bitmap.createBitmap(128,128,Bitmap.Config.ARGB_8888).apply {eraseColor(android.graphics.Color.LTGRAY)}
        val resolver=compose.activity.contentResolver
        val launchIntent=Intent(compose.activity.intent)
        val inserted=mutableListOf<Uri>()
        try {
            repeat(2) {
                val uri=resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME,"personas-cloud-qa-$it.jpg")
                    put(MediaStore.Images.Media.MIME_TYPE,"image/jpeg")
                    put(MediaStore.Images.Media.RELATIVE_PATH,"Pictures/PersonasCloudQA-${UUID.randomUUID()}")
                    put(MediaStore.Images.Media.IS_PENDING,1)
                })!!
                inserted.add(uri)
                resolver.openOutputStream(uri)!!.use {out -> if(sample!=null) sample.inputStream().use {it.copyTo(out)} else blank.compress(Bitmap.CompressFormat.JPEG,95,out)}
                resolver.update(uri,ContentValues().apply {put(MediaStore.Images.Media.IS_PENDING,0)},null,null)
            }
            block(inserted)
        } finally {
            blank.recycle()
            compose.runOnUiThread {
                // ActivityScenario identifies lifecycle events by the original launch intent.
                // Production onNewIntent correctly replaces it with the shared image intent.
                compose.activity.intent=launchIntent
                val current=ViewModelProvider(compose.activity)[SearchViewModel::class.java]
                current.cancel();current.dismissImport()
            }
            inserted.forEach {resolver.delete(it,null,null)}
        }
    }
    private fun share(uris: List<Uri>): Intent = Intent(if(uris.size==1) Intent.ACTION_SEND else Intent.ACTION_SEND_MULTIPLE).apply {
        type="image/*"
        if(uris.size==1) putExtra(Intent.EXTRA_STREAM,uris.single()) else putParcelableArrayListExtra(Intent.EXTRA_STREAM,ArrayList(uris))
        clipData=ClipData.newUri(compose.activity.contentResolver,"Imágenes QA",uris.first()).apply {uris.drop(1).forEach {addItem(ClipData.Item(it))}}
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }

    @Test fun sharedImagesRejectNonImagesSchemesAndMalformedExtras() = withImages {images ->
        val resolver=compose.activity.contentResolver
        val text=resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI,ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME,"personas-qa-${UUID.randomUUID()}.txt")
            put(MediaStore.MediaColumns.MIME_TYPE,"text/plain")
            put(MediaStore.MediaColumns.IS_PENDING,1)
        })!!
        try {
            resolver.openOutputStream(text)!!.use {it.write("QA".toByteArray())}
            resolver.update(text,ContentValues().apply {put(MediaStore.MediaColumns.IS_PENDING,0)},null,null)
            val intent=share(listOf(images[0],images[0],images[1],text,Uri.parse("https://example.invalid/photo.jpg"),Uri.parse("file:///private/photo.jpg")))
            assertEquals(images,runBlocking {sharedImageUris(intent,resolver)})
            assertTrue(runBlocking {sharedImageUris(Intent(intent).setType("text/plain"),resolver)}.isEmpty())
            assertTrue(runBlocking {sharedImageUris(Intent(intent).setAction(Intent.ACTION_VIEW),resolver)}.isEmpty())
            val malformed=Intent(Intent.ACTION_SEND).setType("image/jpeg").putExtra(Intent.EXTRA_STREAM,"not a URI")
            assertTrue(runBlocking {sharedImageUris(malformed,resolver)}.isEmpty())
        } finally {resolver.delete(text,null,null)}
    }

    @Test fun incomingSinglePhotoCanBecomeReferenceWithoutLosingCandidates() = withImages(realFace=true) {images ->
        val vm=vm()
        compose.runOnUiThread {vm.addCandidates(listOf(images[1]));vm.receiveShared(share(listOf(images[0])))}
        compose.waitUntil(10_000) {vm.state.value.incomingPhotos.isNotEmpty()}
        compose.onNodeWithText("Usar como referencia").assertIsDisplayed().performClick()
        compose.waitUntil(30_000) {!vm.state.value.busy}
        assertNotNull(vm.state.value.chosen)
        assertEquals(listOf(images[1]),vm.state.value.photos)
        assertEquals(SearchStep.REFERENCE,vm.state.value.step)
        compose.runOnUiThread {vm.search()}
        compose.waitUntil(30_000) {!vm.state.value.busy}
        assertEquals(listOf(images[1]),vm.state.value.results)
        compose.runOnUiThread {vm.clear()}
    }

    @Test fun sharedIntentReusesSessionAndRequiresConfirmationBeforeMerging() = withImages(realFace=true) {images ->
        val vm=vm()
        compose.runOnUiThread {vm.reference(images[0])}
        compose.waitUntil(30_000) {!vm.state.value.busy}
        val reference=vm.state.value.reference
        compose.runOnUiThread {vm.addCandidates(listOf(images[0]))}
        val incoming=share(listOf(images[0],images[1],images[1])).setClass(compose.activity,MainActivity::class.java)
        compose.runOnUiThread {compose.activity.startActivity(incoming)}
        compose.waitUntil(10_000) {vm.state.value.incomingPhotos.isNotEmpty()}
        assertEquals(images,vm.state.value.incomingPhotos)
        assertEquals(listOf(images[0]),vm.state.value.photos)
        assertSame(vm,vm())
        screenshot("cloud-import-confirm",dialog=true)
        compose.onNodeWithText("Cancelar").performClick()
        assertEquals(listOf(images[0]),vm.state.value.photos)
        compose.runOnUiThread {compose.activity.startActivity(incoming)}
        compose.waitUntil(10_000) {vm.state.value.incomingPhotos.isNotEmpty()}
        compose.onNodeWithText("Añadir al conjunto").performClick()
        compose.waitUntil(10_000) {!vm.state.value.libraryLoading}
        assertEquals(images,vm.state.value.photos)
        assertSame(reference,vm.state.value.reference)
        assertEquals(SearchStep.ALBUMS,vm.state.value.step)
        screenshot("cloud-albums")
        compose.onNodeWithText("Google Fotos").performScrollTo().performClick()
        compose.onNodeWithText("Fotos de Google Fotos").assertIsDisplayed()
        screenshot("cloud-help",dialog=true)
        compose.onNodeWithText("Volver").performClick()
        assertEquals(images,vm.state.value.photos)
        assertSame(reference,vm.state.value.reference)
        compose.runOnUiThread {vm.clear()}
    }

    @Test fun incomingImagesWaitForRunningAnalysisAndSurviveCancellation() = withImages(realFace=true) {images ->
        val vm=vm()
        compose.runOnUiThread {vm.reference(images[0])}
        compose.waitUntil(30_000) {!vm.state.value.busy}
        // Unique URIs no longer imply unique content: use actual pixel variants so this
        // integration test cannot finish entirely from the new encoded-content cache.
        val source=co.local.personas.data.ContentPhotos(compose.activity.contentResolver)
        val bitmap=kotlinx.coroutines.runBlocking {source.decode(images[0])}.let {decoded ->
            decoded.copy(Bitmap.Config.ARGB_8888,true).also {decoded.recycle()}
        }
        val variants=(0..31).map {index -> File(compose.activity.cacheDir,"qa-import-work-$index.png").also {file ->
            bitmap.setPixel(0,0,android.graphics.Color.rgb(index*7,0,0))
            file.outputStream().use {bitmap.compress(Bitmap.CompressFormat.PNG,100,it)}
        }}
        bitmap.recycle()
        val scope=variants.map {Uri.fromFile(it)}
        try {
        compose.runOnUiThread {vm.addCandidates(scope);vm.search();vm.receiveShared(share(listOf(images[1])))}
        compose.waitUntil(10_000) {vm.state.value.incomingPhotos.isNotEmpty()}
        assertTrue(vm.state.value.busy)
        compose.onNodeWithText("Añadir al conjunto").assertDoesNotExist()
        compose.runOnUiThread {vm.acceptShared(asReference=false)}
        assertEquals(scope,vm.state.value.photos)
        compose.runOnUiThread {vm.cancel()}
        compose.waitUntil(30_000) {!vm.state.value.busy}
        assertTrue(vm.state.value.cancelled)
        assertEquals(listOf(images[1]),vm.state.value.incomingPhotos)
        compose.onNodeWithText("Añadir al conjunto").performClick()
        assertEquals(scope+images[1],vm.state.value.photos)
        assertNotNull(vm.state.value.chosen)
        compose.runOnUiThread {vm.clear()}
        } finally {variants.forEach {it.delete()}}
    }

    @Test fun largeTextCloudHelpAndUnavailableSettingsKeepAlternativesReachable() {
        var opened=false
        compose.runOnUiThread {
            compose.activity.setContent {
                val density=LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density,2f)) {
                    PersonasTheme {Box(Modifier.requiredSize(320.dp,480.dp)) {
                        CloudPhotosDialog("Ajustes no disponibles. Usa Compartir → Personas desde Google Fotos.",onPick={opened=true},onSettings={},onDismiss={},modifier=Modifier.requiredSizeIn(maxWidth=320.dp,maxHeight=480.dp))
                    }}
                }
            }
        }
        // A native Dialog window obtains its density from Android. The optional host run
        // also sets/restores the real system font scale, and verifies actual enlarged text.
        if(InstrumentationRegistry.getArguments().getString("verifySystemLargeText")=="true") {
            assertTrue(compose.activity.resources.configuration.fontScale>=1.9f)
            val title=compose.onNodeWithText("Fotos de Google Fotos").fetchSemanticsNode().boundsInRoot
            assertTrue(title.height/compose.activity.resources.displayMetrics.density>40f)
        }
        compose.onNodeWithText("Abrir selector de fotos").assertIsDisplayed()
        compose.onNodeWithText("Configurar nube").performScrollTo().assertIsDisplayed()
        screenshot("cloud-large-text",dialog=true)
        compose.onNodeWithText("Abrir selector de fotos").performClick()
        assertTrue(opened)
    }

    @Test fun cloudEntryOpensRealSystemSettingsAndPickerAndAllowsCancellation() {
        assumeTrue(android.os.Build.VERSION.SDK_INT>=33)
        assumeTrue(ActivityResultContracts.PickVisualMedia.isPhotoPickerAvailable(compose.activity))
        val vm=vm()
        val automation=InstrumentationRegistry.getInstrumentation().uiAutomation
        fun waitForExternalWindow() = compose.waitUntil(10_000) {
            val pkg=automation.rootInActiveWindow?.packageName?.toString()
            pkg!=null && pkg!=compose.activity.packageName && pkg!="com.android.systemui"
        }
        compose.onNodeWithText("Buscar a una persona").performClick()
        compose.onNodeWithText("Google Fotos · Elegir de la nube").performScrollTo().performClick()
        compose.onNodeWithText("Configurar nube").performScrollTo().performClick()
        try {waitForExternalWindow()} finally {automation.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)}
        compose.waitUntil(10_000) {compose.onAllNodesWithText("Fotos de Google Fotos").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithText("Abrir selector de fotos").performClick()
        try {waitForExternalWindow()} finally {automation.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)}
        compose.waitUntil(10_000) {compose.onAllNodesWithText("Elegir foto de referencia").fetchSemanticsNodes().isNotEmpty()}
        assertNull(vm.state.value.reference)
        assertTrue(vm.state.value.photos.isEmpty())
    }
}
