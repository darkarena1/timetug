# Spike S: Swift on Windows (findings)

Date: 2026-10-09. Plan: `docs/superpowers/plans/2026-10-09-windows-spike-s.md`. Spec: section 9 of `docs/superpowers/specs/2026-10-09-windows-program-design.md`.

Everything below was measured on one Windows 11 ARM64 virtual machine (Parallels on an Apple silicon Mac). Nothing was tested on x64 hardware. The spike code lived only on the VM and is not kept; this document is the output.

## Environment

| Item | Value |
|---|---|
| Windows | Windows 11 ARM64 (Windows PowerShell 5.1.26100.9549), long paths enabled, Developer Mode not enabled |
| Swift | 6.4.0 (`swift-6.4-RELEASE`), target `aarch64-unknown-windows-msvc`, from `winget install Swift.Toolchain`. The toolchain is the `+Asserts` build ("Build config: +assertions"), so build times are pessimistic |
| .NET SDK | 10.0.401 (win-arm64) |
| Git | Git for Windows 2.55.0 (arm64) |
| Visual Studio | Community 2022 17.7.34009 (already on the VM) plus the three components the plan lists, added with `setup.exe modify`: Windows 11 SDK 22621, MSVC x86/x64 tools, MSVC ARM64 tools (MSVC 14.37.32822) |
| Repository | `darkarena1/timetug` at `a7b1cb8`, cloned with `core.autocrlf=false` |

How the VM was driven: not over SSH. Parallels' `prlctl exec` runs a command as the VM's signed-in user (not elevated), and winget's installers that need elevation ran without a prompt on this VM. The SSH steps in the plan were not needed.

## Package tests

| Package | Build | Passed | Failed | Skipped |
|---|---|---|---|---|
| CalendarConnectors | succeeds | 98 | 0 | 4 |
| TimeTugCore | succeeds | 299 | 0 | 0 |
| CalendarBridge | succeeds | 13 | 0 | 0 |

First build plus test took about 4 minutes for CalendarConnectors, 1 minute for TimeTugCore and 1 minute for CalendarBridge on the Asserts toolchain.

The four skipped tests are deliberate in the tests themselves: `liveFeedLoads` and `iCloudLiveSmoke` (live services), and `transportCanDeclineRedirects` and `transportFollowsRedirectsByDefault`. The last two are the same redirect tests the Linux job (`core-linux`) skips, so nothing is new.

### Failures by class

None.

Build warnings (not failures): `'RedirectingProtocol' inherits an unavailable 'Sendable' conformance` (FoundationNetworking on Windows), a `wchar_t ... broken by a context change` message from the C headers, and ordinary Swift 6 diagnostics (`'is' test is always true`, `no calls to throwing functions occur within 'try'`) that the Mac build presumably also reports.

Two setup notes, neither a Swift finding:

