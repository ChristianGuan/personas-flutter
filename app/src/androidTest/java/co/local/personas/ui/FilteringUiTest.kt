package co.local.personas.ui

import android.graphics.Bitmap
import android.net.Uri
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import co.local.personas.domain.Matching
import co.local.personas.ui.theme.PersonasTheme
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class FilteringUiTest {
    @get:Rule val compose=createAndroidComposeRule<MainActivity>()
    private fun fixture(): Pair<Uri,Uri> {
        val name=InstrumentationRegistry.getArguments().getString("filterFixtures")
        assumeTrue(name!=null)
        val dir=File(compose.activity.cacheDir,name!!)
        val row=JSONObject(File(dir,"regression.json").readText()).getJSONArray("cases").getJSONObject(0)
        return Uri.fromFile(File(dir,"s%02d-01.png".format(row.getInt("target")))) to
            Uri.fromFile(File(dir,"s%02d-%02d.png".format(row.getInt("otherSubject"),row.getInt("image"))))
    }
    private fun screenshot(name: String,dialog: Boolean=false) {
        File(compose.activity.cacheDir,"qa-$name.png").outputStream().use {
            (if(dialog) compose.onNode(isDialog()) else compose.onRoot()).captureToImage().asAndroidBitmap().compress(Bitmap.CompressFormat.PNG,100,it)
        }
    }
    @Test fun wrongPersonRequiresConfirmationAndExclusionSurvivesRepeat() {
        val (reference,other)=fixture()
        lateinit var vm: SearchViewModel
        compose.runOnUiThread {vm=ViewModelProvider(compose.activity)[SearchViewModel::class.java];vm.reference(reference)}
        compose.waitUntil(30_000) {!vm.state.value.busy}
        compose.runOnUiThread {vm.addCandidates(listOf(reference,other));vm.search()}
        compose.waitUntil(30_000) {!vm.state.value.busy}
        assertEquals(listOf(reference),vm.state.value.results)
        assertEquals(PhotoOutcome.REVIEW,vm.state.value.reviews.last().outcome)
        compose.runOnUiThread {vm.toggle(other);vm.toggleAll()}
        assertEquals(setOf(reference),vm.state.value.selected)
        assertEquals(listOf(reference.toString()),Matching.selectedForSharing(vm.state.value.results.map {it.toString()},setOf(reference.toString(),other.toString())))
        compose.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Por revisar (1)"))
        screenshot("strict-review")
        compose.onNodeWithContentDescription("Foto por revisar. Tocar para confirmar la persona").performScrollTo().performClick()
        compose.onNodeWithText("No es esta persona").performScrollTo().performClick()
        compose.onNodeWithText("Excluida por ti").assertExists()
        screenshot("strict-rejected",true)
        compose.onNodeWithText("‹ Volver a las fotos").performScrollTo().performClick()
        compose.runOnUiThread {vm.search()}
        compose.waitUntil(30_000) {!vm.state.value.busy}
        assertEquals(PhotoOutcome.USER_REJECTED,vm.state.value.reviews.last().outcome)
        assertEquals(listOf(reference),vm.state.value.results)
        compose.onNode(hasScrollToIndexAction()).performScrollToNode(hasText("Revisar fotos descartadas"))
        compose.onNodeWithText("Revisar fotos descartadas").performClick()
        compose.onNode(hasScrollToIndexAction()).performScrollToIndex(3)
        compose.onNodeWithContentDescription("Foto descartada. Tocar para revisar").performClick()
        compose.onNode(isDialog()).assertExists()
        compose.onNodeWithText("Sí, es esta persona").performScrollTo().performClick()
        assertEquals(PhotoOutcome.CONFIRMED,vm.state.value.reviews.last().outcome)
        assertEquals(listOf(reference,other),vm.state.value.results)
        compose.onNodeWithText("‹ Volver a las fotos").performScrollTo().performClick()
        compose.runOnUiThread {vm.reference(reference)} // Starts a new target; manual feedback is cleared.
        compose.waitUntil(30_000) {!vm.state.value.busy}
        compose.runOnUiThread {vm.search()}
        compose.waitUntil(30_000) {!vm.state.value.busy}
        assertEquals(PhotoOutcome.REVIEW,vm.state.value.reviews.last().outcome)
        compose.runOnUiThread {vm.clear()}
    }
    @Test fun reviewActionsRemainReachableAtLargeTextAndSmallSize() {
        val (_,other)=fixture()
        compose.runOnUiThread {compose.activity.setContent {
            val density=LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density,2f)) {
                PersonasTheme {Box(Modifier.requiredSize(320.dp,480.dp)) {
                    PhotoReviewDialog(other,SearchState(reviews=listOf(PhotoReview(other,PhotoOutcome.REVIEW))),{},{},modifier=Modifier.requiredSize(320.dp,480.dp))
                }}
            }
        }}
        if(InstrumentationRegistry.getArguments().getString("verifySystemLargeText")=="true") {
            assertTrue(compose.activity.resources.configuration.fontScale>=1.9f)
            val node=compose.onNodeWithText("Por revisar").performScrollTo()
            val layouts=mutableListOf<TextLayoutResult>()
            node.performSemanticsAction(SemanticsActions.GetTextLayoutResult) {it(layouts)}
            val layout=layouts.single()
            val bounds=node.fetchSemanticsNode().boundsInRoot
            val details=JSONObject().put("fontScale",layout.layoutInput.density.fontScale).put("density",layout.layoutInput.density.density)
                .put("layoutHeight",layout.size.height).put("boundsHeight",bounds.height)
            File(compose.activity.cacheDir,"qa-text-layout.json").writeText(details.toString())
            screenshot("strict-large-diagnostic",true)
            assertTrue("Dialog text density: $details",layout.layoutInput.density.fontScale>=1.9f)
            // Android 14+ scales larger sp sizes nonlinearly: 200% is not 2x line height.
            val unscaledLineHeight=layout.layoutInput.style.lineHeight.value*layout.layoutInput.density.density
            assertTrue("Dialog text must grow above its unscaled line height: $details",layout.size.height>unscaledLineHeight)
        }
        compose.onNodeWithText("Sí, es esta persona").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("No es esta persona").performScrollTo().assertIsDisplayed()
        screenshot("strict-large-text",true)
    }
}
