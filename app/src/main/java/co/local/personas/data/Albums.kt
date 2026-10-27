package co.local.personas.data

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlin.coroutines.coroutineContext

/** Bucket IDs alone are not unique across storage volumes. */
data class AlbumKey(val volume: String, val bucketId: String)
data class LocalAlbum(val key: AlbumKey, val name: String, val cover: Uri, val count: Int)
enum class LibraryAccess { NONE, LIMITED, FULL }

fun libraryAccess(context: Context): LibraryAccess {
    fun granted(permission: String) = context.checkSelfPermission(permission)==PackageManager.PERMISSION_GRANTED
    return when {
        Build.VERSION.SDK_INT>=33 && granted(Manifest.permission.READ_MEDIA_IMAGES) -> LibraryAccess.FULL
        Build.VERSION.SDK_INT>=34 && granted(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) -> LibraryAccess.LIMITED
        Build.VERSION.SDK_INT<=32 && granted(Manifest.permission.READ_EXTERNAL_STORAGE) -> LibraryAccess.FULL
        else -> LibraryAccess.NONE
    }
}
fun libraryPermissions(): Array<String> = when {
    Build.VERSION.SDK_INT>=34 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES,Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
    Build.VERSION.SDK_INT>=33 -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
    else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
}

interface AlbumSource {
    suspend fun albums(): List<LocalAlbum>
    suspend fun photos(key: AlbumKey): List<Uri>
}
class MediaStoreAlbums(private val context: Context): AlbumSource {
    override suspend fun albums(): List<LocalAlbum> = withContext(Dispatchers.IO) {
        val volumes=if(android.os.Build.VERSION.SDK_INT>=29) MediaStore.getExternalVolumeNames(context) else setOf("external")
        val grouped=linkedMapOf<AlbumKey,LocalAlbum>()
        for(volume in volumes.sorted()) {
            val collection=MediaStore.Images.Media.getContentUri(volume)
            val fields=arrayOf(MediaStore.Images.Media._ID,MediaStore.Images.Media.BUCKET_ID,MediaStore.Images.Media.BUCKET_DISPLAY_NAME)
            val cursor=context.contentResolver.query(collection,fields,null,null,"${MediaStore.Images.Media.DATE_ADDED} DESC, ${MediaStore.Images.Media._ID} DESC")
                ?: error("No se pudo consultar la galería")
            cursor.use {
                while(it.moveToNext()) {
                    coroutineContext.ensureActive()
                    if(it.isNull(1)) continue
                    val key=AlbumKey(volume,it.getString(1))
                    val existing=grouped[key]
                    grouped[key]=existing?.copy(count=existing.count+1) ?: LocalAlbum(key,it.getString(2)?.takeIf(String::isNotBlank) ?: "Sin nombre",ContentUris.withAppendedId(collection,it.getLong(0)),1)
                }
            }
        }
        grouped.values.toList()
    }
    override suspend fun photos(key: AlbumKey): List<Uri> = withContext(Dispatchers.IO) {
        val collection=MediaStore.Images.Media.getContentUri(key.volume)
        val result=mutableListOf<Uri>()
        val cursor=context.contentResolver.query(collection,arrayOf(MediaStore.Images.Media._ID),"${MediaStore.Images.Media.BUCKET_ID} = ?",arrayOf(key.bucketId),"${MediaStore.Images.Media.DATE_ADDED} DESC, ${MediaStore.Images.Media._ID} DESC")
            ?: error("No se pudo abrir el álbum")
        cursor.use {
            while(it.moveToNext()) {
                coroutineContext.ensureActive()
                result.add(ContentUris.withAppendedId(collection,it.getLong(0)))
            }
        }
        result
    }
}
