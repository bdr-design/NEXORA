import Foundation
import ProbePlatform

private let detailMagic: UInt64 = 0x314c49415445444e
private let summaryMagic: UInt64 = 0x315952414d4d5553
struct LedgerRow {
    var invoice: UInt64, operation: UInt64, tick: UInt64, amount: Int64
    var asset: UInt32, generation: UInt32, entity: UInt32, period: UInt32
    var debit: UInt32, credit: UInt32, flags: UInt32
    func encode(into b: inout Bytes) {
        b.u64(invoice);b.u64(operation);b.u64(tick);b.i64(amount)
        b.u32(asset);b.u32(generation);b.u32(entity);b.u32(period);b.u32(debit);b.u32(credit);b.u32(flags);b.u32(0)
    }
    static func read(_ r: inout Reader) throws -> LedgerRow {
        let value=try LedgerRow(invoice:r.u64(),operation:r.u64(),tick:r.u64(),amount:r.i64(),asset:r.u32(),generation:r.u32(),entity:r.u32(),period:r.u32(),debit:r.u32(),credit:r.u32(),flags:r.u32())
        guard try r.u32()==0,value.amount>0,value.entity<32,(1...3).contains(value.period),value.debit<3,value.credit<3,value.debit != value.credit,value.flags<=2 else {throw ProbeError.corruption("ledger row")}
        return value
    }
}
final class RowWriter {
    private let h:FileHandle
    private var buffer=Bytes(reserve:65536)
    private(set) var rows:UInt64=0
    init(_ path:String) throws {
        h=try exclusiveHandle(path)
        var header=Bytes();header.u64(detailMagic);header.u64(1);try h.write(contentsOf:Data(header.data))
    }
    func append(_ row:LedgerRow) throws {
        row.encode(into:&buffer);rows += 1
        if buffer.data.count>=65536 {try flush()}
    }
    private func flush() throws {
        try h.write(contentsOf:Data(buffer.data));buffer.data.removeAll(keepingCapacity:true)
    }
    func close() throws {if !buffer.data.isEmpty {try flush()};try h.synchronize();try h.close()}
}
func rows(_ path:String,_ body:(LedgerRow) throws -> Void) throws -> UInt64 {
    let h=try FileHandle(forReadingFrom:URL(fileURLWithPath:path));defer{try? h.close()}
    var header=Reader(bytes:[UInt8](try h.read(upToCount:16) ?? Data()))
    guard try header.u64()==detailMagic,try header.u64()==1 else {throw ProbeError.corruption("detail header")}
    var total:UInt64=0
    while let data=try h.read(upToCount:65536),!data.isEmpty {
        guard data.count%64==0 else {throw ProbeError.corruption("detail truncated row")}
        var r=Reader(bytes:[UInt8](data))
        while r.offset<r.bytes.count {try body(LedgerRow.read(&r));total += 1}
    }
    return total
}
func fileSize(_ path:String) throws -> Int {
    let a=try FileManager.default.attributesOfItem(atPath:path)
    guard let n=a[.size] as? NSNumber else {throw ProbeError.invalid("file size")};return n.intValue
}
func fileHash(_ path:String) throws -> [UInt64] {
    let value=nx_hash_file(path);guard value.status==0 else {throw ProbeError.invalid("hash file")}
    return [value.a,value.b,value.c,value.d]
}
func manifest(_ value:[String:Any], directory:String) throws {
    let path=directory+"/manifest.tmp",h=try exclusiveHandle(path);defer{try? h.close()}
    try h.write(contentsOf:try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]))
    try h.synchronize();try h.close();nx_kill_point("summary.before_manifest")
    guard nx_replace_file(path,directory+"/manifest.json")==0 else {throw ProbeError.invalid("manifest rename")}
    nx_kill_point("summary.after_manifest")
    guard nx_sync_dir(directory)==0 else {throw ProbeError.invalid("manifest dir sync")}
}
func makeLedger(_ directory:String,count:Int,days:Int=1) throws -> [String:Any] {
    guard (1...1_000_000).contains(count), (1...3).contains(days) else {throw ProbeError.invalid("ledger population")}
    try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:false)
    let start=nx_now(),writer=try RowWriter(directory+"/detail.bin")
    for leg in 0..<(5*days) {
        for i in 0..<count {
            let invoice=UInt64(leg*count+i+1),unpaid=(leg*count+i)%10==0
            let amount=Int64(i%97+101),time=UInt64(leg*17280+i%600+1)
            let issue=LedgerRow(invoice:invoice,operation:invoice*2-1,tick:time,amount:amount,
                asset:UInt32(i),generation:1,entity:UInt32(i%32),period:UInt32(leg/5+1),debit:1,credit:2,flags:unpaid ? 1:0)
            try writer.append(issue)
            if !unpaid {
                let collect=LedgerRow(invoice:invoice,operation:invoice*2,tick:time+600,amount:amount,
                    asset:UInt32(i),generation:1,entity:UInt32(i%32),period:UInt32(leg/5+1),debit:0,credit:1,flags:2)
                try writer.append(collect)
            }
        }
    }
    try writer.close();let elapsed=nx_now()-start
    let hash=try fileHash(directory+"/detail.bin")
    try manifest(["generation":0,"assets":count,"detailHash":hash,"rows":writer.rows],directory:directory)
    return ["rows":writer.rows,"writeAndSyncNS":elapsed,"bytes":try fileSize(directory+"/detail.bin")]
}
struct AccountTotals: Equatable {
    var debit=ContiguousArray(repeating:Int64(0),count:288)
    var credit=ContiguousArray(repeating:Int64(0),count:288)
    var entries=ContiguousArray(repeating:UInt64(0),count:288)
    mutating func add(_ row:LedgerRow) throws {
        let d=(Int(row.period-1)*32+Int(row.entity))*3+Int(row.debit),c=(Int(row.period-1)*32+Int(row.entity))*3+Int(row.credit)
        let nd=debit[d].addingReportingOverflow(row.amount),nc=credit[c].addingReportingOverflow(row.amount)
        guard !nd.overflow && !nc.overflow else {throw ProbeError.invalid("summary money overflow")}
        debit[d]=nd.partialValue;credit[c]=nc.partialValue;entries[d] += 1;entries[c] += 1
    }
    func combined(_ other:AccountTotals) throws -> AccountTotals {
        var result=AccountTotals()
        for i in 0..<288 {
            let d=debit[i].addingReportingOverflow(other.debit[i]),c=credit[i].addingReportingOverflow(other.credit[i])
            guard !d.overflow && !c.overflow else {throw ProbeError.invalid("summary combine overflow")}
            result.debit[i]=d.partialValue;result.credit[i]=c.partialValue;result.entries[i]=entries[i]+other.entries[i]
        }
        return result
    }
}
func writeSummary(_ totals:AccountTotals,hash:[UInt64],sourceRows:UInt64,path:String) throws {
    var b=Bytes(reserve:4000);b.u64(summaryMagic);b.u32(1);b.u32(288);b.u64(sourceRows)
    for word in hash {b.u64(word)}
    for i in 0..<288 {b.u32(UInt32((i/3)%32));b.u32(UInt32(i/96+1));b.u32(UInt32(i%3));b.u32(0);b.i64(totals.debit[i]);b.i64(totals.credit[i]);b.u64(totals.entries[i])}
    b.finishCRC();let h=try exclusiveHandle(path);defer{try? h.close()};try h.write(contentsOf:Data(b.data));try h.synchronize();try h.close()
}
func readSummary(_ path:String) throws -> AccountTotals {
    let bytes=[UInt8](try Data(contentsOf:URL(fileURLWithPath:path)))
    guard bytes.count==56+288*40+4 else {throw ProbeError.corruption("summary size")}
    var c=Reader(bytes:bytes,offset:bytes.count-4)
    guard try c.u32()==nx_crc(0,bytes,bytes.count-4) else {throw ProbeError.corruption("summary checksum")}
    var r=Reader(bytes:bytes)
    guard try r.u64()==summaryMagic,try r.u32()==1,try r.u32()==288 else {throw ProbeError.corruption("summary header")}
    _ = try r.u64();for _ in 0..<4 {_ = try r.u64()}
    var totals=AccountTotals()
    for i in 0..<288 {
        guard try r.u32()==UInt32((i/3)%32),try r.u32()==UInt32(i/96+1),try r.u32()==UInt32(i%3),try r.u32()==0 else {throw ProbeError.corruption("summary entity/account/period")}
        totals.debit[i]=try r.i64();totals.credit[i]=try r.i64();totals.entries[i]=try r.u64()
        guard totals.debit[i]>=0 && totals.credit[i]>=0 else {throw ProbeError.corruption("summary signs")}
    }
    return totals
}
func compactLedger(_ directory:String,count:Int,days:Int=1,reclaim:Bool=true) throws -> [String:Any] {
    let detail=directory+"/detail.bin",before=try fileSize(detail),start=nx_now()
    let invoices=count*5*days
    var states=ContiguousArray(repeating:UInt8(0),count:invoices)
    var amounts=ContiguousArray(repeating:Int64(0),count:invoices)
    var original=AccountTotals()
    let rowCount=try rows(detail) { row in
        guard row.invoice>0 && row.invoice<=UInt64(invoices) else {throw ProbeError.corruption("invoice ID")}
        let i=Int(row.invoice-1)
        if row.flags==2 {
            guard states[i]==1,amounts[i]==row.amount,row.debit==0,row.credit==1 else {throw ProbeError.corruption("missing/duplicate/overpaid settlement")}
            states[i]=3
        } else {
            guard states[i]==0,row.debit==1,row.credit==2 else {throw ProbeError.corruption("duplicate accrual")}
            states[i]=row.flags==1 ? 5:1;amounts[i]=row.amount
        }
        try original.add(row)
    }
    let hash=try fileHash(detail)
    let openPath=directory+"/open.bin",summaryPath=directory+"/summary.bin"
    let open=try RowWriter(openPath)
    var closedTotals=AccountTotals(),openTotals=AccountTotals(),protectedRows:UInt64=0
    _ = try rows(detail) {row in
        if states[Int(row.invoice-1)] != 3 {
            guard row.flags != 2 else {throw ProbeError.corruption("open settlement mismatch")}
            try open.append(row);try openTotals.add(row);protectedRows += 1
        } else {
            guard row.flags != 1 else {throw ProbeError.corruption("summarizing protected item")}
            try closedTotals.add(row)
        }
    }
    try open.close();try writeSummary(closedTotals,hash:hash,sourceRows:rowCount-protectedRows,path:summaryPath)
    nx_kill_point("summary.after_temp")
    // Independent disk reread; no reliance on just the accumulator supplied to the writer.
    let readBack=try readSummary(summaryPath);var openBack=AccountTotals();var readProtected:UInt64=0
    _ = try rows(openPath) {r in
        guard states[Int(r.invoice-1)] != 3 else {throw ProbeError.corruption("closed item in protected file")}
        try openBack.add(r);readProtected += 1
    }
    try require(try readBack.combined(openBack)==original,"summary+open != original by entity/account/period")
    try require(readBack==closedTotals && openBack==openTotals && readProtected==protectedRows,"summary/open disk identity")
    // Oracle independent of the compaction read loop and its state table.
    var oracle=AccountTotals()
    for leg in 0..<(5*days) {for i in 0..<count {
        let amount=Int64(i%97+101),entity=UInt32(i%32),paid=(leg*count+i)%10 != 0
        try oracle.add(LedgerRow(invoice:0,operation:0,tick:0,amount:amount,asset:0,generation:1,entity:entity,period:UInt32(leg/5+1),debit:1,credit:2,flags:0))
        if paid {try oracle.add(LedgerRow(invoice:0,operation:0,tick:0,amount:amount,asset:0,generation:1,entity:entity,period:UInt32(leg/5+1),debit:0,credit:1,flags:0))}
    }}
    try require(original==oracle,"independent detailed finance oracle")
    try manifest(["generation":1,"assets":count,"rows":rowCount,"protectedRows":protectedRows,"sourceHash":hash,
        "summaryHash":try fileHash(summaryPath),"openHash":try fileHash(openPath)],directory:directory)
    nx_kill_point("summary.before_reclaim")
    if reclaim {try FileManager.default.removeItem(atPath:detail);guard nx_sync_dir(directory)==0 else {throw ProbeError.invalid("reclaim sync")}}
    nx_kill_point("summary.after_reclaim")
    let after=try fileSize(summaryPath)+fileSize(openPath),manifestBytes=try fileSize(directory+"/manifest.json")
    return ["status":"pass","assets":count,"gameDays":days,"tripsPerAssetPerDay":5,"entities":32,"accounts":3,
        "unpaidFraction":0.1,"detailRows":rowCount,"protectedOpenRows":protectedRows,
        "beforeDetailBytes":before,"afterSummaryPlusOpenBytes":after,"manifestBytes":manifestBytes,
        "summaryBytes":try fileSize(summaryPath),"openBytes":try fileSize(openPath),"compactionPeakPayloadBytes":before+after,
        "compactionAndVerificationNS":nx_now()-start,"allEntityAccountPeriodTotalsExact":true,"openItemsSummarized":0,
        "scope":"measured synthetic per-period per-trip issuance+90% full settlement; no periodic billing approval; open backlog is NOT bounded forever"]
}
func validateRetentionGeneration(_ directory:String,count:Int,days:Int=1) throws -> [String:Any] {
    let data=try Data(contentsOf:URL(fileURLWithPath:directory+"/manifest.json"))
    guard let m=try JSONSerialization.jsonObject(with:data) as? [String:Any],let generation=m["generation"] as? Int else {throw ProbeError.corruption("manifest")}
    var total=AccountTotals()
    if generation==0 {_ = try rows(directory+"/detail.bin") {try total.add($0)}}
    else if generation==1 {
        let closed=try readSummary(directory+"/summary.bin");var open=AccountTotals()
        _ = try rows(directory+"/open.bin") { r in
            guard r.flags==1,(r.invoice-1)%10==0 else {throw ProbeError.corruption("protected open row")};try open.add(r)
        };total=try closed.combined(open)
    } else {throw ProbeError.corruption("manifest generation")}
    var expected=AccountTotals()
    for leg in 0..<(5*days) {for i in 0..<count {
        let row=LedgerRow(invoice:0,operation:0,tick:0,amount:Int64(i%97+101),asset:0,generation:1,entity:UInt32(i%32),period:UInt32(leg/5+1),debit:1,credit:2,flags:0)
        try expected.add(row)
        if (leg*count+i)%10 != 0 {var payment=row;payment.debit=0;payment.credit=1;try expected.add(payment)}
    }}
    try require(total==expected,"crash retained partial finance")
    return ["status":"pass","generation":generation,"totalsExact":true]
}
func retentionCheck(_ directory:String,count:Int,days:Int=1) throws -> [String:Any] {
    let created=try makeLedger(directory,count:count,days:days)
    var result=try compactLedger(directory,count:count,days:days)
    result["writeDetailAndSyncNS"]=created["writeAndSyncNS"]
    let start=nx_now();_ = try validateRetentionGeneration(directory,count:count,days:days)
    result["restoreSummaryAndOpenAuditNS"]=nx_now()-start
    return result
}
