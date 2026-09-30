import Foundation
import ProbePlatform

/// Additional real-clock partitions supplement (never replace) the deterministic injected clock cases.
/// Deadlines select stop boundaries only; event equality is the gate, not observed speed.
func completeOrderChecks(_ count: Int) throws -> [String:Any] {
    var result = try orderChecks(count)
    let expected = reference(count)
    var partitions: [[String:Any]] = []
    for budget in [1,7,31,256,1024] {
        let world = try SwiftWorld(count:count); try world.seedFixture()
        var position = 0, calls = 0, timeStops = 0
        while true {
            let p = try world.advance(to:600,budget:budget,deadlineNS:nx_now()+10_000)
            for i in 0..<p.events {
                try require(position<expected.count && world.output(i)==expected[position], "actual-clock event \(position)")
                position += 1
            }
            calls += 1
            if p.stop == .time {timeStops += 1}
            try require(p.stop != .blocked && calls < count*100+100000, "actual-clock liveness")
            if p.stop == .target {break}
        }
        try require(position==count && world.revenue==expected.reduce(0,{$0+$1.amount}), "actual-clock full transcript/state")
        partitions.append(["budget":budget,"eventsCompared":position,"calls":calls,"timeStops":timeStops,"deadlineIntervalNS":10000,"status":"pass"])
    }
    result["actualClockPartitions"] = partitions
    return result
}
