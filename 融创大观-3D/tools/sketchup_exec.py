#!/usr/bin/env python3
"""Send eval_ruby command to SketchUp MCP extension via TCP."""
import socket
import json
import sys


def send_ruby(code: str, host="127.0.0.1", port=9876, timeout=30) -> dict:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    sock.connect((host, port))
    request = {
        "jsonrpc": "2.0",
        "method": "tools/call",
        "params": {
            "name": "eval_ruby",
            "arguments": {"code": code},
        },
        "id": 1,
    }
    sock.sendall((json.dumps(request) + "\n").encode("utf-8"))
    chunks = []
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            break
        chunks.append(chunk)
        try:
            return json.loads(b"".join(chunks).decode("utf-8"))
        except json.JSONDecodeError:
            continue
    sock.close()
    raise RuntimeError("No valid JSON response")


if __name__ == "__main__":
    code = sys.argv[1] if len(sys.argv) > 1 else "Sketchup.active_model.title"
    result = send_ruby(code)
    print(json.dumps(result, ensure_ascii=False, indent=2))
