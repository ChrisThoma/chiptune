import Foundation

/// The undo/redo stacks and their folding rules, factored out of `Studio` so
/// the coalescing behaviour is readable on its own. Knows nothing about songs:
/// `State` is whatever the owner wants restored, `Run` names a batch of edits
/// that collapses to one step (see `Studio.CheckpointRun`).
///
/// A plain struct stored as an *observed* property of its owner — not a class,
/// and not `@ObservationIgnored` — so `canUndo`/`canRedo` keep invalidating
/// the toolbar buttons exactly as the inline stacks did.
struct UndoHistory<State, Run: Equatable, Kind: Equatable> {
    private var undoStack: [State] = []
    private var redoStack: [State] = []
    private var lastCheckpoint: Date?
    /// The run the last checkpoint belonged to, for run-coalesced edits.
    private var lastRun: Run?
    /// The operation kind the last checkpoint belonged to, so time-coalescing
    /// only folds edits of the same kind — a tempo tap followed by a note
    /// toggle inside the window must still be two undo steps.
    private var lastKind: Kind?

    /// Edits closer together than this fold into one undo step, so painting a
    /// run of cells is one undo rather than sixteen.
    var coalescingWindow: TimeInterval = 1.0
    /// Deep enough to cover a working session, shallow enough that the stack
    /// isn't holding an unbounded number of states.
    var limit = 50

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Records `state` unless it folds into the previous checkpoint.
    ///
    /// - Parameters:
    ///   - coalescing: fold when the previous checkpoint was inside
    ///     `coalescingWindow` *and* tagged with the same `kind`. For
    ///     continuous gestures — painting cells, holding a stepper. Folding
    ///     rolls the window forward, so a continuous stroke stays one step
    ///     however long it goes on.
    ///   - kind: identifies the operation for `coalescing`, so unrelated
    ///     edits that merely land inside the same window (a tempo tap, then
    ///     a note toggle) don't fold into one undo step.
    ///   - run: fold when the previous checkpoint belonged to the same named
    ///     run, however long ago it was. For edits with no rhythm to time out
    ///     on. Any record without a `run` ends the run, so a different kind of
    ///     edit always starts a new undo step.
    mutating func record(_ state: @autoclosure () -> State,
                         coalescing: Bool = false,
                         kind: Kind? = nil,
                         run: Run? = nil) {
        let now = Date()
        if run != nil, run == lastRun, !undoStack.isEmpty {
            lastCheckpoint = now
            return
        }
        if coalescing, run == nil, !undoStack.isEmpty, let last = lastCheckpoint,
           kind == lastKind, now.timeIntervalSince(last) < coalescingWindow {
            lastCheckpoint = now
            return
        }
        undoStack.append(state())
        if undoStack.count > limit { undoStack.removeFirst() }
        // A new edit is a new branch; whatever was undone past is gone.
        redoStack.removeAll()
        lastCheckpoint = now
        lastRun = run
        lastKind = kind
    }

    /// Steps back, pushing `current` where redo will find it. Returns the
    /// state to restore, or nil when there is nothing to undo.
    mutating func undo(current: @autoclosure () -> State) -> State? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current())
        return previous
    }

    mutating func redo(current: @autoclosure () -> State) -> State? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current())
        return next
    }

    /// The next edit starts a fresh step rather than folding itself into
    /// whatever was just restored.
    mutating func closeFolding() {
        lastCheckpoint = nil
        lastRun = nil
        lastKind = nil
    }

    /// Ends the current named run, so the next edit of that kind starts a
    /// fresh undo step.
    mutating func endRun() {
        lastRun = nil
    }

    /// Drops the redo branch — for when a state redo would reinstate was
    /// rejected rather than undone.
    mutating func dropRedo() {
        redoStack.removeAll()
    }

    mutating func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
        closeFolding()
    }

    /// Whether the last checkpoint opened `run` and is still on the stack.
    func lastRunIs(_ run: Run) -> Bool {
        lastRun == run && !undoStack.isEmpty
    }
}
