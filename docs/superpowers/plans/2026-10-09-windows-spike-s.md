# Spike S: Swift on Windows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Update `docs/superpowers/plans/2026-10-09-windows-program-tracker.md` (Now and Session log) when a task finishes.

**Goal:** Find out, cheaply and before any repository moves, whether approach A works: TimeTug's portable Swift code builds and passes its tests on Windows ARM64, a Swift DLL can export C functions that a .NET 10 app calls with UTF-8 JSON and a callback, how large the Swift runtime is, and which Foundation behaviours differ.

**Architecture:** Throwaway code on the Windows VM only (`C:\spike\`), never committed. The only kept output is a findings document in this repository. The agent works from the Mac and runs every Windows command over SSH (`ssh timetug-win`), whose default shell is PowerShell 7.

**Tech Stack:** Swift (latest stable, 6.4.0 on 2026-10-09) for Windows, Visual Studio 2022 Community components (MSVC ARM64 and x64 tools, Windows 11 SDK 22621), .NET 10 SDK, PowerShell 7, Git for Windows, OpenSSH Server.

**Spec:** `docs/superpowers/specs/2026-10-09-windows-program-design.md` (section 9, Spike S; section 2 for the C interface shape).

## Global Constraints

- Nothing from this spike is committed except `docs/spikes/2026-10-09-swift-on-windows.md` and the tracker update.
- Never commit to `master`; work on the current branch (`claude/windows-app-version-6153ea`) or a new `claude/` branch, and finish with a pull request (the owner squash-merges).
- The C interface tried here follows the spec's shape: `tt_engine_create(config_json, on_message, context)`, `tt_engine_send(engine, command_json)`, `tt_engine_reply(engine, request_id, reply_json)`, `tt_engine_destroy(engine)`, UTF-8 JSON, callbacks may arrive on another thread.
- Agents never enter the owner's passwords or credentials anywhere, and never change Windows security settings other than those listed in Task 1, which the owner performs.
- Report results as measured. A failing test is a finding, not something to fix in this spike.

## Review Focus

1. **Line endings:** Git for Windows converts LF to CRLF on checkout by default; iCalendar fixtures and golden strings would then fail for the wrong reason. Clone with `core.autocrlf=false` (Task 2 checks it).
2. **Long paths:** `.build` directories nest deeply and can pass the 260-character limit; long paths must be enabled (Task 1) and a failure with "path too long" is recorded as a setup error, not a Swift finding.
3. **Time zones:** Windows has its own zone names; Swift Foundation must still resolve IANA identifiers (`America/Denver`) and DST transitions (Task 4 probes them).
4. **Callback thread:** the engine will call back from a background thread; the C# side must survive a callback that arrives off its main thread and after `await` (Task 3 calls back from a detached Swift task).
5. **TLS and proxy:** `URLSession` on Windows uses libcurl; an HTTPS request must succeed, and the spec's claim that it ignores the system proxy is recorded as checked or not checked (Task 4).

---

### Task 1: Prepare the Windows VM (owner, with agent verification)

**Files:** none in the repository. On the Mac: `~/.ssh/config` (owner adds the host alias).

**Interfaces:**
- Produces: SSH alias `timetug-win` that opens PowerShell 7 on the VM as the owner's Windows user; `git`, `swift`, `dotnet` on that user's `PATH`.

- [ ] **Step 1 (owner): enable long paths and the SSH server.** In an elevated PowerShell on the VM:

```powershell
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name LongPathsEnabled -Value 1 -PropertyType DWORD -Force
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd
```

- [ ] **Step 2 (owner): install the tools.** In a normal (non-elevated) PowerShell on the VM, one at a time:

```powershell
winget install --id Microsoft.PowerShell -e --source winget
winget install --id Git.Git -e --source winget
winget install --id Microsoft.VisualStudio.2022.Community --exact --force --custom "--add Microsoft.VisualStudio.Component.Windows11SDK.22621 --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.VC.Tools.ARM64" --source winget
winget install --id Swift.Toolchain -e --source winget
winget install --id Microsoft.DotNet.SDK.10 -e --source winget
```

- [ ] **Step 3 (owner): make PowerShell 7 the SSH shell and add the Mac's key.** Elevated PowerShell on the VM:

```powershell
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Program Files\PowerShell\7\pwsh.exe" -PropertyType String -Force
```

Copy the Mac's public key (`~/.ssh/id_ed25519.pub`) into `C:\ProgramData\ssh\administrators_authorized_keys` if the Windows user is an administrator, otherwise into `C:\Users\<user>\.ssh\authorized_keys`. For the administrators file, fix its permissions:

```powershell
icacls.exe "C:\ProgramData\ssh\administrators_authorized_keys" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
```

On the Mac, add to `~/.ssh/config` (with the VM's address from Parallels, Windows `ipconfig`):

```
Host timetug-win
  HostName <the VM's IP address>
  User <the Windows user name>
```

- [ ] **Step 4 (agent): verify.** On the Mac:

```bash
ssh timetug-win '$PSVersionTable.PSVersion.ToString(); git --version; swift --version; dotnet --version; (Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem).LongPathsEnabled; $env:PROCESSOR_ARCHITECTURE'
```

Expected: PowerShell 7.x, a git version, `Swift version 6.4` (or newer) with target `aarch64-unknown-windows-msvc`, a `10.0.x` .NET SDK, `1`, `ARM64`. If `swift` is not found, the owner signs out and back in on the VM once (the installer updates the user `PATH`), then repeat.

- [ ] **Step 5 (agent): record the versions** in the tracker's Session log (no commit yet; Task 5 commits).

### Task 2: Build and test the portable packages on Windows

**Files:** none in the repository. On the VM: `C:\spike\timetug` (clone), `C:\spike\results\*.log`.

**Interfaces:**
- Consumes: `timetug-win` from Task 1.
- Produces: `C:\spike\results\connectors-test.log`, `core-test.log`, `bridge-test.log`, and pass, fail and skip counts for the findings document.

- [ ] **Step 1: clone without line-ending conversion.**

```bash
ssh timetug-win 'New-Item -ItemType Directory -Force C:\spike\results | Out-Null; git -c core.autocrlf=false -c core.longpaths=true clone https://github.com/darkarena1/timetug.git C:\spike\timetug; git -C C:\spike\timetug config core.autocrlf'
```

Expected: the clone completes and the last line prints `false`. (After the organization move the URL is `https://github.com/binary-companion/timetug.git`.)

- [ ] **Step 2: build and test the connector library.**

```bash
ssh timetug-win 'Set-Location C:\spike\timetug; swift test --package-path Packages\CalendarConnectors 2>&1 | Tee-Object C:\spike\results\connectors-test.log | Select-Object -Last 25'
```

Expected: either all tests pass, or a summary line with counts. Record build errors (file and message) separately from test failures. Allow up to 30 minutes for the first build.

- [ ] **Step 3: build and test TimeTugCore.**

```bash
ssh timetug-win 'Set-Location C:\spike\timetug; swift test --package-path Packages\TimeTugCore 2>&1 | Tee-Object C:\spike\results\core-test.log | Select-Object -Last 25'
```

- [ ] **Step 4: build and test CalendarBridge.**

```bash
ssh timetug-win 'Set-Location C:\spike\timetug; swift test --package-path Packages\CalendarBridge 2>&1 | Tee-Object C:\spike\results\bridge-test.log | Select-Object -Last 25'
```

- [ ] **Step 5: classify every failure.** For each failing test, read its log section:

```bash
ssh timetug-win 'Select-String -Path C:\spike\results\*.log -Pattern "error:|failed|Fatal" | Select-Object -First 80 | ForEach-Object { $_.Line }'
```

Put each failure in exactly one class: *line endings*, *time zone or calendar*, *networking (URLProtocol, URLSession)*, *file system or paths*, *concurrency*, *compiler or toolchain*, *other*. Copy the class, test name and first error line into the findings notes. Compare with the Linux job (`core-linux` in `.github/workflows/ci.yml`), which skips two redirect tests: a failure in those is expected, not new.

### Task 3: Swift DLL with the spec's C interface, called from .NET 10

**Files:** on the VM only: `C:\spike\EngineProbe\Package.swift`, `C:\spike\EngineProbe\Sources\EngineProbe\Probe.swift`, `C:\spike\ProbeHost\ProbeHost.csproj`, `C:\spike\ProbeHost\Program.cs`.

**Interfaces:**
- Consumes: `CalendarCore` from the clone (`ConferenceDetector`), to prove the DLL can use the real library.
- Produces: `EngineProbe.dll` exporting `tt_engine_create`, `tt_engine_send`, `tt_engine_reply`, `tt_engine_destroy`; a .NET 10 console app that calls them and prints the messages it receives.

- [ ] **Step 1: write the Swift package.** Create `C:\spike\EngineProbe\Package.swift` (write the files with `ssh timetug-win 'Set-Content -Path ... -Value @"..."@'` or `scp` from the scratchpad):

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EngineProbe",
    products: [.library(name: "EngineProbe", type: .dynamic, targets: ["EngineProbe"])],
    dependencies: [.package(path: "../timetug/Packages/CalendarConnectors")],
    targets: [.target(name: "EngineProbe", dependencies: [.product(name: "CalendarCore", package: "CalendarConnectors")])]
)
```

Create `C:\spike\EngineProbe\Sources\EngineProbe\Probe.swift`:

```swift
import CalendarCore
import Foundation

