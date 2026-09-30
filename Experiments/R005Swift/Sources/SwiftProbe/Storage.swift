import Foundation
import ProbePlatform

struct Bytes {
    var data: [UInt8] = []
    init(reserve: Int = 0) { data.reserveCapacity(reserve) }
    mutating func u8(_ value: UInt8) { data.append(value) }
    mutating func u32(_ value: UInt32) {
        data.append(UInt8(truncatingIfNeeded:value));data.append(UInt8(truncatingIfNeeded:value >> 8))
        data.append(UInt8(truncatingIfNeeded:value >> 16));data.append(UInt8(truncatingIfNeeded:value >> 24))
    }
    mutating func u64(_ value: UInt64) {
        u32(UInt32(truncatingIfNeeded:value));u32(UInt32(truncatingIfNeeded:value >> 32))
    }
    mutating func i64(_ value: Int64) { u64(UInt64(bitPattern:value)) }
    mutating func finishCRC() { let crc=nx_crc(0,data,data.count);u32(crc) }
}
struct Reader {
    let bytes: [UInt8]
    var offset=0
    mutating func u8() throws -> UInt8 {
        guard offset<bytes.count else {throw ProbeError.corruption("truncated byte")};defer{offset += 1};return bytes[offset]
    }
    mutating func u32() throws -> UInt32 {
        guard offset<=bytes.count-4 else {throw ProbeError.corruption("truncated UInt32")}
        defer{offset += 4}
        return UInt32(bytes[offset]) | UInt32(bytes[offset+1]) << 8 | UInt32(bytes[offset+2]) << 16 | UInt32(bytes[offset+3]) << 24
    }
    mutating func u64() throws -> UInt64 { let low=try u32(), high=try u32();return UInt64(low) | UInt64(high) << 32 }
    mutating func i64() throws -> Int64 { Int64(bitPattern:try u64()) }
}
func exclusiveHandle(_ path:String) throws -> FileHandle {
    guard !path.utf8.contains(0) else {throw ProbeError.invalid("NUL output path")}
    let fd=nx_open_exclusive(path)
    guard fd>=0 else {throw ProbeError.invalid("exclusive output errno \(-fd): \(path)")}
    return FileHandle(fileDescriptor:fd,closeOnDealloc:true)
}
let snapshotMagic:UInt64=0x3150414e5352584e
let snapshotTail:UInt64=0x44455454494d4f43

