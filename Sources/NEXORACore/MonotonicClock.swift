import Dispatch

public enum MonotonicClock {
    @inline(__always)
    public static func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}
