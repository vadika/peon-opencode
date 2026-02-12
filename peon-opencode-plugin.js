import { spawn } from "node:child_process"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"

const expandHome = (value) => {
  if (!value) return value
  if (value.startsWith("~/")) {
    return path.join(os.homedir(), value.slice(2))
  }
  return value
}

const getHookCommand = () => {
  const envCmd = process.env.PEON_HOOK_CMD
  if (envCmd && envCmd.trim()) return expandHome(envCmd.trim())
  const peonDir = process.env.PEON_DIR
    ? expandHome(process.env.PEON_DIR)
    : path.join(os.homedir(), ".opencode", "hooks", "peon-ping")
  return path.join(peonDir, "peon-opencode.sh")
}

const debugEnabled = () => process.env.PEON_DEBUG === "1"

const debugLogPath = () => {
  const custom = process.env.PEON_DEBUG_LOG
  if (custom && custom.trim()) return expandHome(custom.trim())
  return path.join(os.tmpdir(), "peon-opencode.log")
}

const debug = (message) => {
  if (!debugEnabled()) return
  const line = `[${new Date().toISOString()}] ${message}\n`
  try {
    fs.appendFileSync(debugLogPath(), line)
  } catch {
    // ignore
  }
}

const emitHook = (payload) => {
  const cmd = getHookCommand()
  if (!fs.existsSync(cmd)) {
    debug(`hook not found: ${cmd}`)
    return
  }
  debug(`spawn hook: ${cmd}`)
  const child = spawn(cmd, [], { stdio: ["pipe", "ignore", "ignore"] })
  child.on("error", (err) => debug(`hook error: ${err.message}`))
  child.on("exit", (code) => debug(`hook exit: ${code}`))
  child.stdin.write(JSON.stringify(payload))
  child.stdin.end()
}

const toEventPayload = (event, override = {}) => {
  return { payload: event, ...override }
}

export const PeonOpencodePlugin = async () => {
  return {
    event: async ({ event }) => {
      if (!event || !event.type) return

      const type = event.type
      if (
        type === "session.created" ||
        type === "session.completed" ||
        type === "session.idle"
      ) {
        debug(`event: ${type}`)
        emitHook(toEventPayload(event))
        return
      }

      if (type === "session.error") {
        debug(`event: ${type}`)
        emitHook(toEventPayload(event, { event: "error" }))
        return
      }

      if (type === "permission.asked") {
        debug(`event: ${type}`)
        emitHook(toEventPayload(event, { event: "permission_request" }))
      }
    },
    "tool.execute.after": async (input, output) => {
      if (!input || !output) return
      const failed = Boolean(output.error)
      if (!failed) return
      debug(`tool error: ${input.tool || "unknown"}`)
      emitHook({
        event: "tool_error",
        payload: {
          type: "tool_error",
          properties: {
            tool: input.tool,
            directory: input.cwd,
          },
        },
        cwd: input.cwd,
      })
    },
  }
}
