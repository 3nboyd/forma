# Release validation

Forma 2.0.0 targets macOS 15+ and Swift 6+. Validation performed on an Apple silicon Mac running macOS 15.6.

## Conversion and filesystem integration tests

The original fourteen conversion and filesystem tests are retained:

- Ordered PDF page ranges and invalid range rejection.
- Actual crop/rotation/filter export dimensions and original byte preservation.
- Duplicate copy names never overwrite; atomic moves preserve data.
- Invalid mixed conversion batches publish no partial results.
- Actual PDF split/merge, password enforcement, wrong-password rejection, unlocking.
- Recursive output destinations and filename path separators rejected.
- macOS textutil output and ZIP signature.
- Actual FFmpeg output duration after trimming.
- PDF page image dimensions and scanned-text rejection.
- Duplicate and overlapping move inputs rejected.
- Writes through an existing open handle follow a moved file; inode preserved.
- Existing destination preservation and symlink-alias duplicate detection.
- Failed multi-file move rolls back previous renames.
- Cross-volume rejection (conditional on a second-volume fixture).

An independent reviewer reran all fourteen tests and verified the move race fix. A separate test run used a mounted second-volume fixture to verify cross-volume preflight without writing to that volume.

Eleven new tests cover capability detection and workspace behavior: image/PDF/audio/video/document choices, incompatible mixed batches, folder/unknown inputs, automatic destination and output defaults, deduplication, filtering, PDF reordering, reduction from mixed to single-type queues, pending imports, and refreshing moved file locations. The integrated suite contains 25 tests.

## Build and packaging

Release compilation succeeded. Packaging stages the app outside synced document folders, signs ad-hoc, verifies the signature, and creates the release ZIP. The unzipped artifact passed `codesign --verify --deep --strict`.

## Native interface verification

The Forma 2 empty state, inline folder browser, detected output-format tiles, image preview and conversion result were inspected through native accessibility and screenshots. An image was selected in the embedded browser and converted through the interface to JPEG. The output was independently decoded as JPEG with the expected 1600 × 1000 dimensions, alongside the original source. A second conversion produced a uniquely numbered JPEG and preserved the existing export. Reopening Add files returned to the previously browsed folder. The release screenshots contain only generated test files.

Finder access was not approved by the computer-use tool, so the actual Finder context-menu interaction could not be automated. A read-only query of macOS Launch Services confirmed that the packaged Forma app is registered as a handler for the test image. The document declarations and application URL handler were also reviewed. Window-wide drops use SwiftUI's file-URL transfer API; a physical Finder-to-window drag was not automated.

## Running tests with Command Line Tools

Full Xcode installations can use `swift test`. On the tested Command Line Tools installation, Swift Testing requires an explicit framework search path and a workaround for a broken cross-import overlay:

```sh
swift test --disable-sandbox \
  -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  -Xlinker -F -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks
```

No tests or UI checks prove compatibility with every possible input file or full fidelity for professional media/document workflows. Consult the README limits.
