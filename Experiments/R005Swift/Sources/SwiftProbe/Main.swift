import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@main enum Main {
    static func main() {
        do {try run()} catch {
            FileHandle.standardError.write(Data((String(describing:error)+"\n").utf8)); exit(1)
        }
    }
    static func run() throws {
        let args=Array(CommandLine.arguments.dropFirst())
        let result: Any
        switch args.first {
        case "selftest": result=["boundaries":try boundaryChecks(),"mutations":try mutationChecks()]
        case "order":
            guard args.count==2,let n=Int(args[1]) else {throw ProbeError.invalid("order N")}
            result=try completeOrderChecks(n)
        case "hybrid-selftest":
            result=try hybridLayoutSelftest()
        case "hybrid-mutants":
            result=try hybridMutationChecks()
        case "hybrid-order":
            guard args.count==2,let n=Int(args[1]) else {throw ProbeError.invalid("hybrid-order N")}
            result=try hybridOrderChecks(n)
        case "stage-a-bench":
            guard args.count==4,let n=Int(args[2]),let runs=Int(args[3]) else {
                throw ProbeError.invalid("stage-a-bench S|H N 10")
            }
            result=try stageABenchmark(variant:args[1],count:n,measuredRuns:runs)
        case "stage-b":
            guard args.count==3 else {throw ProbeError.invalid("stage-b directory G16|G1")}
            result=try stageBRun(args[1],caseName:args[2])
        case "stage-b-window":
            guard args.count==4,let window=Int(args[3]) else {throw ProbeError.invalid("stage-b-window directory G1 3")}
            result=try stageBRun(args[1],caseName:args[2],window:window)
        case "stage-b-crash-bootstrap":
            guard args.count==2 else {throw ProbeError.invalid("stage-b-crash-bootstrap directory")}
            result=try stageBCrashBootstrap(args[1])
        case "stage-b-crash-action":
            guard args.count==2 else {throw ProbeError.invalid("stage-b-crash-action directory")}
            result=try stageBCrashAction(args[1])
        case "stage-b-recover-crash":
            guard args.count==2 else {throw ProbeError.invalid("stage-b-recover-crash directory")}
            result=try stageBRecoverCrash(args[1])
#if STAGE_C
        case "stage-c-transport-checks":
            guard args.count == 2 else { throw ProbeError.invalid("stage-c-transport-checks directory") }
            result = try stageCMicroTransportChecks(args[1])
        case "stage-c-micro-components":
            guard args.count == 2 else { throw ProbeError.invalid("stage-c-micro-components directory") }
            result = try stageCMicroComponents(args[1])
        case "stage-c-micro":
            guard args.count == 3, ["S", "H"].contains(args[2]) else {
                throw ProbeError.invalid("stage-c-micro directory S|H")
            }
            result = args[2] == "H" ? try stageCHybridRun(args[1], requestedSaves: 5, diagnosticOnly: true) :
                try stageCRun(args[1], requestedSaves: 5, diagnosticOnly: true)
        case "stage-c-allocation-probes":
            guard args.count==2,["S","H"].contains(args[1]) else {
                throw ProbeError.invalid("stage-c-allocation-probes S|H")
            }
            result = args[1] == "H" ? try stageCHybridAllocationProbes() : try stageCAllocationProbes()
        case "stage-c-smoke":
            guard args.count==4,["S","H"].contains(args[2]),let n=Int(args[3]) else {
                throw ProbeError.invalid("stage-c-smoke directory S|H N")
            }
            result = args[2] == "H" ? try stageCHybridSmoke(args[1],count:n) : try stageCSmoke(args[1],count:n)
        case "stage-c":
            guard args.count==4,let n=Int(args[2]),let saves=Int(args[3]) else {
                throw ProbeError.invalid("stage-c directory N saves")
            }
            result=try stageCRun(args[1],count:n,requestedSaves:saves)
        case "stage-c-h":
            guard args.count==4,let n=Int(args[2]),let saves=Int(args[3]) else {
                throw ProbeError.invalid("stage-c-h directory N saves")
            }
            result=try stageCHybridRun(args[1],count:n,requestedSaves:saves)
        case "stage-c-crash-bootstrap":
            guard args.count==3,let n=Int(args[2]) else {
                throw ProbeError.invalid("stage-c-crash-bootstrap directory N")
            }
            result=try stageCCrashBootstrap(args[1],count:n)
        case "stage-c-crash-action":
            guard args.count==3 else {throw ProbeError.invalid("stage-c-crash-action directory point")}
            result=try stageCCrashAction(args[1],point:args[2])
        case "stage-c-recover":
            guard args.count==2 else {throw ProbeError.invalid("stage-c-recover directory")}
            result=try stageCRecoverCrash(args[1])
        case "stage-c-chain-expected":
            guard args.count==2 else {throw ProbeError.invalid("stage-c-chain-expected directory")}
            result=try stageCWALChainExpected(args[1])
        case "stage-c-chain-crash":
            guard args.count==2 else {throw ProbeError.invalid("stage-c-chain-crash directory")}
            result=try stageCWALChainCrashAction(args[1])
        case "stage-c-h-crash-bootstrap":
            guard args.count==3,let n=Int(args[2]) else {throw ProbeError.invalid("stage-c-h-crash-bootstrap directory N")}
            result=try stageCHybridCrashBootstrap(args[1],count:n)
        case "stage-c-h-crash-action":
            guard args.count==3 else {throw ProbeError.invalid("stage-c-h-crash-action directory point")}
            result=try stageCHybridCrashAction(args[1],point:args[2])
        case "stage-c-h-recover":
            guard args.count==2 else {throw ProbeError.invalid("stage-c-h-recover directory")}
            result=try stageCHybridRecoverCrash(args[1])
        case "stage-c-h-chain-expected":
            guard args.count==2 else {throw ProbeError.invalid("stage-c-h-chain-expected directory")}
            result=try stageCHybridWALChainExpected(args[1])
        case "stage-c-h-chain-crash":
            guard args.count==2 else {throw ProbeError.invalid("stage-c-h-chain-crash directory")}
            result=try stageCHybridWALChainCrashAction(args[1])
#endif
        case "storage":
            guard args.count==3, let n=Int(args[2]) else {throw ProbeError.invalid("storage directory N")}
            result=try storageCheck(args[1],count:n)
        case "retention-multi":
            guard args.count==3, let n=Int(args[2]) else {throw ProbeError.invalid("retention-multi directory N")}
            result=try retentionCheck(args[1],count:n,days:3)
        case "retention":
            guard args.count==3, let n=Int(args[2]) else {throw ProbeError.invalid("retention directory N")}
            result=try retentionCheck(args[1],count:n)
        case "bootstrap":
            guard args.count==3, let n=Int(args[2]) else {throw ProbeError.invalid("bootstrap directory N")}
            try bootstrap(args[1],count:n);result=["status":"pass"]
        case "crash-action":
            guard args.count==3 else {throw ProbeError.invalid("crash-action directory wal|snapshot")}
            try crashAction(args[1],checkpointAction:args[2]=="snapshot");result=["status":"pass"]
        case "recover":
            guard args.count==2 else {throw ProbeError.invalid("recover directory")};result=try recoverySummary(args[1])
        case "make-ledger":
            guard args.count==3,let n=Int(args[2]) else {throw ProbeError.invalid("make-ledger directory N")}
            result=try makeLedger(args[1],count:n)
        case "compact-ledger":
            guard args.count==3,let n=Int(args[2]) else {throw ProbeError.invalid("compact-ledger directory N")}
            result=try compactLedger(args[1],count:n)
        case "recover-ledger":
            guard args.count==3,let n=Int(args[2]) else {throw ProbeError.invalid("recover-ledger directory N")}
            result=try validateRetentionGeneration(args[1],count:n)
        case "bench":
            guard args.count>=3,let n=Int(args[1]),let b=Int(args[2]) else {throw ProbeError.invalid("bench N budget [legacy|deadline]")}
            result=try benchmark(n,budget:b,legacy:args.contains("legacy"),deadline:args.contains("deadline"))
        default:
            throw ProbeError.invalid("selftest | order N | hybrid-selftest | hybrid-mutants | hybrid-order N | stage-a-bench S|H N 10 | stage-b directory G16|G1 | bench N budget")
        }
        let data=try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys,.prettyPrinted])
        print(String(decoding:data,as:UTF8.self))
    }
}
