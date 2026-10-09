package dev.individuation.chiptune.ui.editor

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import dev.individuation.chiptune.ui.layout.PopoverPlacement
import dev.individuation.chiptune.ui.layout.SurfaceContainers
import dev.individuation.chiptune.ui.layout.SurfaceKind
import dev.individuation.chiptune.ui.theme.ChipColors
import kotlin.math.roundToInt

/*
 * Regular-width presentations: a popover anchored to the control that opened
 * it (iOS `.popover(attachmentAnchor: .rect(.bounds), arrowEdge: .top)`,
 * drawn as an arrowless card), and the centred library dialog.
 */

/** What a popover hangs off. */
sealed interface PopoverAnchor {
    /** A track header, by index (as [Presented.InstrumentEditor] holds it). */
    data class Track(val index: Int) : PopoverAnchor

    /** ARR in the transport. */
    data object Arrangement : PopoverAnchor

    /** The \u2022\u2022\u2022 song menu button: Export and the key list. */
    data object Menu : PopoverAnchor
}

/** Where the anchors are, in window pixels, and the editor's safe area. */
@Stable
class PopoverAnchors {
    private val rects = mutableStateMapOf<PopoverAnchor, Rect>()

    /** The editor inside the system bars, in window pixels. */
    var window by mutableStateOf<Rect?>(null)
        internal set

    operator fun get(anchor: PopoverAnchor): Rect? = rects[anchor]

    internal fun set(anchor: PopoverAnchor, rect: Rect) {
        if (rects[anchor] != rect) rects[anchor] = rect
    }
}

/** Records this view as [anchor]'s bounds. */
fun Modifier.popoverAnchor(anchors: PopoverAnchors, anchor: PopoverAnchor): Modifier =
    onGloballyPositioned { anchors.set(anchor, it.boundsInWindow()) }

private fun Rect.bounds() = PopoverPlacement.Bounds(left.toDouble(), top.toDouble(), right.toDouble(), bottom.toDouble())

private val PopoverShape = RoundedCornerShape(14.dp)

/** Room around a popover card for its shadow. */
private val ShadowRoom = 20.dp

/**
 * A dark card anchored under [anchor] (or over it, when there's more room
 * there), sized by [kind]'s popover frame. Outside taps, Back and Escape call
 * [onDismiss]; so does Ctrl+.
 */
@Composable
fun ChipPopover(
    editor: Editor,
    anchor: PopoverAnchor,
    kind: SurfaceKind,
    onDismiss: () -> Unit,
    content: @Composable () -> Unit,
) {
    val anchors = editor.presentation.anchors
    val density = LocalDensity.current
    val window = anchors.window ?: return
    val anchorRect = anchors[anchor]
    val spec = SurfaceContainers.popover(kind, density.fontScale.toDouble())
    val px = density.density.toDouble()
    val framePx = spec.frame.copy(
        minWidth = spec.frame.minWidth * px,
        idealWidth = spec.frame.idealWidth * px,
        minHeight = spec.frame.minHeight * px,
        idealHeight = spec.frame.idealHeight * px,
    )
    val margin = PopoverPlacement.MARGIN * px
    val gap = PopoverPlacement.GAP * px
    val shadowPx = ShadowRoom.value * px
    val windowBounds = window.bounds()
    val anchorBounds = anchorRect?.bounds()
    val placement = PopoverPlacement.place(anchorBounds, framePx, spec.wrapsHeight, windowBounds, margin, gap)
    val provider = remember(anchorBounds, windowBounds, placement.below, spec.wrapsHeight) {
        object : PopupPositionProvider {
            override fun calculatePosition(
                anchorBounds: IntRect,
                windowSize: IntSize,
                layoutDirection: LayoutDirection,
                popupContentSize: IntSize,
            ): IntOffset {
                // The card sits [ShadowRoom] inside the window the popup
                // measures, so its shadow isn't cut off at the window edge.
                val (x, y) = PopoverPlacement.origin(
                    anchorRect?.bounds(),
                    popupContentSize.width - 2 * shadowPx,
                    popupContentSize.height - 2 * shadowPx,
                    windowBounds,
                    margin,
                    gap,
                    if (spec.wrapsHeight) null else placement.below,
                )
                return IntOffset((x - shadowPx).roundToInt(), (y - shadowPx).roundToInt())
            }
        }
    }
    val width = (placement.width / px).toFloat().dp
    val height = (placement.height / px).toFloat().dp
    Popup(
        popupPositionProvider = provider,
        onDismissRequest = onDismiss,
        properties = PopupProperties(focusable = true, dismissOnBackPress = true, dismissOnClickOutside = true),
    ) {
        Box(
            Modifier
                .padding(ShadowRoom)
                .width(width)
                .then(if (spec.wrapsHeight) Modifier.heightIn(max = height) else Modifier.height(height))
                .shadow(18.dp, PopoverShape, ambientColor = Color.Black, spotColor = Color.Black)
                .clip(PopoverShape)
                .background(FormColors.sheet)
                .border(0.5.dp, ChipColors.grid, PopoverShape)
                .presentedKeys(onDismiss),
        ) {
            content()
        }
    }
}

/** The library on a tablet: a centred card, at most 640 wide (iOS's form
 * sheet). */
@Composable
fun ChipCenteredDialog(onDismiss: () -> Unit, content: @Composable () -> Unit) {
    val density = LocalDensity.current
    val window = LocalWindowInfo.current.containerSize
    val width = SurfaceContainers.libraryDialogWidth(window.width / density.density.toDouble())
    val height = SurfaceContainers.libraryDialogHeight(window.height / density.density.toDouble())
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        PresentedWindowKeys(onDismiss)
        Box(
            Modifier
                .width(width.toFloat().dp)
                .height(height.toFloat().dp)
                .clip(PopoverShape)
                .background(FormColors.sheet),
        ) {
            content()
        }
    }
}
