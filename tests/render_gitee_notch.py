#!/usr/bin/env python3
"""Native SwiftUI rendering regression, with synthetic store data and no network.
Extracts the exact old/new production GINotchView (not a redrawn mock UI).
The full application is built and smoke-tested separately.
"""
import os, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
OUT = Path(os.environ['OUT']) / 'notch-rendering'
OUT.mkdir(parents=True, exist_ok=True)
base = 'f8f0b6df395394d69d066ede0da58eeedaef06d9'
path = 'DynamicIsland/ToolIsleFeatures/Gitee/GIViews.swift'
old = subprocess.check_output(['git','show',f'{base}:{path}'],cwd=ROOT).decode()
new = (ROOT/path).read_text()
def extract(s):
    return s[s.index('struct GINotchView: View {'):s.index('struct GIReaderRootView: View {')]
views = 'import AppKit\nimport SwiftUI\n' + extract(old).replace('struct GINotchView:', 'struct LegacyGINotchView:') + extract(new)
(OUT/'Views.swift').write_text(views)
(OUT/'Harness.swift').write_text(r'''
import AppKit
import SwiftUI

@MainActor final class GIStore: ObservableObject {
    static let shared = GIStore()
    @Published var account: GIUser?
    @Published var demoMode = false
    @Published var isConnecting = false
    @Published var connectionError: String?
    @Published var selectedRepositories: [GIRepository] = []
    @Published var items: [GIListItem] = []
    @Published var loadingList = false
    @Published var listFailures: [GIRepositoryFailure] = []
    @Published var query = ""
    @Published var repositoryFilter = ""
    @Published var stateFilter = "all"
    var filteredItems: [GIListItem] {
        items.filter { (query.isEmpty || $0.issue.title.contains(query)) &&
            (repositoryFilter.isEmpty || $0.route.repository == repositoryFilter) &&
            (stateFilter == "all" || $0.issue.state == stateFilter) }
    }
    func activate() {}
    func refreshIssues(reset: Bool) {}
    func retryFailedRepositories() {}
    func configure(_ state: String) {
        account = GIUser(id:-1,login:"fixture",name:"合成测试账户")
        demoMode = false; isConnecting = false; connectionError = nil
        selectedRepositories = [GIRepository(id:1,full_name:"fixture/project",name:"Project",description:nil,html_url:nil)]
        loadingList = false; listFailures = []; query = ""; repositoryFilter = ""; stateFilter = "all"
        items = (1...3).map { n in
            let route = GIIssueRoute(repository:"fixture/project",number:"ITest\(n)")
            let issue = GIIssue(id:Int64(n),number:route.number,title:["关联 Issue 正文阅读","修复外接显示器显示位置","返回后恢复阅读位置"][n-1],state:"open",body:nil,html_url:nil,user:nil,updated_at:nil,comments:0)
            return GIListItem(route:route,issue:issue)
        }
        switch state {
        case "no-account": account=nil; items=[]; selectedRepositories=[]
        case "connecting": account=nil; items=[]; isConnecting=true
        case "auth-error": account=nil; items=[]; connectionError="账户验证失败，请检查令牌。"
        case "no-project": selectedRepositories=[]; items=[]
        case "loading": items=[]; loadingList=true
        case "error": items=[]; listFailures=[GIRepositoryFailure(repository:"fixture/project",error:GIServiceError.missing)]
        case "empty": items=[]
        case "filtered": query="no-match"
        case "partial": listFailures=[GIRepositoryFailure(repository:"fixture/other",error:GIServiceError.forbidden)]
        default: break
        }
    }
}
@MainActor final class GIReaderWindowController {
    static let shared=GIReaderWindowController()
    func show(route:GIIssueRoute?=nil) {}
}
@MainActor final class GISettingsNavigation {
    static let shared=GISettingsNavigation()
    func open() {}
}
@main struct RenderTests {
    @MainActor static func main() throws {
        let out=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        var records:[[String:Any]]=[]
        let states=["ready","no-account","connecting","auth-error","no-project","loading","error","empty","filtered","partial"]
        for legacy in [true,false] {
            for scheme in [ColorScheme.light,ColorScheme.dark] {
                for width in [360,560] {
                    for state in (legacy ? ["ready","filtered"] : states) {
                        GIStore.shared.configure(state)
                        let appearance=NSAppearance(named:scheme == .light ? .aqua : .darkAqua)!
                        NSApp.appearance=appearance
                        let root=AnyView(Group {
                            if legacy { LegacyGINotchView() } else { GINotchView() }
                        }.environment(\.colorScheme,scheme).frame(width:CGFloat(width),height:190).background(Color.black))
                        let host=NSHostingView(rootView:root)
                        let window=NSWindow(contentRect:NSRect(x:100,y:100,width:width,height:190),styleMask:.borderless,backing:.buffered,defer:false)
                        window.isReleasedWhenClosed=false; window.appearance=appearance; window.contentView=host
                        window.makeKeyAndOrderFront(nil)
                        RunLoop.main.run(until:Date().addingTimeInterval(0.25))
                        host.layoutSubtreeIfNeeded()
                        guard let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds) else { fatalError("snapshot unavailable") }
                        host.cacheDisplay(in:host.bounds,to:rep)
                        let filename="\(legacy ? "before" : "after")-\(scheme == .light ? "light" : "dark")-\(width)-\(state).png"
                        try rep.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(filename))
                        let scale=Double(rep.pixelsWide)/Double(width)
                        func bright(_ x0:Int,_ y0:Int,_ x1:Int,_ y1:Int)->Int {
                            var n=0
                            for y in Int(Double(y0)*scale)..<min(rep.pixelsHigh,Int(Double(y1)*scale)) {
                                for x in Int(Double(x0)*scale)..<min(rep.pixelsWide,Int(Double(x1)*scale)) {
                                    if let c=rep.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),
                                       min(c.redComponent,c.greenComponent,c.blueComponent)>0.45 { n += 1 }
                                }
                            }
                            return n
                        }
                        let header=bright(10,8,200,36), body=bright(10,40,width-12,155), footer=bright(width-170,158,width-12,187)
                        records.append(["file":filename,"header_bright_pixels":header,"body_bright_pixels":body,"footer_bright_pixels":footer,"width":rep.pixelsWide,"height":rep.pixelsHigh])
                        if !legacy {
                            precondition(header>20,"invisible header: \(filename)")
                            precondition(body>20,"invisible data/state: \(filename)")
                            precondition(footer>20,"invisible reader action: \(filename)")
                            precondition(abs(Double(rep.pixelsHigh)/scale-190)<2,"unexpected height")
                        }
                        window.orderOut(nil);window.contentView=nil;window.close()
                    }
                }
            }
        }
        try JSONSerialization.data(withJSONObject:records,options:.prettyPrinted).write(to:out.appendingPathComponent("render-results.json"))
        print("PASS: 40 new production-view snapshots; header/body/footer visible in both appearances, 10 states, 2 widths. 8 legacy comparison snapshots. All data synthetic.")
    }
}
''')
subprocess.run(['swiftc','-swift-version','5',str(ROOT/'DynamicIsland/ToolIsleFeatures/Gitee/GICore.swift'),str(OUT/'Views.swift'),str(OUT/'Harness.swift'),'-o',str(OUT/'render-test')],check=True)
subprocess.run([str(OUT/'render-test'),str(OUT)],check=True)
# Test executables/source extracts are not application deliverables.
for name in ('render-test','Views.swift','Harness.swift'):
    (OUT/name).unlink()
