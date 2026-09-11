#!/usr/bin/env python3
import json
import sys
import agent_tools

if __name__ == '__main__':
    try:
        arguments=json.loads(sys.stdin.read(16000))
        print(agent_tools.execute(sys.argv[1],arguments,{'file_access':'ask','tools':True}))
    except Exception:
        print(json.dumps({'error':'Tool failed, access denied, or unsupported content. Do not claim success or retry denied access without a new user request.'}))