/// Canonical little-endian encoding. No native object/padding/pointer bytes.
/// The full-copy experiment is NOT an incremental production checkpoint implementation.
func snapshotBytes(_ w:SwiftWorld, sequence:UInt64) throws -> [UInt8] {
    var b=Bytes(reserve:w.count*82+2048)
    b.u64(snapshotMagic);b.u32(1);b.u32(UInt32(w.count));b.u64(sequence);b.u64(w.now)
    b.i64(w.revenue);b.i64(w.receivable);b.i64(w.cash);b.u64(w.processed);b.u64(w.sequenceHash)
    b.u32(UInt32(w.groupAmounts.count));b.u32(UInt32(w.wheel.pending))
    for i in 0..<w.count {
        b.u32(w.generations[i]);b.u32(w.airports[i]);b.u32(w.destinations[i]);b.u64(w.departures[i])
        b.i64(w.fares[i]);b.u64(w.completed[i]);b.u64(w.accruedOperations[i]);b.u8(w.active[i])
    }
    for amount in w.groupAmounts {b.i64(amount)}
    // Canonical event ordering by asset identity, independent of ephemeral node slots/sort continuation.
    var nodes=ContiguousArray(repeating:Event.empty,count:w.count)
    for id in 0..<w.wheel.capacity where w.wheel.live[id] == 1 {
        let e=w.wheel.event(UInt32(id));try require(Int(e.asset)<w.count && nodes[Int(e.asset)].asset==none,"snapshot event uniqueness")
        nodes[Int(e.asset)]=e
    }
    for i in 0..<w.count where nodes[i].asset != none {
        let e=nodes[i];b.u64(e.due);b.u64(e.operation);b.u32(e.asset);b.u32(e.generation);b.u8(e.kind)
    }
    b.u64(snapshotTail);b.finishCRC();return b.data
}
func restoreSnapshot(_ bytes:[UInt8]) throws -> (SwiftWorld,UInt64) {
    guard bytes.count>=92 else {throw ProbeError.corruption("short snapshot")}
    var crcReader=Reader(bytes:bytes,offset:bytes.count-4)
    let stored=try crcReader.u32(),actual=nx_crc(0,bytes,bytes.count-4)
    guard stored==actual else {throw ProbeError.corruption("snapshot checksum")}
    var r=Reader(bytes:bytes)
    guard try r.u64()==snapshotMagic,try r.u32()==1 else {throw ProbeError.corruption("snapshot identity/version")}
    let n=Int(try r.u32());guard (1...2_000_000).contains(n) else {throw ProbeError.corruption("snapshot capacity")}
    let sequence=try r.u64(), now=try r.u64(),revenue=try r.i64(),receivable=try r.i64(),cash=try r.i64(),processed=try r.u64(),hash=try r.u64()
    let groups=Int(try r.u32()),events=Int(try r.u32())
    guard groups==(n+15)/16,events<=n,bytes.count==80+45*n+8*groups+25*events+12 else {throw ProbeError.corruption("snapshot length/counts")}
    let w=try SwiftWorld(count:n);try w.restoreScalars(now:now,revenue:revenue,receivable:receivable,cash:cash,processed:processed,hash:hash)
    for i in 0..<n {
        try w.restoreAsset(i,gen:r.u32(),airport:r.u32(),destination:r.u32(),departure:r.u64(),fare:r.i64(),trips:r.u64(),last:r.u64(),active:r.u8())
    }
    var groupTotal:Int64=0
    for i in 0..<groups {let value=try r.i64();try w.restoreGroup(i,value);let sum=groupTotal.addingReportingOverflow(value);guard !sum.overflow else {throw ProbeError.corruption("group overflow")};groupTotal=sum.partialValue}
    guard groupTotal==w.revenue else {throw ProbeError.corruption("group/balance mismatch")}
    var seen=ContiguousArray(repeating:false,count:n)
    for _ in 0..<events {
        let e=try Event(due:r.u64(),operation:r.u64(),asset:r.u32(),generation:r.u32(),kind:r.u8())
        let i=Int(e.asset)
        guard i<n,!seen[i],w.active[i]==1,e.kind<=2,e.operation>w.accruedOperations[i],e.due>=now else {throw ProbeError.corruption("snapshot event")}
        seen[i]=true;_ = try w.wheel.schedule(e)
    }
    for i in 0..<n {guard seen[i] == (w.active[i]==1) else {throw ProbeError.corruption("missing active event")}}
    guard try r.u64()==snapshotTail,r.offset==bytes.count-4 else {throw ProbeError.corruption("snapshot footer")}
    return (w,sequence)
}
func checkpoint(_ w:SwiftWorld,sequence:UInt64,directory:String) throws -> Int {
    let bytes=try snapshotBytes(w,sequence:sequence),temp=directory+"/checkpoint.tmp",path=directory+"/checkpoint.bin"
    let h=try exclusiveHandle(temp);defer{try? h.close()}
    nx_kill_point("snapshot.before_header")
    try h.write(contentsOf:Data(bytes[0..<80]));nx_kill_point("snapshot.after_header")
    let middle=80+(bytes.count-80)/2
    try h.write(contentsOf:Data(bytes[80..<middle]));nx_kill_point("snapshot.mid_columns")
    try h.write(contentsOf:Data(bytes[middle..<(bytes.count-12)]));nx_kill_point("snapshot.after_columns")
    try h.write(contentsOf:Data(bytes[(bytes.count-12)...]));nx_kill_point("snapshot.after_footer")
    try h.synchronize();nx_kill_point("snapshot.after_sync")
    try h.close();nx_kill_point("snapshot.before_rename")
    guard nx_replace_file(temp,path)==0 else {throw ProbeError.invalid("checkpoint rename")}
    nx_kill_point("snapshot.after_rename")
    guard nx_sync_dir(directory)==0 else {throw ProbeError.invalid("directory sync")}
    nx_kill_point("snapshot.after_directory_sync")
    return bytes.count
}

