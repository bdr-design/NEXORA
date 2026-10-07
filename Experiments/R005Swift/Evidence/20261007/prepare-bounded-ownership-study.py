"""Prepare one disposable H-cold ownership micro package; never edit actual Sources."""
from pathlib import Path
import shutil
import sys

if not __debug__:
    raise RuntimeError('bounded ownership preparer requires Python assertions')

package = Path(sys.argv[1]).resolve()
assert package.parent.name == '.bounded-ownership-study' and package.name == 'current'
source = package / 'Sources' / 'SwiftProbe'
assert source.is_dir()

micro = Path(__file__).with_name('BoundedEpochOwnershipMicro.swift')
destination = source / micro.name
assert micro.is_file() and not destination.exists()
shutil.copyfile(micro, destination)

main = source / 'Main.swift'
text = main.read_text()
needle = '''#if EPOCH_PAGES
        case "paged-candidate-lifecycle":'''
assert text.count(needle) == 1
replacement = '''#if EPOCH_PAGES
#if BOUNDED_EPOCH_MICRO
        case "bounded-epoch-ownership-micro":
            guard args.count == 4, let count = Int(args[1]), let slots = Int(args[2]) else {
                throw ProbeError.invalid("bounded-epoch-ownership-micro 257 1|4096 2|100000 2 observe|zero|functional")
            }
            result = try boundedEpochOwnershipMicro(count: count, slots: slots, allocationPolicy: args[3])
#endif
        case "paged-candidate-lifecycle":'''
main.write_text(text.replace(needle, replacement))
