package co.local.personas.ui

import android.graphics.Bitmap
import android.net.Uri
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class HeicUiTest {
    @get:Rule val compose=createAndroidComposeRule<MainActivity>()
    @Test fun heicCanBeAReferenceResultAndPreviewAndBrokenReferenceKeepsValidState() {
        val name=InstrumentationRegistry.getArguments().getString("heicFixtures")
        assumeTrue(name!=null)
        val dir=File(compose.activity.cacheDir,name!!)
        val reference=Uri.fromFile(File(dir,"face-10bit.heic"))
        val scope=listOf("face-srgb.HEIC","face-10bit.heic","face-p3.heic","face-p3-10bit.heic","face-rotated-10bit.heic","face-mirrored-10bit.heic","blank.heic","broken.heic").map {Uri.fromFile(File(dir,it))}
        lateinit var vm: SearchViewModel
        compose.runOnUiThread {vm=ViewModelProvider(compose.activity)[SearchViewModel::class.java];vm.reference(reference)}
        compose.waitUntil(30_000) {!vm.state.value.busy}
        assertNotNull(vm.state.value.chosen)
        assertEquals(Bitmap.Config.ARGB_8888,vm.state.value.reference!!.config)
        val previous=vm.state.value.reference
        compose.runOnUiThread {vm.addCandidates(scope);vm.search()}
        compose.waitUntil(30_000) {!vm.state.value.busy}
        assertEquals(scope.take(6),vm.state.value.results)
        assertEquals(1,vm.state.value.skipped)
        assertEquals(PhotoOutcome.UNREADABLE,vm.state.value.reviews.last().outcome)
        // The lazy item exists before its HEIC thumbnail finishes decoding. Scroll
        // by its stable key, then wait for a real image instead of skipping loaders.
        compose.onNode(hasScrollToIndexAction()).performScrollToKey("result:"+scope.first())
        compose.waitUntil(30_000) {compose.onAllNodesWithContentDescription("Coincidencia. Tocar para ver imagen completa").fetchSemanticsNodes().isNotEmpty()}
        compose.onAllNodesWithContentDescription("Coincidencia. Tocar para ver imagen completa").onFirst().performClick()
        compose.waitUntil(10_000) {compose.onAllNodesWithContentDescription("Imagen completa para revisar").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithText("Seleccionar esta foto").performScrollTo().assertIsDisplayed()
        File(compose.activity.cacheDir,"qa-heic-preview.png").outputStream().use {
            compose.onNode(isDialog()).captureToImage().asAndroidBitmap().compress(Bitmap.CompressFormat.PNG,100,it)
        }
        compose.onNodeWithText("‹ Volver a las fotos").performScrollTo().performClick()
        compose.runOnUiThread {vm.reference(scope.last(),append=true)}
        compose.waitUntil(30_000) {!vm.state.value.busy}
        assertSame(previous,vm.state.value.reference)
        assertNotNull(vm.state.value.chosen)
        assertTrue(vm.state.value.message.contains("No pudimos leer esta imagen"))
        assertEquals(scope,vm.state.value.photos)
        compose.runOnUiThread {vm.clear()}
    }
}
