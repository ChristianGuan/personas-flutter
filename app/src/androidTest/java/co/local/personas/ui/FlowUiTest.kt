package co.local.personas.ui

import android.content.ContentValues
import android.content.res.Configuration
import android.provider.MediaStore
import androidx.test.platform.app.InstrumentationRegistry
import co.local.personas.data.MediaStoreAlbums
import kotlinx.coroutines.runBlocking
import org.junit.Assume.assumeTrue
import java.util.UUID
import android.graphics.Bitmap
import android.net.Uri
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Surface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import co.local.personas.data.LibraryAccess
import co.local.personas.ui.theme.PersonasTheme
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Empty-state fixtures live only in tests; no recognizer doubles or sample matches. */
@RunWith(AndroidJUnit4::class)
class FlowUiTest {
    @get:Rule val compose=createAndroidComposeRule<MainActivity>()

    private fun screenshot(name: String) {
        compose.waitForIdle()
        val file=File(compose.activity.cacheDir,"qa-$name.png")
        val node=if(name=="real-full-photo") compose.onNode(isDialog()) else compose.onRoot()
        file.outputStream().use {node.captureToImage().asAndroidBitmap().compress(Bitmap.CompressFormat.PNG,100,it)}
    }

    @Test fun homeAndReferenceNavigation() {
        compose.onNodeWithText("Encuentra a tu gente").assertIsDisplayed()
        screenshot("home")
        compose.onNodeWithText("Nueva búsqueda").performClick()
        compose.onNodeWithText("Elegir álbum").assertIsNotEnabled()
        compose.onNodeWithText("Elegir foto de referencia").performScrollTo().assertIsDisplayed()
        screenshot("reference-empty")
    }