public typealias TTMessageFn = @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void

final class ProbeEngine: @unchecked Sendable {
    let onMessage: TTMessageFn
    let context: UnsafeMutableRawPointer?
    let config: String
    init(onMessage: TTMessageFn, context: UnsafeMutableRawPointer?, config: String) {
        self.onMessage = onMessage; self.context = context; self.config = config
    }
    func emit(_ object: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        String(decoding: data, as: UTF8.self).withCString { onMessage($0, context) }
    }
}

@_cdecl("tt_engine_create")
public func tt_engine_create(_ configJSON: UnsafePointer<CChar>?, _ onMessage: TTMessageFn?, _ context: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
    guard let onMessage else { return nil }
    let engine = ProbeEngine(onMessage: onMessage, context: context, config: configJSON.map { String(cString: $0) } ?? "{}")
    engine.emit(["v": 1, "type": "created", "payload": ["config": engine.config]])
    return Unmanaged.passRetained(engine).toOpaque()
}

@_cdecl("tt_engine_send")
public func tt_engine_send(_ handle: UnsafeMutableRawPointer?, _ commandJSON: UnsafePointer<CChar>?) {
    guard let handle, let commandJSON else { return }
    let engine = Unmanaged<ProbeEngine>.fromOpaque(handle).takeUnretainedValue()
    let text = String(cString: commandJSON)
    // Synchronous reply on the caller's thread: proves the library is usable inside the DLL.
    let link = ConferenceDetector.detect(location: nil, url: nil, notes: text)?.absoluteString ?? ""
    engine.emit(["v": 1, "type": "detected", "payload": ["link": link]])
    // Asynchronous reply from a background task: proves off-thread callbacks.
    Task.detached {
        try? await Task.sleep(nanoseconds: 200_000_000)
        engine.emit(["v": 1, "type": "async", "payload": ["thread": Thread.isMainThread ? "main" : "background"]])
    }
}

