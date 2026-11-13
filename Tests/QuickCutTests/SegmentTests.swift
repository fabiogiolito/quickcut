import Testing
@testable import QuickCut

@Test func splitDeleteMove() {
    var segs = [Segment(start: 0, end: 10)]
    var ok = segs.split(at: 4)
    #expect(ok)
    #expect(segs.map(\.start) == [0, 4] && segs.map(\.end) == [4, 10])
    ok = segs.split(at: 4.01)
    #expect(!ok)                          // too close to an edge
    ok = segs.split(at: 7)
    #expect(ok)                           // timeline 7 = source 7
    #expect(segs.locate(5)!.index == 1 && segs.locate(5)!.offset == 1)

    segs.removeAll { $0.start == 4 }      // delete middle, gap collapses
    #expect(segs.duration == 7)
    #expect(segs.locate(4.5)!.index == 1) // timeline 4.5 now lands in the 7–10 piece

    segs.move(segs[1].id, to: segs[0].id) // reorder
    #expect(segs.map(\.start) == [7, 0])
    #expect(segs.startTime(of: 1) == 3)
}