    @Test fun smallScreenAt200PercentTextKeepsActionReachable() {
        compose.runOnUiThread {
            compose.activity.setContent {
                val density=LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density,2f)) {
                    PersonasTheme {Box(Modifier.requiredSize(320.dp,480.dp)) {SearchScreen()}}
                }
            }
        }
        compose.onNodeWithText("Nueva búsqueda").assertIsDisplayed()
        screenshot("small-large-home")
        compose.onNodeWithText("Nueva búsqueda").performClick()
        compose.onNodeWithText("Elegir álbum").assertIsDisplayed().assertIsNotEnabled()
        // Lazy grids do not compose items outside the viewport. Scroll the grid first.
        compose.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Elegir foto de referencia"))
        compose.onNodeWithText("Elegir foto de referencia").assertIsDisplayed()
        screenshot("small-large-text")
    }

    @Test fun referenceWithoutFacesUsesRealPipelineAndExplainsNextAction() {
        val blank=File(compose.activity.cacheDir,"qa-blank.png")
        val image=Bitmap.createBitmap(512,512,Bitmap.Config.ARGB_8888)
        image.eraseColor(android.graphics.Color.LTGRAY)
        blank.outputStream().use {image.compress(Bitmap.CompressFormat.PNG,100,it)}
        image.recycle()
        lateinit var vm: SearchViewModel
        compose.runOnUiThread {
            vm=ViewModelProvider(compose.activity)[SearchViewModel::class.java]
            vm.reference(Uri.fromFile(blank))
        }
        compose.waitUntil(30_000) {!vm.state.value.busy}
        assertNotNull("Real decoding and inference must finish, not be replaced by an error fixture",vm.state.value.reference)
        assertTrue(vm.state.value.faces.isEmpty())
        compose.onNodeWithText("No encontramos un rostro utilizable").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Elegir álbum").assertIsNotEnabled()
        screenshot("no-face")
        blank.delete()
    }

    private fun showState(state: SearchState,onGallery: ()->Unit={}) {
        compose.runOnUiThread {
            compose.activity.setContent {PersonasTheme {Surface(Modifier.fillMaxSize()) {
                StepScreen(state.step,state,onReference={},onChoose={},onAlbumsPermission={},onRefresh={},onSettings={},
                    onSelectAlbum={},onGallery=onGallery,onFiles={},onClearCandidates={},onPreview={},onToggle={},onToggleAll={},
                    onReferenceStep={},onAlbumStep={},onRetry={},onClear={},shareError=false)
            }}}
        }
    }
    @Test fun deniedAlbumsKeepIndividualSelectionAvailable() {
        var opened=false
        showState(SearchState(step=SearchStep.ALBUMS,access=LibraryAccess.NONE),onGallery={opened=true})
        compose.onNodeWithText("Elegir fotos").performScrollTo().performClick()
        assertTrue(opened)
        compose.onNodeWithText("Acceso a álbumes desactivado").performScrollTo().assertIsDisplayed()
        screenshot("albums-denied")
    }
    @Test fun emptyLimitedLibraryHasExplanationAndNextAction() {
        showState(SearchState(step=SearchStep.ALBUMS,access=LibraryAccess.LIMITED))
        compose.onNodeWithText("No hay álbumes accesibles").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Revisar acceso").performScrollTo().assertHasClickAction()
        screenshot("albums-empty")
    }
    @Test fun noResultsSuggestsChangingReference() {
        showState(SearchState(step=SearchStep.RESULTS))
        compose.onNodeWithText("No encontramos coincidencias").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Cambiar referencia").performScrollTo().assertHasClickAction()
        screenshot("no-results")
    }
    @Test fun cancellationIsExplicitAndOffersRetry() {
        showState(SearchState(step=SearchStep.RESULTS,cancelled=true))
        compose.onNodeWithText("Búsqueda cancelada").assertIsDisplayed()
        compose.onNodeWithText("Volver a buscar").performScrollTo().assertHasClickAction()
        screenshot("cancelled")
    }
    @Test fun complementaryReferenceRecoversDistinctPhotosAndRejectsNegatives() {
        val dirName=InstrumentationRegistry.getArguments().getString("identityFixtures")
        assumeTrue("Supply optional pose/illumination fixtures outside the repository",dirName!=null)
        val dir=File(compose.activity.cacheDir,dirName!!)
        val positives=dir.listFiles()!!.filter {it.name.startsWith("positive-")}.sortedBy {it.name}.map {Uri.fromFile(it)}
        val negatives=dir.listFiles()!!.filter {it.name.startsWith("negative-")}.sortedBy {it.name}.map {Uri.fromFile(it)}
        assertEquals(11,positives.size);assertEquals(2,negatives.size)
        val scope=positives+negatives
        lateinit var vm: SearchViewModel
        compose.runOnUiThread {
            vm=ViewModelProvider(compose.activity)[SearchViewModel::class.java]
            vm.reference(Uri.fromFile(File(dir,"ref-side.jpg")))
        }
        compose.waitUntil(30_000) {!vm.state.value.busy}
        assertNotNull(vm.state.value.chosen)
        compose.runOnUiThread {vm.addCandidates(scope);vm.search()}
        compose.waitUntil(60_000) {!vm.state.value.busy}
        val before=vm.state.value.results.toSet()
        assertTrue("The regression fixture must expose missed positives with a single side reference",before.count {it in positives}<positives.size)
        assertFalse(before.any {it in negatives})
        compose.runOnUiThread {vm.reference(Uri.fromFile(File(dir,"ref-front.jpg")),append=true)}
        compose.waitUntil(30_000) {!vm.state.value.busy}
        assertEquals(1,vm.state.value.examples.size)
        assertEquals(scope,vm.state.value.photos)
        compose.onNodeWithText("Buscar de nuevo en ${scope.size} fotos").assertIsEnabled()
        screenshot("identity-references")
        compose.onNodeWithText("Buscar de nuevo en ${scope.size} fotos").performClick()
        compose.waitUntil(60_000) {!vm.state.value.busy}
        val after=vm.state.value.results.toSet()
        val review=vm.state.value.reviews.filter {it.outcome==PhotoOutcome.REVIEW}.map {it.uri}.toSet()
        assertEquals("Stricter auto acceptance must retain all previous positives in results or explicit review",positives.toSet(),after+review)
        assertFalse(review.any {it in negatives})
        assertFalse(after.any {it in negatives})
        assertTrue(after.size>before.size)
        val metrics=org.json.JSONObject().apply {
            put("positivePhotos",positives.size);put("negativePhotos",negatives.size)
            put("singleReferenceTruePositives",before.count {it in positives});put("multipleReferenceTruePositives",after.count {it in positives});put("multipleReferenceReviewPositives",review.count {it in positives})
            put("singleReferenceFalsePositives",before.count {it in negatives});put("multipleReferenceFalsePositives",after.count {it in negatives})
            put("lastProcessed",vm.state.value.processed);put("lastSkipped",vm.state.value.skipped);put("lastDurationMs",vm.state.value.elapsedMs)
            put("api",android.os.Build.VERSION.SDK_INT)
        }
        File(compose.activity.cacheDir,"qa-identity-metrics.json").writeText(metrics.toString())
        screenshot("identity-results")
        compose.runOnUiThread {vm.clear()}
    }

    @Test fun discardedPhotoCanBeConfirmedAsExtraReferenceWithoutChangingScope() {
        val dirName=InstrumentationRegistry.getArguments().getString("identityFixtures")
        assumeTrue(dirName!=null)
        val dir=File(compose.activity.cacheDir,dirName!!)
        val candidate=Uri.fromFile(File(dir,"positive-00.jpg"))
        lateinit var vm: SearchViewModel
        compose.runOnUiThread {
            vm=ViewModelProvider(compose.activity)[SearchViewModel::class.java]
            vm.reference(Uri.fromFile(File(dir,"ref-side.jpg")))
        }
        compose.waitUntil(30_000) {!vm.state.value.busy}
        compose.runOnUiThread {vm.addCandidates(listOf(candidate));vm.search()}
        compose.waitUntil(30_000) {!vm.state.value.busy}
        assertTrue(vm.state.value.results.isEmpty())
        assertEquals(PhotoOutcome.BELOW_THRESHOLD,vm.state.value.reviews.single().outcome)
        compose.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Revisar fotos descartadas"))
        compose.onNodeWithText("Revisar fotos descartadas").performClick()
        compose.onNode(hasScrollToIndexAction()).performScrollToIndex(2)
        compose.waitUntil(10_000) {compose.onAllNodesWithContentDescription("Foto descartada. Tocar para revisar").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithContentDescription("Foto descartada. Tocar para revisar").performScrollTo().performClick()
        compose.onNodeWithText("Usar como otra referencia").assertIsDisplayed().performClick()
        compose.waitUntil(30_000) {!vm.state.value.busy}
        assertEquals(SearchStep.REFERENCE,vm.state.value.step)
        assertEquals(listOf(candidate),vm.state.value.photos)
        assertEquals(1,vm.state.value.examples.size)
        // The user confirms the selected face by starting this new search.
        compose.onNodeWithText("Buscar de nuevo en 1 foto").assertIsEnabled().performClick()
        compose.waitUntil(30_000) {!vm.state.value.busy}
        assertEquals(listOf(candidate),vm.state.value.results)
        screenshot("discarded-recovery")
        compose.runOnUiThread {vm.clear()}
    }

    @Test fun failedCancelledAndRemovedExtraReferencesPreserveValidState() {
        val sampleName=InstrumentationRegistry.getArguments().getString("faceFixture")
        assumeTrue(sampleName!=null)
        val uri=Uri.fromFile(File(compose.activity.cacheDir,sampleName!!))
        lateinit var vm: SearchViewModel
        compose.runOnUiThread {vm=ViewModelProvider(compose.activity)[SearchViewModel::class.java];vm.reference(uri)}
        compose.waitUntil(30_000) {!vm.state.value.busy}
        compose.runOnUiThread {vm.reference(uri,append=true)}
        compose.waitUntil(30_000) {!vm.state.value.busy}
        assertEquals(1,vm.state.value.examples.size)
        val valid=vm.state.value.reference
        compose.runOnUiThread {vm.reference(Uri.fromFile(File(compose.activity.cacheDir,"qa-missing.jpg")),append=true)}
        compose.waitUntil(10_000) {!vm.state.value.busy}
        assertSame(valid,vm.state.value.reference);assertEquals(1,vm.state.value.examples.size)
        val blank=File(compose.activity.cacheDir,"qa-empty-extra.png")
        val bitmap=Bitmap.createBitmap(256,256,Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(android.graphics.Color.GRAY)
        blank.outputStream().use {bitmap.compress(Bitmap.CompressFormat.PNG,100,it)};bitmap.recycle()
        try {
            compose.runOnUiThread {vm.reference(Uri.fromFile(blank),append=true)}
            compose.waitUntil(30_000) {!vm.state.value.busy}
            assertSame(valid,vm.state.value.reference);assertEquals(1,vm.state.value.examples.size)
            compose.runOnUiThread {vm.reference(uri,append=true);vm.cancel()}
            compose.waitUntil(10_000) {!vm.state.value.busy}
            assertSame(valid,vm.state.value.reference);assertEquals(1,vm.state.value.examples.size)
            compose.runOnUiThread {vm.removeExample(0)}
            assertEquals(0,vm.state.value.examples.size);assertSame(valid,vm.state.value.reference)
            compose.runOnUiThread {vm.reference(uri,append=true)}
            compose.waitUntil(30_000) {!vm.state.value.busy}
            assertEquals(1,vm.state.value.examples.size)
            compose.runOnUiThread {vm.reference(uri,append=false)}
            compose.waitUntil(30_000) {!vm.state.value.busy}
            assertEquals(0,vm.state.value.examples.size)
        } finally {blank.delete()}
    }

    @Test fun nineRealDetectedFacesCanBeChosenByThumbnailAndImage() {
        val sampleName=InstrumentationRegistry.getArguments().getString("faceFixture")
        assumeTrue("Supply the optional official sample for group-face QA",sampleName!=null)
        val sample=android.graphics.BitmapFactory.decodeFile(File(compose.activity.cacheDir,sampleName!!).absolutePath)
        val group=Bitmap.createBitmap(sample.width*3,sample.height*3,Bitmap.Config.ARGB_8888)
        val canvas=android.graphics.Canvas(group)
        for(y in 0..2) for(x in 0..2) canvas.drawBitmap(sample,(x*sample.width).toFloat(),(y*sample.height).toFloat(),null)
        sample.recycle()
        val file=File(compose.activity.cacheDir,"qa-group.png")
        file.outputStream().use {group.compress(Bitmap.CompressFormat.PNG,100,it)}
        group.recycle()
        lateinit var vm: SearchViewModel
        try {
            compose.runOnUiThread {
                vm=ViewModelProvider(compose.activity)[SearchViewModel::class.java]
                vm.reference(Uri.fromFile(file))
            }
            compose.waitUntil(45_000) {!vm.state.value.busy}
            assertEquals("Both native scales must merge into nine distinct faces",9,vm.state.value.faces.size)
            for(number in listOf(4,9)) {
                compose.onNode(hasScrollToIndexAction()).performScrollToNode(hasContentDescription("Elegir rostro $number"))
                compose.onNodeWithContentDescription("Elegir rostro $number").performClick().assertIsSelected()
                compose.runOnIdle {assertEquals(number-1,vm.state.value.chosen)}
            }
            screenshot("nine-face-choices")
            val imageDescription="Referencia con 9 rostros. También puedes elegir con los botones de rostro."
            compose.onNode(hasScrollToIndexAction()).performScrollToNode(hasContentDescription(imageDescription))
            val bounds=vm.state.value.faces[6].bounds
            val bitmap=vm.state.value.reference!!
            compose.onNodeWithContentDescription(imageDescription).performTouchInput {
                val factor=minOf(width.toFloat()/bitmap.width,height.toFloat()/bitmap.height)
                click(androidx.compose.ui.geometry.Offset((width-bitmap.width*factor)/2+bounds.centerX()*factor,(height-bitmap.height*factor)/2+bounds.centerY()*factor))
            }
            compose.runOnIdle {assertEquals(6,vm.state.value.chosen)}
            compose.onNodeWithText("Elegir álbum").assertIsEnabled()
            screenshot("nine-face-reference")
        } finally {file.delete()}
    }
    @Test fun realAlbumScopeAndRecognitionStayIsolated() {
        // Optional official sample is supplied privately by the operator, never shipped in the app.
        val sampleName=InstrumentationRegistry.getArguments().getString("faceFixture")
        assumeTrue("Supply a public sample in target cache to run real-face QA",sampleName!=null)
        val sample=File(compose.activity.cacheDir,sampleName!!)
        assertTrue(sample.isFile)
        val resolver=compose.activity.contentResolver
        val inserted=mutableListOf<Uri>()
        val batch=UUID.randomUUID().toString()
        try {
            for(parent in listOf("A","B")) {
                val values=ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME,"personas-qa.jpg")
                    put(MediaStore.Images.Media.MIME_TYPE,"image/jpeg")
                    put(MediaStore.Images.Media.RELATIVE_PATH,"Pictures/PersonasQA-$batch/$parent/Same")
                    put(MediaStore.Images.Media.IS_PENDING,1)
                }
                val uri=resolver.insert(MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),values)!!
                inserted.add(uri)
                resolver.openOutputStream(uri)!!.use {out -> sample.inputStream().use {it.copyTo(out)}}
                resolver.update(uri,ContentValues().apply {put(MediaStore.Images.Media.IS_PENDING,0)},null,null)
            }
            val source=MediaStoreAlbums(compose.activity)
            val catalog=runBlocking {source.albums()}
            val albums=inserted.map {uri -> catalog.first {it.cover==uri}}
            assertEquals("Same",albums[0].name)
            assertEquals(albums[0].name,albums[1].name)
            assertNotEquals(albums[0].key,albums[1].key)
            assertEquals(listOf(inserted[0]),runBlocking {source.photos(albums[0].key)})
            assertEquals(listOf(inserted[1]),runBlocking {source.photos(albums[1].key)})
            lateinit var vm: SearchViewModel
            compose.runOnUiThread {
                vm=ViewModelProvider(compose.activity)[SearchViewModel::class.java]
                vm.reference(Uri.fromFile(sample))
            }
            compose.waitUntil(30_000) {!vm.state.value.busy}
            assertNotNull(vm.state.value.chosen)
            screenshot("real-reference")
            compose.runOnUiThread {vm.navigate(SearchStep.ALBUMS)}
            compose.waitUntil(30_000) {!vm.state.value.libraryLoading}
            compose.waitForIdle()
            // The UI only enables album selection after the real catalog query completes.
            compose.runOnUiThread {vm.selectAlbum(albums[0])}
            compose.waitUntil(10_000) {!vm.state.value.libraryLoading}
            assertEquals(listOf(inserted[0]),vm.state.value.photos)
            // Cancelling a cloud picker/settings trip must retain an unchanged authorized album.
            compose.runOnUiThread {vm.refreshAlbums()}
            compose.waitUntil(10_000) {!vm.state.value.libraryLoading}
            assertEquals(albums[0].key,vm.state.value.selectedAlbum?.key)
            assertEquals(listOf(inserted[0]),vm.state.value.photos)
            compose.onNodeWithText("Buscar coincidencias").assertIsEnabled().performClick()
            compose.waitUntil(30_000) {!vm.state.value.busy}
            assertEquals(SearchStep.RESULTS,vm.state.value.step)
            // Both files contain the same face. Only the chosen bucket may appear.
            assertEquals(listOf(inserted[0]),vm.state.value.results)
            assertEquals(1,vm.state.value.processed)
            compose.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Seleccionar todas"))
            compose.onNodeWithText("Seleccionar todas").performClick()
            compose.onNodeWithText("Compartir selección").assertIsEnabled()
            assertEquals(setOf(inserted[0]),vm.state.value.selected)
            screenshot("real-results")
            compose.onNode(hasScrollToIndexAction()).performScrollToNode(hasContentDescription("Coincidencia. Tocar para ver imagen completa"))
            compose.onNodeWithContentDescription("Coincidencia. Tocar para ver imagen completa").performClick()
            compose.waitUntil(10_000) {compose.onAllNodesWithContentDescription("Imagen completa para revisar").fetchSemanticsNodes().isNotEmpty()}
            compose.onNodeWithText("✓ Seleccionada · Quitar").assertIsDisplayed()
            screenshot("real-full-photo")
            compose.onNodeWithText("‹ Volver a las fotos").performClick()
            compose.runOnUiThread {vm.clear()}
        } finally {
            // Delete only rows created by this test; never touch existing gallery entries.
            inserted.forEach {resolver.delete(it,null,null)}
        }
    }
    @Test fun darkThemeKeepsNavigationAndEmptyActionAvailable() {
        compose.runOnUiThread {
            compose.activity.setContent {
                val dark=Configuration(LocalConfiguration.current).apply {
                    uiMode=(uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or Configuration.UI_MODE_NIGHT_YES
                }
                CompositionLocalProvider(LocalConfiguration provides dark) {PersonasTheme {SearchScreen()}}
            }
        }
        compose.onNodeWithText("Nueva búsqueda").assertIsDisplayed()
        screenshot("dark-home")
        compose.onNodeWithText("Nueva búsqueda").performClick()
        compose.onNodeWithText("Elegir álbum").assertIsNotEnabled()
        screenshot("dark-reference")
    }
    @Test fun unreadableImagesAreReportedSeparatelyFromNoMatch() {
        showState(SearchState(step=SearchStep.RESULTS,skipped=1))
        compose.onNodeWithText("1 foto no se pudo analizar").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Revisar el conjunto").performScrollTo().assertHasClickAction()
        screenshot("partial-error")
    }
}