@_cdecl("tt_engine_reply")
public func tt_engine_reply(_ handle: UnsafeMutableRawPointer?, _ requestID: UInt64, _ replyJSON: UnsafePointer<CChar>?) {
    guard let handle else { return }
    let engine = Unmanaged<ProbeEngine>.fromOpaque(handle).takeUnretainedValue()
    engine.emit(["v": 1, "type": "replied", "id": requestID, "payload": ["reply": replyJSON.map { String(cString: $0) } ?? ""]])
}

@_cdecl("tt_engine_destroy")
public func tt_engine_destroy(_ handle: UnsafeMutableRawPointer?) {
    guard let handle else { return }
    Unmanaged<ProbeEngine>.fromOpaque(handle).release()
}
```

Before writing `Probe.swift`, check the real `ConferenceDetector` API in `Packages/CalendarConnectors/Sources/CalendarCore/ConferenceDetector.swift` and adjust the `detect` call to its actual signature; record any adjustment in the findings.

- [ ] **Step 2: build the DLL and list its exports.**

```bash
ssh timetug-win 'Set-Location C:\spike\EngineProbe; swift build -c release 2>&1 | Select-Object -Last 10; Get-ChildItem .build\release\*.dll | Select-Object Name, Length'
ssh timetug-win '& "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\*\bin\HostARM64\arm64\dumpbin.exe" /exports C:\spike\EngineProbe\.build\release\EngineProbe.dll | Select-String "tt_engine"'
```

Expected: `EngineProbe.dll` exists and the four `tt_engine_*` names are listed. If they are missing, record it, then retry with the `@c` attribute instead of `@_cdecl` if the toolchain supports it, and record which one worked.

- [ ] **Step 3: write the .NET host.** `C:\spike\ProbeHost\ProbeHost.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
    <Nullable>enable</Nullable>
  </PropertyGroup>
</Project>
```

`C:\spike\ProbeHost\Program.cs`:

```csharp
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

unsafe
{
    var handle = Native.tt_engine_create("{\"dataDir\":\"C:\\\\spike\"}", &Native.OnMessage, null);
    Console.WriteLine($"handle != null: {handle != null}");
    Native.tt_engine_send(handle, "Join at https://zoom.us/j/123456789 please");
    Native.tt_engine_reply(handle, 42, "{\"ok\":true}");
    Thread.Sleep(1000); // let the asynchronous message arrive
    Native.tt_engine_destroy(handle);
    Console.WriteLine($"main thread id: {Environment.CurrentManagedThreadId}");
}

