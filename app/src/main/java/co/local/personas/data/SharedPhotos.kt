package co.local.personas.data

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import androidx.core.content.IntentCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

/** Only explicit, read-only image grants. Never resolve a sender's file paths. */
suspend fun sharedImageUris(intent: Intent, resolver: ContentResolver): List<Uri> = withContext(Dispatchers.IO) {
    if(intent.action !in listOf(Intent.ACTION_SEND,Intent.ACTION_SEND_MULTIPLE) || intent.type?.startsWith("image/")!=true) return@withContext emptyList()
    val offered=try {
        buildList {
            if(intent.action==Intent.ACTION_SEND) IntentCompat.getParcelableExtra(intent,Intent.EXTRA_STREAM,Uri::class.java)?.let(::add)
            else IntentCompat.getParcelableArrayListExtra(intent,Intent.EXTRA_STREAM,Uri::class.java)?.let(::addAll)
            intent.clipData?.let {clip -> repeat(clip.itemCount) {clip.getItemAt(it).uri?.let(::add)}}
        }.distinct()
    } catch(_: RuntimeException) {emptyList()}
    offered.filter {uri ->
        ensureActive()
        if(uri.scheme!=ContentResolver.SCHEME_CONTENT || uri.authority.isNullOrBlank()) false
        else try {resolver.getType(uri)?.startsWith("image/")!=false} catch(_: Exception) {false}
    }
}
