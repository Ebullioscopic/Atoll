// ToolIsle Gitee reader. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI
import WebKit

struct GIWebReader: NSViewRepresentable {
    let visit: GIVisit
    let page: GIPage
    @ObservedObject var store: GIStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.userContentController.add(context.coordinator, name: "giReader")
        if let url = Bundle.main.url(forResource: "gitee-markdown", withExtension: "js"),
           let library = try? String(contentsOf: url, encoding: .utf8) {
            config.userContentController.addUserScript(WKUserScript(source: library, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        config.userContentController.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.shell, baseURL: URL(string: "https://toolisle.invalid/reader"))
        return webView
    }
    func updateNSView(_ webView: WKWebView, context: Context) {
        let signature = "\(visit.id)-\(page.revision)-\(store.loadRemoteImages)-\(store.textScale)"
        guard context.coordinator.signature != signature else { return }
        context.coordinator.signature = signature
        var base = visit.route.url
        if let raw = page.issue.html_url, let canonical = URL(string: raw),
           canonical.scheme == "https", GIIssueLinks.hosts.contains(canonical.host?.lowercased() ?? ""),
           canonical.user == nil, canonical.password == nil { base = canonical }
        let payload: [String: Any] = [
            "visit": visit.id.uuidString, "base": base.absoluteString,
            "title": page.issue.title, "state": page.issue.stateTitle,
            "author": page.issue.user?.displayName ?? "", "updated": page.issue.updated_at ?? "",
            "body": page.issue.body ?? "", "fragment": visit.anchorHandled ? "" : (visit.fragment ?? ""),
            "scrollY": visit.scrollY, "images": store.loadRemoteImages, "scale": store.textScale,
            "comments": page.comments.map { ["id": String($0.id), "body": $0.body ?? "", "author": $0.user?.displayName ?? "", "date": $0.created_at ?? ""] }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            context.coordinator.pending = data.base64EncodedString()
            context.coordinator.render(webView)
        }
    }
    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "giReader")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let store: GIStore
        var signature = ""
        var pending: String?
        var ready = false
        init(store: GIStore) { self.store = store }
        func render(_ view: WKWebView) {
            guard ready, let pending else { return }
            self.pending = nil
            // Base64 is emitted by JSONSerialization, not untrusted executable interpolation.
            view.evaluateJavaScript("window.GIReader.renderBase64('\(pending)')") { [weak self] _, error in
                if error != nil { self?.store.notice = "Markdown 渲染失败，可在 Gitee 中打开原文。" }
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; render(webView) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            store.notice = "阅读视图未能加载，请重新打开此 Issue。"
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            ready = false; signature = ""
            store.notice = "阅读进程已重启，请刷新当前 Issue。"
            webView.loadHTMLString(GIWebReader.shell, baseURL: URL(string: "https://toolisle.invalid/reader"))
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.webView?.url?.host == "toolisle.invalid",
                  let data = message.body as? [String: Any], let kind = data["kind"] as? String,
                  let idString = data["visit"] as? String, let id = UUID(uuidString: idString),
                  store.visit?.id == id else { return }
            switch kind {
            case "scroll": store.snapshot(id: id, y: (data["y"] as? Double) ?? 0)
            case "link":
                if let href = data["href"] as? String, href.count < 16384 { store.handleLink(href, visitID: id) }
            case "ready":
                store.snapshot(id: id, y: (data["y"] as? Double) ?? 0, anchorHandled: true)
                if data["anchorFound"] as? Bool == false {
                    store.notice = "未能定位到链接指定的段落或评论。Issue 已打开，可使用“在 Gitee 中打开”查看原定位。"
                }
                if ProcessInfo.processInfo.arguments.contains("--gitee-reader-smoke"), store.demoMode, let webView = message.webView {
                    GISmokeCheck.shared.didRender(webView, store: store)
                }
            case "copy":
                if let text = data["text"] as? String { GIPasteboard.copy(text) }
            case "images": store.loadRemoteImages = true
            default: break
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            // The only document this WebView may display is our local HTML shell.
            if !ready, navigationAction.navigationType == .other,
               url?.absoluteString == "about:blank" || url?.host == "toolisle.invalid" {
                decisionHandler(.allow); return
            }
            if navigationAction.navigationType == .linkActivated, let url, let id = store.visit?.id {
                store.handleLink(url.absoluteString, visitID: id)
            }
            decisionHandler(.cancel)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, let id = store.visit?.id { store.handleLink(url.absoluteString, visitID: id) }
            return nil
        }
    }

    static let shell = #"""
    <!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="referrer" content="no-referrer">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src https://gitee.com https://foruda.gitee.com https://images.gitee.com data:; connect-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'">
    <style>
    :root {color-scheme:light dark;--base:14px;--line:color-mix(in srgb,CanvasText 12%,transparent);--panel:color-mix(in srgb,CanvasText 4%,Canvas);}
    * {box-sizing:border-box} html {background:Canvas;color:CanvasText;overflow-x:hidden;overflow-anchor:none}
    body {margin:0;padding:26px 32px 60px;font:var(--base)/1.75 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;word-break:break-word}
    main {max-width:900px;margin:auto} h1 {font-size:1.55em;line-height:1.4;margin:0 0 10px;font-weight:650} h2 {font-size:1.3em} h3 {font-size:1.12em} h4,h5,h6 {font-size:1em}
    h2,h3,h4 {margin:1.5em 0 .6em;scroll-margin-top:20px} p {margin:.65em 0 1em} a {color:LinkText;text-decoration:underline;text-decoration-thickness:1px;text-underline-offset:3px;cursor:pointer}
    a:hover {text-decoration-thickness:2px} a:focus-visible,button:focus-visible {outline:2px solid Highlight;outline-offset:3px;border-radius:3px}
    .meta {color:GrayText;font-size:.85em;margin-bottom:22px;display:flex;gap:10px;flex-wrap:wrap}.state {border:1px solid var(--line);border-radius:5px;padding:0 7px}
    pre {position:relative;background:var(--panel);border:1px solid var(--line);border-radius:9px;padding:34px 14px 14px;overflow:auto;max-width:100%;line-height:1.55}
    code {font: .9em/1.6 ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--panel);border-radius:4px;padding:2px 4px}
    pre code {padding:0;background:none;white-space:pre;word-break:normal} .copy {position:absolute;right:8px;top:6px;font-size:11px;padding:2px 7px}
    button {font:inherit;color:CanvasText;background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:4px 10px;cursor:pointer}
    blockquote {margin:16px 0;border-left:3px solid var(--line);padding:1px 16px;color:GrayText} ul,ol {padding-left:24px} li {margin:5px 0}
    .table-scroll {overflow:auto;margin:18px 0;max-width:100%;border:1px solid var(--line);border-radius:8px} table {border-collapse:collapse;min-width:100%;font-size:.93em}
    th,td {border-bottom:1px solid var(--line);padding:9px 12px;text-align:left;min-width:90px} th {background:var(--panel)} tr:last-child td {border-bottom:0}
    img {max-width:100%;height:auto;border-radius:6px;display:block;margin:12px 0} .image-placeholder {display:block;width:100%;min-height:90px;padding:20px;text-align:center;color:GrayText;margin:12px 0}
    hr {border:0;border-top:1px solid var(--line);margin:28px 0}.comments-title {font-size:1.05em;margin-top:36px;border-top:1px solid var(--line);padding-top:22px}
    .comment {border-bottom:1px solid var(--line);padding:18px 0;scroll-margin-top:20px}.comment .meta {margin-bottom:9px}.comment-body {font-size:.97em}
    .footnote {font-size:.85em;color:GrayText}.checkbox {margin-right:5px} .error {border:1px solid var(--line);padding:20px;border-radius:8px}
    @media(max-width:520px) {body {padding:20px 20px 50px} h1 {font-size:1.4em}}
    @media(prefers-reduced-motion:reduce) {* {scroll-behavior:auto!important}}
    </style></head><body><main id="content"><p class="footnote">正在准备阅读内容…</p></main></body></html>
    """#

    static let script = #"""
    (() => {
      'use strict';
      let current = null, touched = false, sequence = 0;
      const post = (kind, extra={}) => {
        if (current) window.webkit.messageHandlers.giReader.postMessage({kind,visit:current.visit,...extra});
      };
      const snapshot = () => post('scroll',{y:window.scrollY});
      let frame = 0;
      window.addEventListener('scroll',()=>{if (!frame) frame=requestAnimationFrame(()=>{frame=0;snapshot()});},{passive:true});
      for (const name of ['wheel','touchstart','pointerdown','keydown']) window.addEventListener(name,()=>{touched=true;},{passive:true});
      const node = (tag,text,cls) => {const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e};
      const safeURL = (raw,base) => {
        try {const u=new URL(raw,base);if(u.username||u.password)return null;
          if(!['http:','https:','mailto:'].includes(u.protocol))return null;
          for(const key of u.searchParams.keys())if(['access_token','token','authorization','private_token'].includes(key.toLowerCase()))return null;
          return u;
        } catch {return null}
      };
      function markdown(source,base,images) {
        const box=node('div');
        if(!window.GIText) {box.textContent=source;return box}
        if(source.length>1000000){box.className='error';box.textContent='正文过长，请在 Gitee 中打开完整内容。';return box}
        // Template contents are inert: no image request may start before the opt-in check.
        const template=document.createElement('template');
        template.innerHTML=GIText.render(source);
        const fragment=template.content;
        for(const e of fragment.querySelectorAll('input')) {
          const check=node('span',e.hasAttribute('checked')?'☑':'☐','checkbox');e.replaceWith(check);
        }
        for(const e of fragment.querySelectorAll('a')) {
          const raw=e.getAttribute('href')||'';const u=safeURL(raw,base);
          if(!u){e.removeAttribute('href');e.title='此链接不可打开';continue}
          e.setAttribute('href',u.href);e.title=u.href;e.rel='noreferrer noopener';e.removeAttribute('target');
        }
        for(const e of fragment.querySelectorAll('img')) {
          const raw=e.getAttribute('src')||'';const alt=e.getAttribute('alt')||'图片';
          const data=/^data:image\/(png|jpeg|gif|webp);base64,[a-z0-9+/=]+$/i.test(raw)&&raw.length<2000000;
          const u=safeURL(raw,base);
          const trusted=u&&u.protocol==='https:'&&['gitee.com','foruda.gitee.com','images.gitee.com'].includes(u.hostname)&&(!u.port||u.port==='443');
          if(images&&(trusted||data)) {
            e.src=data?raw:u.href;e.referrerPolicy='no-referrer';
            e.addEventListener('error',()=>{e.replaceWith(node('p','图片未能加载或需要网页登录。请在 Gitee 打开。','footnote'))},{once:true});
          } else {
            const button=node('button',trusted||data?'点击加载 Gitee 图片 · '+alt:'在浏览器查看外部图片 · '+alt,'image-placeholder');
            if(trusted||data)button.addEventListener('click',()=>{snapshot();post('images')});
            else if(u)button.addEventListener('click',()=>{snapshot();post('link',{href:u.href})});
            else {button.disabled=true;button.textContent='无法显示此图片 · '+alt}
            e.replaceWith(button);
          }
        }
        for(const e of fragment.querySelectorAll('table')) {const wrapper=node('div',undefined,'table-scroll');e.replaceWith(wrapper);wrapper.append(e)}
        for(const pre of fragment.querySelectorAll('pre')) {
          const code=pre.querySelector('code');if(!code)continue;
          const button=node('button','复制','copy');button.title='复制代码';
          button.addEventListener('click',()=>{post('copy',{text:code.textContent});button.textContent='已复制';setTimeout(()=>{button.textContent='复制'},1200)});
          pre.prepend(button);
        }
        box.append(fragment);
        return box;
      }
      function render(data) {
        const stamp=++sequence;
        current=data;touched=false;
        document.documentElement.style.setProperty('--base',(14*data.scale)+'px');
        const root=document.getElementById('content');root.replaceChildren();
        root.append(node('h1',data.title));
        const meta=node('div',undefined,'meta');meta.append(node('span',data.state,'state'),node('span',data.author),node('span',data.updated.replace('T',' ').slice(0,16)));root.append(meta);
        if(!window.GIText)root.append(node('p','Markdown 组件未能加载，以下以纯文本显示；可在 Gitee 打开原文。','error'));
        root.append(markdown(data.body,data.base,data.images));
        root.append(node('h2','评论 · '+data.comments.length,'comments-title'));
        if(!data.comments.length)root.append(node('p','当前未加载到评论。','footnote'));
        for(const comment of data.comments) {
          const article=node('section',undefined,'comment');article.id='note_'+comment.id;
          for(const prefix of ['issuecomment-','comment-','comment_']) {const alias=node('span');alias.id=prefix+comment.id;article.append(alias)}
          const info=node('div',undefined,'meta');info.append(node('strong',comment.author),node('span',comment.date.replace('T',' ').slice(0,16)));article.append(info);
          const body=markdown(comment.body,data.base,data.images);body.className='comment-body';article.append(body);root.append(article);
        }
        const slugs=new Map();
        for(const h of root.querySelectorAll('h1,h2,h3,h4,h5,h6')) {
          const slug=h.textContent.trim().toLowerCase().replace(/[^\p{L}\p{N}\s_-]/gu,'').replace(/\s+/g,'-')||'section';
          const n=slugs.get(slug)||0;slugs.set(slug,n+1);h.id=slug+(n?'-'+n:'');
        }
        let anchor=null;
        if(data.fragment)anchor=document.getElementById(data.fragment)||document.getElementById(data.fragment.replace(/^user-content-/,''));
        const restore=()=>{
          if(sequence!==stamp||touched)return;
          if(anchor)anchor.scrollIntoView({block:'start',behavior:'auto'});
          else window.scrollTo(0,data.scrollY||0);
        };
        requestAnimationFrame(()=>requestAnimationFrame(()=>{
          restore();post('ready',{y:window.scrollY,anchorFound:data.fragment?!!anchor:true});
        }));
        for(const img of root.querySelectorAll('img'))img.addEventListener('load',restore,{once:true});
      }
      document.addEventListener('click',event=>{
        const link=event.target.closest('a[href]');if(!link)return;
        event.preventDefault();event.stopPropagation();snapshot();post('link',{href:link.getAttribute('href')});
      });
      window.GIReader={
        renderBase64(value){const bytes=Uint8Array.from(atob(value),c=>c.charCodeAt(0));render(JSON.parse(new TextDecoder().decode(bytes)))},
        inspect(){return {title:document.querySelector('h1')?.textContent||'',y:window.scrollY,linkCount:document.querySelectorAll('a[href]').length,tableCount:document.querySelectorAll('table').length,codeCount:document.querySelectorAll('pre code').length,commentCount:document.querySelectorAll('.comment').length,hasRenderer:!!window.GIText,imageCount:document.querySelectorAll('img').length}},
        followDemoLink(){window.scrollTo(0,600);snapshot();const a=[...document.querySelectorAll('a[href]')].find(a=>a.href.includes('/IDEMOB#note_202'));if(a)a.click();return !!a}
      };
    })();
    """#
}

/// Opt-in CI test harness. Only synthetic fixtures are used; normal launches never enter it.
@MainActor
private final class GISmokeCheck {
    static let shared = GISmokeCheck()
    private var stage = 0
    private var report: [String: Any] = [:]
    func didRender(_ webView: WKWebView, store: GIStore) {
        guard store.demoMode, stage < 3 else { return }
        if stage == 0, store.visit?.route == GIStore.demoA {
            stage = 1
            webView.evaluateJavaScript("GIReader.inspect()") { [weak self, weak webView] value, _ in
                self?.report["initial"] = value
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { webView?.evaluateJavaScript("GIReader.followDemoLink()") }
            }
        } else if stage == 1, store.visit?.route == GIStore.demoB {
            stage = 2
            webView.evaluateJavaScript("({...GIReader.inspect(),anchorTop:document.getElementById('note_202').getBoundingClientRect().top})") { [weak self] value, _ in
                self?.report["linked"] = value
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { store.moveHistory(-1) }
            }
        } else if stage == 2, store.visit?.route == GIStore.demoA {
            stage = 3
            webView.evaluateJavaScript("GIReader.inspect()") { [weak self] value, _ in
                guard let self else { return }
                self.report["restored"] = value
                self.report["selected_repository_unchanged"] = store.selectedRepositories.map(\.path) == [GIStore.demoA.repository]
                self.report["selected_issue_unchanged"] = store.selectedListID == GIStore.demoA
                self.report["synthetic_fixtures_only"] = true
                guard let path = ProcessInfo.processInfo.environment["TOOLISLE_GITEE_SMOKE_RESULT"],
                      let data = try? JSONSerialization.data(withJSONObject: self.report, options: [.prettyPrinted, .sortedKeys]) else { return }
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        }
    }
}
