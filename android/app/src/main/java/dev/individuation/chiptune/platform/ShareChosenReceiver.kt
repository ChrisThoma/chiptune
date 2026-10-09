package dev.individuation.chiptune.platform

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent

/** Told by the system chooser which target the user picked; backing out sends nothing. */
class ShareChosenReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        @Suppress("DEPRECATION")
        val chosen = intent.getParcelableExtra<ComponentName>(Intent.EXTRA_CHOSEN_COMPONENT)
        listener?.invoke(chosen?.flattenToShortString() ?: "unknown")
    }

    companion object {
        /** Main thread only; set while a chooser is up. */
        @Volatile var listener: ((String) -> Unit)? = null
    }
}