- `git config core.autocrlf` printed `true`: the clone used `-c core.autocrlf=false`, which is not persisted, and the machine's global setting is `true`. The working tree was LF and every test passed. The repository has no CRLF-sensitive fixtures (no `.ics` files), but nothing stops a developer with the Git for Windows default from checking out CRLF files; see recommendation 4.
- SwiftPM could not create its `.build\release` convenience symlink (`unable to create symbolic link ... I/O error (code: 512)`) because creating symbolic links needs Developer Mode or an elevated session. The build itself succeeded and the output is under `.build\out\Products\Release-windows-aarch64\`. A script must not rely on `.build\release`.

## C interface from .NET

- **Exports:** found. `@_cdecl` works; the `@c` fallback was not needed. `dumpbin /exports` lists `tt_engine_create`, `tt_engine_send`, `tt_engine_reply` and `tt_engine_destroy` under their C names. It also exports every public Swift symbol under its mangled name (four more entries); harmless, and not a reason to change anything.
- **DLL:** `EngineProbe.dll`, 2.2 MB. `CalendarCore` (the real connector library, via `ConferenceDetector.detect`) is linked into it statically. Its only dependencies are the Swift runtime DLLs (`Foundation`, `FoundationEssentials`, `FoundationNetworking`, `swiftCore`, `swift_Concurrency`) and the C runtime.
- **Host output** (.NET 10, `LibraryImport`, `delegate* unmanaged[Cdecl]`, `[UnmanagedCallersOnly]`):

```
[thread 2] {"payload":{"config":"{\"dataDir\":\"C:\\\\spike\"}"},"type":"created","v":1}
handle != null: True
[thread 2] {"payload":{"link":"https:\/\/zoom.us\/j\/123456789"},"type":"detected","v":1}
[thread 2] {"id":42,"payload":{"reply":"{\"ok\":true}"},"type":"replied","v":1}
[thread 4] {"payload":{"thread":"background"},"type":"async","v":1}
main thread id: 2
```

- **Thread behaviour:** replies produced while a call is in progress arrive on the caller's thread (thread 2). A message emitted from a detached Swift task arrived on a different thread (4) and the .NET side handled it. Not tested: marshalling that callback back to a UI dispatcher after an `await`; that belongs to the C# wrapper in phase 4.
- **UTF-8 and JSON:** the round trip is intact. Foundation's `JSONSerialization` escapes `/` as `\/` (valid JSON, but byte-for-byte golden fixtures would need to account for it). Console output of the emoji in the Foundation probe was garbled by the console's code page; the decoded value compared equal.
- **Plan defect (not a finding):** the plan's `ProbeHost.csproj` lacks `<ImplicitUsings>enable</ImplicitUsings>`, so `Console`, `Thread` and `Environment` did not resolve until it was added.

## Runtime size

Measured from the Swift runtime folder (`...\Swift\Runtimes\6.4.0\usr\bin`), uncompressed, ARM64:

| Item | Size |
|---|---|
| Full runtime folder | 63.0 MB (35 DLLs) |
| Minimal set the DLL needs (followed by `dumpbin /dependents`, 18 DLLs) | 57.4 MB |
| Minimal set plus `EngineProbe.dll`, run from a clean folder | 59.6 MB, runs correctly |
| Largest single DLL | `_FoundationICU.dll`, 36.2 MB |

The next largest are `swiftCore.dll` 5.2 MB, `FoundationEssentials.dll` 5.0 MB, `Foundation.dll` 4.4 MB, `FoundationNetworking.dll` 1.4 MB, `MSVCP140.dll` 1.3 MB and `FoundationInternationalization.dll` 1.3 MB. The two C runtime DLLs (`MSVCP140`, `VCRUNTIME140`, 1.5 MB together) would normally come from the Visual C++ runtime framework package in an MSIX, not be bundled. MSIX compresses the package, so the download will be smaller than these figures; that was not measured.

## Foundation probe

```
PASS IANA zone resolves: Optional("America/Denver")
PASS DST jump: 01:30 + 1h -> 3:30
PASS Denver offset in July: -21600
PASS current zone: America/Guatemala
PASS ISO8601 parse: Optional(2026-10-09 15:30:00 +0000)
PASS JSON round trip with emoji: Optional(FoundationProbe.Sample(title: "Design review ✅", start: 2026-10-09 15:30:00 +0000))
PASS atomic write: C:/Users/scottobryan/AppData/Local/TimeTugSpike/ledger.json
PASS read back: C:/Users/scottobryan/AppData/Local/TimeTugSpike
PASS HTTPS GET: status 200
PASS proxy env: HTTPS_PROXY=unset (system proxy behaviour not tested in this spike)
```

Observations: the VM's Windows time zone ("Central America Standard Time") mapped to the IANA name `America/Guatemala`, so Windows zone names do reach Foundation as IANA identifiers. `applicationSupportDirectory` resolves under `AppData\Local` (not Roaming) and uses forward slashes. The spec's claim that `URLSession` ignores the system proxy was **not checked**: the VM has no proxy configured.

## Review Focus items from the plan

| Item | Result |
|---|---|
| Line endings | Clone used `autocrlf=false`; tests passed. Not exercised with CRLF files (recommendation 4) |
| Long paths | Enabled before building; no path-length failure occurred, and the setup was not tested without it |
| Time zones | IANA zone, DST and offsets pass |
| Callback thread | Off-thread callback works; the post-`await` UI case is for phase 4 |
| TLS and proxy | HTTPS works; system-proxy behaviour not checked |

## Recommendation

**Proceed with approach A as specified, with the following changes.** None needs a change to the architecture. Spec sections named in brackets.

1. **Plan for a package of about 60 MB uncompressed.** `_FoundationICU.dll` (36 MB) is most of it. Measure the compressed MSIX in phase 4, and look at whether the engine can avoid `FoundationInternationalization`/ICU if the package grows beyond what the Store listing should carry. [section 2, section 6 risks]
2. **x64 is still unverified.** This spike ran only on ARM64. The spec already runs `timetug-shared` tests on Windows x64 and ARM64; phase 3 must confirm the x64 toolchain builds the same packages and DLL before the engine is committed to. [section 7]
3. **Developer machines need Developer Mode (or an elevated build) for SwiftPM's convenience symlink**, and build scripts must use `swift build --show-bin-path`, not `.build\release`. [section 7, development docs]
4. **Add a `.gitattributes` with `* text=auto eol=lf` to every new repository**, so a Git for Windows default of `autocrlf=true` cannot change line endings in fixtures or golden files. [section 1]
5. **Compare engine protocol fixtures as parsed JSON, not bytes.** Foundation escapes `/` as `\/` and sorts keys only on request; the conformance suite should not depend on either. [section 2]
6. **Say in the spec that `URLSession` proxy behaviour is unverified**, and test it with a proxied VM before phase 5 relies on it. [section 5/risks]
