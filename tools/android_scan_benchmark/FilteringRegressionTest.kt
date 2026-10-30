package co.local.personas.flutter
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import co.local.personas.data.FilteringTest
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class FilteringRegressionTest {
 @Test fun publicCountsAndCacheContractsRemainValid() {
  val inst=InstrumentationRegistry.getInstrumentation();val dir=File(inst.targetContext.cacheDir,"qa-filter").also {it.mkdirs()}
  for(name in inst.context.assets.list("qa-filter")!!) {
   inst.context.assets.open("qa-filter/$name").use {input->File(dir,name).outputStream().use {input.copyTo(it)}}
  }
  FilteringTest().apply {
   calibrationAndHeldOutSubjectsKeepAutomaticAndReviewCountsSeparate()
   encodedCacheSkipsDecodeButNeverTrustsUriOrIncompleteEntries()
   byteSnapshotsPreserveExifAndOversizeFallback()
   encodedAliasesNeverFinalizePartiallyComputedFacesForANewPerson()
  }
  val report=File(inst.targetContext.cacheDir,"qa-filter-metrics.json").readText()
  inst.sendStatus(0,android.os.Bundle().apply {putString("metrics",report)})
 }
}
