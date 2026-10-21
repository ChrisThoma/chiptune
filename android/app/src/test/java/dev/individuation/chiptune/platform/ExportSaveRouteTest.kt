package dev.individuation.chiptune.platform

import dev.individuation.chiptune.core.audio.ExportOptions
import org.junit.Assert.assertEquals
import org.junit.Test

/** Where "Save to device" puts an export: a video goes to the Gallery, as
 * iOS's Save Video goes to Photos; everything else through the picker. */
class ExportSaveRouteTest {
    @Test fun aVideoOnAndroidTenOrLaterGoesToTheGallery() {
        assertEquals(ExportSaveRoute.Route.GALLERY, ExportSaveRoute.route(ExportOptions.Format.VIDEO, sdk = 29))
        assertEquals(ExportSaveRoute.Route.GALLERY, ExportSaveRoute.route(ExportOptions.Format.VIDEO, sdk = 36))
    }

    /** Before Android 10 a shared Movies folder needs a storage permission
     * the app doesn't ask for, so the picker stays. */
    @Test fun aVideoBeforeAndroidTenUsesThePicker() {
        assertEquals(ExportSaveRoute.Route.PICKER, ExportSaveRoute.route(ExportOptions.Format.VIDEO, sdk = 26))
        assertEquals(ExportSaveRoute.Route.PICKER, ExportSaveRoute.route(ExportOptions.Format.VIDEO, sdk = 28))
    }

    @Test fun wavAndMidiAlwaysUseThePicker() {
        assertEquals(ExportSaveRoute.Route.PICKER, ExportSaveRoute.route(ExportOptions.Format.WAV, sdk = 36))
        assertEquals(ExportSaveRoute.Route.PICKER, ExportSaveRoute.route(ExportOptions.Format.MIDI, sdk = 36))
        assertEquals(ExportSaveRoute.Route.PICKER, ExportSaveRoute.route(null, sdk = 36))
    }

    @Test fun theGalleryFolderAndItsConfirmation() {
        assertEquals("Movies/Chiptune", ExportSaveRoute.GALLERY_FOLDER)
        assertEquals("Saved to Movies/Chiptune.", ExportSaveRoute.SAVED_TO_GALLERY)
    }
}