static unsafe partial class Native
{
    [LibraryImport("EngineProbe", StringMarshalling = StringMarshalling.Utf8)]
    internal static partial void* tt_engine_create(string configJson, delegate* unmanaged[Cdecl]<byte*, void*, void> onMessage, void* context);

    [LibraryImport("EngineProbe", StringMarshalling = StringMarshalling.Utf8)]
    internal static partial void tt_engine_send(void* engine, string commandJson);

    [LibraryImport("EngineProbe", StringMarshalling = StringMarshalling.Utf8)]
    internal static partial void tt_engine_reply(void* engine, ulong requestId, string replyJson);

    [LibraryImport("EngineProbe")]
    internal static partial void tt_engine_destroy(void* engine);

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvCdecl) })]
    internal static void OnMessage(byte* message, void* context)
    {
        var text = Marshal.PtrToStringUTF8((IntPtr)message);
        Console.WriteLine($"[thread {Environment.CurrentManagedThreadId}] {text}");
    }
}
```

- [ ] **Step 4: run it with the Swift runtime on PATH.**

```bash
ssh timetug-win '$rt = (Get-ChildItem "$env:LOCALAPPDATA\Programs\Swift\Runtimes\*\usr\bin" | Select-Object -Last 1).FullName; $env:PATH = "$rt;C:\spike\EngineProbe\.build\release;$env:PATH"; Set-Location C:\spike\ProbeHost; dotnet run -c Release'
```

Expected output, in this order (thread ids vary):
- `{"payload":{"config":"{\"dataDir\":\"C:\\\\spike\"}"},"type":"created","v":1}`
- `handle != null: True`
- `{"payload":{"link":"https://zoom.us/j/123456789"},"type":"detected","v":1}`
- `{"id":42,"payload":{"reply":"{\"ok\":true}"},"type":"replied","v":1}`
- `{"payload":{"thread":"background"},"type":"async","v":1}` with a different thread id from the main thread
- `main thread id: 1`

If the runtime folder is elsewhere, find it with `Get-ChildItem $env:LOCALAPPDATA\Programs\Swift -Recurse -Filter swiftCore.dll` and record the real path.

- [ ] **Step 5: measure the runtime that must ship.** Copy only `EngineProbe.dll` and the host to a clean folder, then add Swift runtime DLLs until it runs; record the minimal set and its size:

```bash
ssh timetug-win '$rt = (Get-ChildItem "$env:LOCALAPPDATA\Programs\Swift\Runtimes\*\usr\bin" | Select-Object -Last 1).FullName; "{0:N1} MB in the full runtime folder" -f ((Get-ChildItem $rt -Filter *.dll | Measure-Object Length -Sum).Sum / 1MB); Get-ChildItem $rt -Filter *.dll | Sort-Object Length -Descending | Select-Object -First 12 Name, @{n="MB";e={[math]::Round($_.Length/1MB,1)}}'
ssh timetug-win '& "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\*\bin\HostARM64\arm64\dumpbin.exe" /dependents C:\spike\EngineProbe\.build\release\EngineProbe.dll'
```

Follow `/dependents` recursively for each Swift DLL it names (Foundation, FoundationEssentials, FoundationInternationalization, `_FoundationICU`, swiftCore, swift_Concurrency, dispatch, BlocksRuntime, FoundationNetworking if URLSession is used) and sum their sizes. Record: the full folder size, the minimal set's size, and the largest single DLL.

### Task 4: Foundation behaviour probe

**Files:** on the VM only: `C:\spike\FoundationProbe\Package.swift`, `C:\spike\FoundationProbe\Sources\FoundationProbe\main.swift`.

**Interfaces:**
- Produces: a list of checks with PASS or FAIL and the observed value, for the findings document.

- [ ] **Step 1: write the probe.** `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FoundationProbe",
    targets: [.executableTarget(name: "FoundationProbe")]
)
```

`Sources/FoundationProbe/main.swift`:

```swift
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

func check(_ name: String, _ ok: Bool, _ detail: String) { print("\(ok ? "PASS" : "FAIL") \(name): \(detail)") }

