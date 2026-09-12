import Cocoa

struct SplitError: LocalizedError { let message: String; var errorDescription: String? { message } }
func run(_ name: String, _ args: [String]) throws -> Data {
    let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Tools/\(name)").path
    let path = FileManager.default.isExecutableFile(atPath: bundled) ? bundled : "/opt/homebrew/bin/\(name)"
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    let out = Pipe(); p.standardOutput = out
    let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    FileManager.default.createFile(atPath: log.path, contents: nil)
    let err = try FileHandle(forWritingTo: log); p.standardError = err
    defer { try? err.close(); try? FileManager.default.removeItem(at: log) }
    try p.run(); let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    if p.terminationStatus != 0 { throw SplitError(message: String(data: (try? Data(contentsOf: log)) ?? Data(), encoding: .utf8) ?? "处理失败") }
    return data
}
func duration(_ url: URL) throws -> Double {
    let data = try run("ffprobe", ["-v","error","-show_entries","format=duration:stream=codec_type","-of","json",url.path])
    let json = try JSONSerialization.jsonObject(with: data) as? [String:Any]
    guard let streams = json?["streams"] as? [[String:Any]], streams.contains(where: { $0["codec_type"] as? String == "video" }), let format = json?["format"] as? [String:Any], let s = format["duration"] as? String, let d = Double(s), d.isFinite, d > 0 else { throw SplitError(message:"无法读取视频时长，请选择完整的视频文件。") }
    return d
}
func parseTime(_ s: String) -> Double? {
    let parts = s.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
    guard (1...3).contains(parts.count) else { return nil }
    var value = 0.0
    for (i,p) in parts.enumerated() {
        guard let n = Double(p), n.isFinite, n >= 0, (i == 0 || n < 60), (i == parts.count-1 || n.rounded() == n) else { return nil }
        value = value * 60 + n
    }
    return value.isFinite ? value : nil
}
func stamp(_ s: Double) -> String { String(format:"%02d:%02d:%06.3f",Int(s)/3600,Int(s)/60%60,s.truncatingRemainder(dividingBy:60)) }
func split(_ input: URL, _ destination: URL, _ point: Double) throws -> (URL, Double) {
    let total = try duration(input)
    guard point > 0 && point < total else { throw SplitError(message:"拆分时间必须大于 0，且小于视频总时长。") }
    let fm = FileManager.default
    let folder = destination.appendingPathComponent("\(input.deletingPathExtension().lastPathComponent) · 拆分 \(UUID().uuidString.prefix(8))", isDirectory:true)
    try fm.createDirectory(at:folder,withIntermediateDirectories:false)
    var success = false
    defer { if !success { try? fm.removeItem(at:folder) } }
    let ext = input.pathExtension.lowercased()
    guard ["mp4","mov","mkv","webm","m4v","ts"].contains(ext) else { throw SplitError(message:"当前支持 MP4、MOV、MKV、WebM、M4V 和 TS。") }
    let list = folder.appendingPathComponent("segments.csv")
    _ = try run("ffmpeg",["-hide_banner","-v","error","-nostdin","-n","-i",input.path,"-map","0","-map_metadata","0","-map_chapters","-1","-c","copy","-f","segment","-segment_times",String(point),"-segment_start_number","1","-reset_timestamps","1","-segment_list",list.path,"-segment_list_type","csv",folder.appendingPathComponent("第%d段.\(ext)").path])
    let rows = try String(contentsOf:list,encoding:.utf8).split(separator:"\n")
    guard rows.count == 2 else { throw SplitError(message:"此时间之后没有可用的关键帧，无法拆成两段。请将拆分时间提前一些。") }
    let a = folder.appendingPathComponent("第1段.\(ext)"), b = folder.appendingPathComponent("第2段.\(ext)")
    _ = try duration(a); _ = try duration(b)
    let fields = rows[0].split(separator:",")
    let actual = Double(fields.last ?? "") ?? point
    try fm.removeItem(at:list)
    success = true; return (folder,actual)
}

