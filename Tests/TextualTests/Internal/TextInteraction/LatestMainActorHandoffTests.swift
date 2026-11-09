#if TEXTUAL_ENABLE_TEXT_SELECTION && !targetEnvironment(macCatalyst)
  import Testing

  @testable import Textual

  @MainActor
  private final class HandoffBox {
    var value: LatestMainActorHandoff<Int>?
  }

  @MainActor
  struct LatestMainActorHandoffTests {
    @Test
    func latestOfferWinsOneQueuedDelivery() {
      var queued: [@MainActor () -> Void] = []
      var delivered: [Int] = []
      let handoff = LatestMainActorHandoff<Int>(
        enqueue: { queued.append($0) },
        deliver: { delivered.append($0) }
      )

      handoff.offer(1)
      #expect(queued.isEmpty)
      handoff.appear()
      handoff.offer(2)
      handoff.offer(3)
      #expect(queued.count == 1)
      queued.removeFirst()()
      #expect(delivered == [3])
      #expect(queued.isEmpty)
    }

    @Test
    func disappearanceInvalidatesAnOlderQueuedDelivery() {
      var queued: [@MainActor () -> Void] = []
      var delivered: [Int] = []
      let handoff = LatestMainActorHandoff<Int>(
        enqueue: { queued.append($0) },
        deliver: { delivered.append($0) }
      )

      handoff.offer(1)
      handoff.appear()
      handoff.disappear()
      handoff.offer(2)
      handoff.appear()
      #expect(queued.count == 2)
      queued.removeFirst()()
      #expect(delivered.isEmpty)
      queued.removeFirst()()
      #expect(delivered == [2])
    }

    @Test
    func reappearanceReplaysOnlyTheLatestHiddenOffer() {
      var queued: [@MainActor () -> Void] = []
      var delivered: [Int] = []
      let handoff = LatestMainActorHandoff<Int>(
        enqueue: { queued.append($0) },
        deliver: { delivered.append($0) }
      )

      handoff.offer(1)
      handoff.appear()
      queued.removeFirst()()
      handoff.disappear()
      handoff.offer(2)
      handoff.offer(3)
      handoff.appear()
      #expect(queued.count == 1)
      queued.removeFirst()()
      #expect(delivered == [1, 3])
    }

    @Test
    func aReentrantNewOfferGetsItsOwnDelivery() {
      var queued: [@MainActor () -> Void] = []
      var delivered: [Int] = []
      let box = HandoffBox()
      box.value = LatestMainActorHandoff<Int>(
        enqueue: { queued.append($0) },
        deliver: { value in
          delivered.append(value)
          if value == 1 { box.value?.offer(2) }
        }
      )

      box.value?.offer(1)
      box.value?.appear()
      #expect(queued.count == 1)
      queued.removeFirst()()
      #expect(delivered == [1])
      #expect(queued.count == 1)
      queued.removeFirst()()
      #expect(delivered == [1, 2])
    }
  }
#endif
