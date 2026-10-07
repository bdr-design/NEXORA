"""Reuse the permitted H harness only in disposable base/packet packages."""
from pathlib import Path
import sys

package = Path(sys.argv[1]).resolve()
assert package.parent.name == '.writer-io-study' and package.name in ('base', 'packet')
source = Path(__file__).with_name('prepare-h-paired-study.py').read_text()
old = "assert package.name == 'current' and package.parent.name == '.h-paired-study'"
assert source.count(old) == 1
source = source.replace(old, "assert package.name in ('base', 'packet') and package.parent.name == '.writer-io-study'")
# The complete, unchanged transformation is source-hashed in the artifact.
# Only its temporary package-location assertion differs; no timing path does.
exec(compile(source, 'prepare-h-paired-study.py:writer-study-location', 'exec'), {'__name__': '__main__'})