// Time zones and DST (Denver springs forward on 2026-03-08 at 02:00 local).
let denver = TimeZone(identifier: "America/Denver")
check("IANA zone resolves", denver != nil, String(describing: denver?.identifier))
if let denver {
    var cal = Calendar(identifier: .gregorian); cal.timeZone = denver
    let before = cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 30))!
    let after = cal.date(byAdding: .hour, value: 1, to: before)!
    check("DST jump", cal.component(.hour, from: after) == 3, "01:30 + 1h -> \(cal.component(.hour, from: after)):\(cal.component(.minute, from: after))")
    check("Denver offset in July", denver.secondsFromGMT(for: cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!) == -6 * 3600, "\(denver.secondsFromGMT(for: cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!))")
}
check("current zone", true, TimeZone.current.identifier)

// ISO 8601 and JSON round trip.
let iso = ISO8601DateFormatter()
let parsed = iso.date(from: "2026-10-09T15:30:00Z")
check("ISO8601 parse", parsed != nil, String(describing: parsed))
struct Sample: Codable, Equatable { let title: String; let start: Date }
let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
let sample = Sample(title: "Design review ✅", start: parsed ?? Date(timeIntervalSince1970: 0))
let roundTrip = try? decoder.decode(Sample.self, from: encoder.encode(sample))
check("JSON round trip with emoji", roundTrip == sample, String(describing: roundTrip))

// Files in the user's local app data.
let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    .appendingPathComponent("TimeTugSpike", isDirectory: true)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let file = dir.appendingPathComponent("ledger.json")
let wrote = (try? Data("{\"ok\":true}".utf8).write(to: file, options: .atomic)) != nil
check("atomic write", wrote, file.path)
check("read back", (try? String(contentsOf: file, encoding: .utf8)) == "{\"ok\":true}", dir.path)

// HTTPS through URLSession (libcurl on Windows).
let done = DispatchSemaphore(value: 0)
var status = -1
URLSession.shared.dataTask(with: URL(string: "https://www.googleapis.com/discovery/v1/apis?name=calendar")!) { _, response, error in
    status = (response as? HTTPURLResponse)?.statusCode ?? -1
    if let error { print("  error: \(error)") }
    done.signal()
}.resume()
_ = done.wait(timeout: .now() + 20)
check("HTTPS GET", status == 200, "status \(status)")
check("proxy env", true, "HTTPS_PROXY=\(ProcessInfo.processInfo.environment["HTTPS_PROXY"] ?? "unset") (system proxy behaviour not tested in this spike)")
```

- [ ] **Step 2: run it.**

```bash
ssh timetug-win 'Set-Location C:\spike\FoundationProbe; swift run -c release 2>&1 | Select-Object -Last 20'
```

Expected: every line starts with `PASS`. A `FAIL` is a finding; copy the line as is.

### Task 5: Findings document and recommendation

**Files:**
- Create: `docs/spikes/2026-10-09-swift-on-windows.md`
- Modify: `docs/superpowers/plans/2026-10-09-windows-program-tracker.md` (phase S status, Now, Session log)

**Interfaces:**
- Consumes: the results of Tasks 1 to 4.
- Produces: the owner's go or no-go input for approach A.

- [ ] **Step 1: write the findings document** with exactly these sections:

```markdown
# Spike S: Swift on Windows (findings)

Date: <date>. Plan: `docs/superpowers/plans/2026-10-09-windows-spike-s.md`. Spec: section 9 of `docs/superpowers/specs/2026-10-09-windows-program-design.md`.

## Environment
<Windows build and architecture, Swift version and target, .NET SDK version, Visual Studio components>

## Package tests
| Package | Build | Passed | Failed | Skipped |
<one row each for CalendarConnectors, TimeTugCore, CalendarBridge>

### Failures by class
<class: test name: first error line, one line per failure; "none" if none>

## C interface from .NET
<exports found (yes/no, which attribute), the host output, thread behaviour>

## Runtime size
<full folder MB, minimal set with each DLL and MB, total>

## Foundation probe
<every PASS/FAIL line as printed>

## Recommendation
<one of: proceed with approach A as specified; proceed with listed changes (each change says which spec section it touches); revisit approach A (why)>
```

- [ ] **Step 2: update the tracker.** Set phase S to `done` (or `blocked` with the reason), check its items under Now, add the owner's decision item if not present, and append a Session log line with the date, the outcome and the next step.

- [ ] **Step 3: commit and open a pull request.**

```bash
git add docs/spikes/2026-10-09-swift-on-windows.md docs/superpowers/plans/2026-10-09-windows-program-tracker.md
git commit -m "Record Spike S findings: Swift on Windows

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git push -u origin HEAD
gh pr create --base master --title "Windows program: spec, tracker and Spike S findings" --body "Program design, the progress tracker, the Spike S plan and its findings. See docs/superpowers/plans/2026-10-09-windows-program-tracker.md.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

Use the attribution line for the model that actually ran the session.
