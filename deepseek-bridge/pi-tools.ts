import { Type } from "typebox";
import { spawn } from "node:child_process";
import path from "node:path";

// Only explicit read-only tools are registered. No built-in bash/read/write tools.
export default function (pi: any) {
  // Bootstrap native history without replaying turns or making model calls.
  // These messages live only in this --no-session process. Context hooks run
  // on every tool round, so the seed remains available throughout the turn.
  let history: any[] = [];
  let systemText = "";
  pi.registerCommand("atoll-context", {
    description: "Restore Atoll user-visible history without running the model",
    handler: async (args: string) => {
      const messages = JSON.parse(args);
      if (!Array.isArray(messages)) throw new Error("Invalid Atoll context");
      systemText = messages.filter(m => m.role === "system").map(m => m.content).join("\n\n");
      history = messages.filter(m => m.role !== "system").map(m => {
        const content = [{type: "text", text: m.content}, ...(m.images || [])];
        if (m.role === "user") return {role: "user", content, timestamp: Date.now()};
        if (m.role !== "assistant") throw new Error("Invalid Atoll role");
        return {role: "assistant", content, api: "openai-completions",
          provider: "atoll-deepseek", model: "atoll-restored-history", stopReason: "stop",
          usage: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0,
            cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0}}, timestamp: Date.now()};
      });
    },
  });
  pi.on("context", async (event: any) => ({messages: [...history, ...event.messages]}));
  pi.on("before_agent_start", async (event: any) => systemText
    ? {systemPrompt: event.systemPrompt + "\n\n" + systemText} : undefined);
  const specs = [
    ["web_search", "Search public web pages. Cite actual result URLs.", "query"],
    ["read_webpage", "Read a public web page. Local/private network URLs are blocked.", "url"],
    ["list_files", "List a local directory only after the user approves the exact path in a Mac dialog.", "path"],
    ["read_file", "Read a UTF-8 text file only after user approval. File contents are sent to DeepSeek. No binary or PDF support.", "path"],
  ];
  pi.registerCommand("atoll-tools", {
    description: "Enable or disable Atoll read-only tools",
    handler: async (args: string) => { pi.setActiveTools(args.trim() === "on" ? specs.map(s => s[0]) : []); },
  });
  for (const [name, description, argument] of specs) {
    pi.registerTool({
      name, label: name, description,
      parameters: Type.Object({[argument]: Type.String()}),
      async execute(_id: string, params: any, signal: AbortSignal) {
        if (signal?.aborted) throw new Error("Cancelled");
        const env = {PATH: "/usr/bin:/bin:/usr/sbin:/sbin", HOME: process.env.HOME!, LANG: "en_US.UTF-8"};
        const child = spawn("/usr/bin/python3", [path.join(process.env.ATOLL_BRIDGE_DIR!, "tool_runner.py"), name],
          {env, stdio: ["pipe", "pipe", "pipe"]});
        let output = "";
        let oversized = false;
        child.stdout.on("data", data => {
          output += data.toString();
          if (output.length > 100000) { oversized = true; child.kill(); }
        });
        const abort = () => child.kill("SIGTERM");
        signal?.addEventListener("abort", abort, {once:true});
        const timer = setTimeout(abort, 110000);
        try {
          const code = await new Promise<number|null>((resolve,reject) => {
            child.on("error",reject);
            child.on("close",resolve);
            child.stdin.on("error",()=>{});
            child.stdin.end(JSON.stringify(params));
          });
          if (signal?.aborted) throw new Error("Cancelled");
          if (code !== 0 || oversized) return {content:[{type:"text",text:"Tool failed or was cancelled."}],details:{error:true},isError:true};
          return {content:[{type:"text",text:output}],details:{}};
        } finally { clearTimeout(timer); signal?.removeEventListener("abort",abort); }
      },
    });
  }
}
