"""Prepare one disposable sealed-WAL micro package; never edit actual Sources."""
from pathlib import Path
import shutil
import sys


if not __debug__:
    raise RuntimeError("sealed WAL preparer requires Python assertions")

assert len(sys.argv) == 2, "prepare-sealed-wal-micro.py PACKAGE"
package = Path(sys.argv[1]).resolve()
assert package.parent.name == ".sealed-wal-study" and package.name == "current"
assert (package / "Package.swift").is_file()
source = package / "Sources" / "SwiftProbe"
assert source.is_dir()

micro = Path(__file__).with_name("SealedWALMicro.swift")
destination = source / micro.name
assert micro.is_file() and not micro.is_symlink()
assert not destination.exists()
shutil.copyfile(micro, destination)

main = source / "Main.swift"
text = main.read_text()
needle = """#if STAGE_C
#if EPOCH_PAGES
        case \"paged-candidate-lifecycle\":"""
assert text.count(needle) == 1
replacement = """#if SEALED_WAL_MICRO
        case \"sealed-wal-micro\":
            guard args.count == 1 else {
                throw ProbeError.invalid(\"sealed-wal-micro\")
            }
            result = try sealedWALMicro()
#endif
#if STAGE_C
#if EPOCH_PAGES
        case \"paged-candidate-lifecycle\":"""
main.write_text(text.replace(needle, replacement))
