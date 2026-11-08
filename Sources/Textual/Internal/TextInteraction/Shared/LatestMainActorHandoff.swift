#if TEXTUAL_ENABLE_TEXT_SELECTION
  import Foundation

  /// Keeps only the newest value offered during a SwiftUI update frame and
  /// delivers it on the next main-queue turn. The callback is not owned by a
  /// temporary overlay view, so a redraw cannot cancel an admitted value.
  @MainActor
  final class LatestMainActorHandoff<Value> {
    typealias Enqueue = @MainActor (@escaping @MainActor () -> Void) -> Void

    private let enqueue: Enqueue
    private let deliver: @MainActor (Value) -> Void
    private var latest: Value?
    private var pending: Value?
    private var visible = false
    private var scheduled = false
    private var epoch: UInt64 = 0

    init(
      enqueue: @escaping Enqueue = { callback in
        DispatchQueue.main.async { callback() }
      },
      deliver: @escaping @MainActor (Value) -> Void
    ) {
      self.enqueue = enqueue
      self.deliver = deliver
    }

    func offer(_ value: Value) {
      latest = value
      pending = value
      scheduleIfNeeded()
    }

    func appear() {
      visible = true
      if pending == nil { pending = latest }
      scheduleIfNeeded()
    }

    func disappear() {
      visible = false
      pending = nil
      scheduled = false
      epoch &+= 1
    }

    private func scheduleIfNeeded() {
      guard visible, pending != nil, !scheduled else { return }
      scheduled = true
      let scheduledEpoch = epoch
      enqueue { [weak self] in
        self?.deliverIfCurrent(scheduledEpoch)
      }
    }

    private func deliverIfCurrent(_ scheduledEpoch: UInt64) {
      guard scheduledEpoch == epoch else { return }
      scheduled = false
      guard visible, let value = pending else { return }
      pending = nil
      deliver(value)
      scheduleIfNeeded()
    }
  }
#endif