class DropView: NSView {
    var receive: ((URL)->Void)?
    var available: (() -> Bool)?
    override init(frame:NSRect) { super.init(frame:frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder:NSCoder) { fatalError() }
    override func draggingEntered(_ sender:NSDraggingInfo) -> NSDragOperation { available?() == true && sender.draggingPasteboard.canReadObject(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) ? .copy : [] }
    override func performDragOperation(_ sender:NSDraggingInfo) -> Bool {
        guard available?() == true, let items = sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL], items.count == 1, let url = items.first else { return false }
        receive?(url); return true
    }
}
class App: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let fileLabel = NSTextField(labelWithString:"拖入一个视频到窗口，或点击选择")
    let info = NSTextField(labelWithString:"支持 MP4 / MOV / MKV / WebM / M4V / TS")
    let time = NSTextField(string:"00:10:00")
    let status = NSTextField(wrappingLabelWithString:"默认导出到原视频所在目录下的独立文件夹。")
    let choose = NSButton(title:"选择视频…",target:nil,action:nil)
    let start = NSButton(title:"拆成两份",target:nil,action:nil)
    let reveal = NSButton(title:"查看拆分结果",target:nil,action:nil)
    let spinner = NSProgressIndicator()
    var input: URL?; var result: URL?; var busy = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item); let sub = NSMenu(); sub.addItem(withTitle:"退出视频快拆",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"); item.submenu = sub; NSApp.mainMenu = menu
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:490),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title = "视频快拆 1.0.1"; window.delegate = self; window.center()
        let drop = DropView(frame:window.contentView!.bounds); drop.receive = { [weak self] url in self?.loadFile(url) }; drop.available = { [weak self] in self?.busy == false }; window.contentView = drop
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 20; stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:32),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-32),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:28)])
        let title = NSTextField(labelWithString:"一个视频，轻松拆成两份")
        title.font = NSFont(name:"FZJunHeiS-M-GB",size:26) ?? .systemFont(ofSize:26,weight:.semibold)
        let brand = NSImageView(); brand.image = NSImage(contentsOf:Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Brand.png")); brand.imageScaling = .scaleProportionallyUpOrDown
        brand.widthAnchor.constraint(equalToConstant:64).isActive = true; brand.heightAnchor.constraint(equalToConstant:64).isActive = true
        let header = NSStackView(views:[brand,title]); header.spacing = 16; stack.addArrangedSubview(header)
        let subtitle = NSTextField(labelWithString:"免转码 · 保留原画质 · 原文件不变"); subtitle.textColor = .secondaryLabelColor; stack.addArrangedSubview(subtitle)
        choose.target = self; choose.action = #selector(selectFile)
        fileLabel.lineBreakMode = .byTruncatingMiddle; fileLabel.maximumNumberOfLines = 1
        let row = NSStackView(views:[choose,fileLabel]); row.spacing = 14; stack.addArrangedSubview(row)
        info.textColor = .secondaryLabelColor; stack.addArrangedSubview(info)
        time.placeholderString = "时:分:秒 或总秒数"; time.font = .monospacedDigitSystemFont(ofSize:22,weight:.medium); time.widthAnchor.constraint(equalToConstant:190).isActive = true
        let timeRow = NSStackView(views:[NSTextField(labelWithString:"第一段时长"),time]); timeRow.spacing = 20; stack.addArrangedSubview(timeRow)
        let note = NSTextField(wrappingLabelWithString:"例如 00:10:00 表示前 10 分钟为第一段，其余为第二段。\n免转码会顺延到下一个关键帧，实际时长可能稍长。保留音轨和字幕，章节信息不保留。")
        note.textColor = .secondaryLabelColor; note.font = .systemFont(ofSize:12); stack.addArrangedSubview(note)
        start.target = self; start.action = #selector(begin); start.bezelStyle = .rounded; start.keyEquivalent = "\r"; start.isEnabled = false
        reveal.target = self; reveal.action = #selector(showResult); reveal.isHidden = true
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        let actions = NSStackView(views:[start,spinner,reveal]); actions.spacing = 16; stack.addArrangedSubview(actions)
        status.font = .systemFont(ofSize:12); stack.addArrangedSubview(status)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func setBusy(_ value: Bool) { busy = value; choose.isEnabled = !value; time.isEnabled = !value; start.isEnabled = !value && input != nil; if value { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) } }
    @objc func selectFile() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFile(url)
    }
    func loadFile(_ url: URL) {
        guard !busy else { return }
        setBusy(true); input = nil; result = nil; reveal.isHidden = true; fileLabel.stringValue = url.lastPathComponent; status.stringValue = "正在读取视频信息…"
        DispatchQueue.global(qos:.userInitiated).async {
            do { let d = try duration(url); DispatchQueue.main.async { self.input = url; self.info.stringValue = "总时长 \(stamp(d))"; self.time.stringValue = stamp(d/2); self.status.stringValue = "默认导出到原目录，点击拆成两份即可。"; self.setBusy(false) } }
            catch { DispatchQueue.main.async { self.status.stringValue = error.localizedDescription; self.setBusy(false) } }
        }
    }
    @objc func begin() {
        guard let input = input else { return }
        guard let t = parseTime(time.stringValue), t > 0 else { status.stringValue = "请输入有效时间，例如 00:10:00 或 600。"; return }
        let dir = input.deletingLastPathComponent()
        setBusy(true); reveal.isHidden = true; status.stringValue = "正在直接复制音视频数据… 大文件速度取决于磁盘读写。"
        DispatchQueue.global(qos:.userInitiated).async {
            do { let (folder,actual) = try split(input,dir,t); DispatchQueue.main.async { self.result = folder; self.reveal.isHidden = false; self.status.stringValue = "已完成两段视频。第一段结束位置约 \(stamp(actual))。"; self.setBusy(false) } }
            catch { DispatchQueue.main.async { self.status.stringValue = "拆分失败：\(error.localizedDescription.prefix(320))"; self.setBusy(false) } }
        }
    }
    @objc func showResult() { if let result = result { NSWorkspace.shared.open(result) } }
    func windowShouldClose(_ sender:NSWindow) -> Bool { !busy }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply { busy ? .terminateCancel : .terminateNow }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { true }
}
if CommandLine.arguments.count == 5 && CommandLine.arguments[1] == "--split" {
    do { guard let t = parseTime(CommandLine.arguments[4]) else { throw SplitError(message:"无效时间") }; let r = try split(URL(fileURLWithPath:CommandLine.arguments[2]),URL(fileURLWithPath:CommandLine.arguments[3]),t); print(r.0.path); print(r.1) } catch { fputs("\(error.localizedDescription)\n",stderr); exit(1) }
} else {
    let app = NSApplication.shared; let delegate = App(); app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
}
