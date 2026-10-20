# Release validation

Forma 1.0.0 targets macOS 15+ and Swift 6+. Validation performed on an Apple silicon Mac running macOS 15.6.

## Conversion and filesystem integration tests

Fourteen tests passed against the integrated package:

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

## Build and packaging

Release compilation succeeded. Packaging stages the app outside synced document folders, signs ad-hoc, verifies the signature, and creates the release ZIP. The unzipped artifact passed `codesign --verify --deep --strict`.

## Native interface verification

The initial workspace layout, sidebar, format controls and file picker were inspected through native accessibility and screenshots. Later import checks encountered repeated automation-service window lookup/capture errors. Runtime diagnostics confirmed the final workspace window was created and visible, and process sampling showed a normal idle event loop. A complete automated import-to-export UI run was **not verified** in this environment. The conversion engine was tested independently as described above. The final app uses an explicitly retained native workspace window, attached file-picker sheets and Dock reopen handling.

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
