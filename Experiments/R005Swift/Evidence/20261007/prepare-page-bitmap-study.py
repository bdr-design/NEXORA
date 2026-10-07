"""Isolated copy bitmap only; actual runtime and older stamp study stay fixed."""
from pathlib import Path
import sys

package = Path(sys.argv[1]).resolve()
assert package.parent.name == '.page-stamp-study' and package.name in ('base', 'stamp')
preparer = Path(__file__).with_name('prepare-page-stamp-study.py').read_text()
assert preparer.count("if package.name=='stamp':") == 1
# Reuse identical setup telemetry/finite1M harness additions in BOTH arms.
preparer = preparer.replace("if package.name=='stamp':", 'if False:')
exec(compile(preparer, 'prepare-page-stamp-study.py:setup-only', 'exec'), {'__name__': '__main__'})
if package.name == 'stamp':
    path = package / 'Sources/SwiftProbe/EpochPages.swift'
    text = path.read_text()
    text = text.replace('import Foundation\n', '''import Foundation
import Synchronization

// Sole simulation-owner metadata, one box per64pages, not per asset/page.
private final class EpochCopyBits {
    let value = Atomic<UInt64>(0)
}
''', 1)
    assert text.count('private var pageEpoch: ContiguousArray<UInt32>') == 1
    text = text.replace('private var pageEpoch: ContiguousArray<UInt32>',
                        'private let copiedWords: ContiguousArray<EpochCopyBits>')
    assert text.count('pageEpoch = .init(repeating: 0, count: pageCount)') == 1
    text = text.replace('pageEpoch = .init(repeating: 0, count: pageCount)',
                        'copiedWords = .init((0..<((pageCount + 63) >> 6)).map { _ in EpochCopyBits() })')
    needle = '        active = true; epoch = value\n'
    assert text.count(needle) == 1
    text = text.replace(needle, '''        // Measured O(pageCount/64) reset: allocation-free, never called on
        // rejected overlap/stale/foreign begin. Actual-source freeze stays O(1).
        for word in copiedWords { word.value.store(0, ordering: .relaxed) }
''' + needle)
    needle = '@inline(__always) func needsCopy(page: Int) -> Bool { active && pageEpoch[page] != epoch }'
    assert text.count(needle) == 1
    text = text.replace(needle, '''@inline(__always) func needsCopy(page: Int) -> Bool {
        active && (copiedWords[page >> 6].value.load(ordering: .relaxed) & (UInt64(1) << (page & 63))) == 0
    }''')
    needle = '        guard active && pageEpoch[page] != epoch else { return 0 }'
    assert text.count(needle) == 1
    text = text.replace(needle, '        guard needsCopy(page: page) else { return 0 }')
    needle = '        pageEpoch[page] = epoch'
    assert text.count(needle) == 1
    text = text.replace(needle, '''        let word = copiedWords[page >> 6]
        word.value.store(word.value.load(ordering: .relaxed) | (UInt64(1) << (page & 63)), ordering: .relaxed)''')
    needle = '        total += (leafEpoch.capacity + pageEpoch.capacity) * MemoryLayout<UInt32>.stride'
    assert text.count(needle) == 1
    text = text.replace(needle, '''        total += leafEpoch.capacity * MemoryLayout<UInt32>.stride
        total += copiedWords.capacity * MemoryLayout<EpochCopyBits>.stride
        // Conservative64B/box allowance, explicitly not measured physical heap.
        total += copiedWords.count * 64''')
    assert 'pageEpoch' not in text
    path.write_text(text)