struct ReplayCommand {
    let sequence:UInt64
    let target:UInt64
    let events:UInt64
}
final class EventTranscript { var events:[Completion]=[]; init(reserve:Int){events.reserveCapacity(reserve)} }
func execute(_ command:ReplayCommand,on w:SwiftWorld, record:EventTranscript? = nil) throws {
    guard command.target>=w.now,command.events<=UInt64(w.wheel.pending) else {throw ProbeError.corruption("invalid replay command")}
    var remaining=command.events
    while remaining>0 {
        let p=try w.advance(to:command.target,budget:Int(min(remaining,256)))
        guard p.stop != .blocked,p.events>0 || p.stop == .work else {throw ProbeError.corruption("replay command cannot progress")}
        if let record {for i in 0..<p.events {record.events.append(w.output(i))}}
        remaining -= UInt64(p.events)
    }
}
let walMagic:UInt64=0x314c415752584e
let walCommit:UInt64=0x31544d4352584e
func appendWAL(_ command:ReplayCommand,directory:String) throws {
    let path=directory+"/commands.wal"
    guard !path.utf8.contains(0) else {throw ProbeError.invalid("NUL WAL path")}
    let fd=nx_open_append(path);guard fd>=0 else {throw ProbeError.invalid("WAL open")}
    let h=FileHandle(fileDescriptor:fd,closeOnDealloc:true);defer{try? h.close()}
    var b=Bytes(reserve:48);b.u64(walMagic);b.u32(48);b.u64(command.sequence);b.u64(command.target);b.u64(command.events);b.finishCRC();b.u64(walCommit)
    try require(b.data.count==48,"WAL encoding size")
    nx_kill_point("wal.before_header")
    try h.write(contentsOf:Data(b.data[0..<12]));nx_kill_point("wal.after_header")
    try h.write(contentsOf:Data(b.data[12..<24]));nx_kill_point("wal.mid_payload")
    try h.write(contentsOf:Data(b.data[24..<40]));nx_kill_point("wal.before_commit")
    try h.write(contentsOf:Data(b.data[40..<44]));nx_kill_point("wal.mid_commit")
    try h.write(contentsOf:Data(b.data[44..<48]));nx_kill_point("wal.after_commit")
    try h.synchronize();nx_kill_point("wal.after_sync")
    guard nx_sync_dir(directory)==0 else {throw ProbeError.invalid("WAL directory sync")}
    nx_kill_point("wal.after_directory_sync")
}
func recover(directory:String, record:EventTranscript? = nil) throws -> (SwiftWorld,UInt64,Int) {
    let snapshot=[UInt8](try Data(contentsOf:URL(fileURLWithPath:directory+"/checkpoint.bin")))
    let (world,checkpointSequence)=try restoreSnapshot(snapshot)
    let path=directory+"/commands.wal"
    let bytes=FileManager.default.fileExists(atPath:path) ? [UInt8](try Data(contentsOf:URL(fileURLWithPath:path))) : []
    var position=0,sequence=checkpointSequence,previous:UInt64=0
    while position+48<=bytes.count {
        let frame=Array(bytes[position..<(position+48)]);var r=Reader(bytes:frame)
        guard try r.u64()==walMagic,try r.u32()==48 else {throw ProbeError.corruption("WAL header")}
        let seq=try r.u64(),target=try r.u64(),count=try r.u64(),crc=try r.u32(),marker=try r.u64()
        guard marker==walCommit,crc==nx_crc(0,frame,36) else {throw ProbeError.corruption("WAL committed frame")}
        guard seq==previous+1 else {throw ProbeError.corruption("WAL missing/duplicate command")};previous=seq
        if seq>checkpointSequence {
            guard seq==sequence+1 else {throw ProbeError.corruption("WAL replay gap")}
            try execute(ReplayCommand(sequence:seq,target:target,events:count),on:world,record:record);sequence=seq
        }
        position += 48
    }
    // Incomplete uncommitted tail stays on disk. It is neither applied nor silently deleted.
    return (world,sequence,bytes.count-position)
}
func bootstrap(_ directory:String,count:Int) throws {
    try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:false)
    let w=try SwiftWorld(count:count);try w.seedFixture();_ = try checkpoint(w,sequence:0,directory:directory)
    _ = FileManager.default.createFile(atPath:directory+"/commands.wal",contents:nil)
}
func storageCheck(_ directory:String,count:Int) throws -> [String:Any] {
    try bootstrap(directory,count:count)
    let (world,_,_)=try recover(directory:directory)
    let first=ReplayCommand(sequence:1,target:600,events:UInt64(count/3))
    let prefix=EventTranscript(reserve:count/3)
    try appendWAL(first,directory:directory);try execute(first,on:world,record:prefix)
    let start=nx_now();let size=try checkpoint(world,sequence:1,directory:directory);let writeNS=nx_now()-start
    let rest=ReplayCommand(sequence:2,target:600,events:UInt64(count-count/3))
    let suffix=EventTranscript(reserve:count-count/3)
    try appendWAL(rest,directory:directory);try execute(rest,on:world,record:suffix)
    let replay=EventTranscript(reserve:count-count/3)
    let recovering=nx_now();let (restored,sequence,tail)=try recover(directory:directory,record:replay);let recoveryNS=nx_now()-recovering
    try require(replay.events==suffix.events,"replay event-by-event suffix")
    let full=reference(count)
    try require(prefix.events+suffix.events==full,"continuous event-by-event independent reference")
    try require(sequence==2 && tail==0,"recovery watermark")
    let expected=try snapshotBytes(world,sequence:sequence),actual=try snapshotBytes(restored,sequence:sequence)
    try require(expected==actual,"checkpoint+commands != continuous state/sequence")
    let oracle=try SwiftWorld(count:count);try oracle.seedFixture()
    _ = try drain(oracle,target:600)
    try require(world.sequenceHash==oracle.sequenceHash && world.revenue==oracle.revenue,"replay independent uninterrupted transcript")
    return ["status":"pass","assets":count,"snapshotBytes":size,"snapshotBytesPerAsset":Double(size)/Double(count),
            "walBytes":96,"writeAndSyncNS":writeNS,"restoreAndReplayNS":recoveryNS,"sequence":sequence,"events":restored.processed,
            "exactCanonicalStateAndSequence":true,"exactReplayTranscriptEvents":replay.events.count,"scope":"full-copy typed-column checkpoint + committed commands; NOT incremental production save; no device pause claim"]
}
func crashAction(_ directory:String,checkpointAction:Bool) throws {
    let (w,seq,_)=try recover(directory:directory)
    let c=ReplayCommand(sequence:seq+1,target:600,events:5)
    try appendWAL(c,directory:directory);try execute(c,on:w)
    nx_kill_point("transaction.after_apply")
    if checkpointAction {_ = try checkpoint(w,sequence:c.sequence,directory:directory)}
}
func recoverySummary(_ directory:String) throws -> [String:Any] {
    let (w,sequence,tail)=try recover(directory:directory)
    let independent=try SwiftWorld(count:w.count);try independent.seedFixture()
    if sequence>0 {try execute(ReplayCommand(sequence:sequence,target:600,events:sequence*5),on:independent)}
    try require(try snapshotBytes(w,sequence:sequence)==snapshotBytes(independent,sequence:sequence),"kill recovered partial/wrong state")
    return ["status":"pass","sequence":sequence,"processed":w.processed,"ignoredUncommittedTailBytes":tail,"hash":w.sequenceHash]
}
