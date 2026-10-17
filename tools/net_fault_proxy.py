#!/usr/bin/env python3
"""TCP proxy that can break the connection on command, for reconnect tests.

    tools/net_fault_proxy.py --listen 8001 --target 127.0.0.1:8000 --control 8002

Clients connect to --listen instead of the server. Send one command per line to the
control port, e.g. `echo blackhole | nc -q1 127.0.0.1 8002`:

    normal     forward traffic (default); closes connections held by "blackhole"
    cut        close every proxied connection on both sides, like a server restart
    blackhole  stop reading and forwarding but keep the sockets open, like a pulled network
               cable (send buffers fill up; exact link loss needs iptables/tc); new
               connections are accepted and then left silent. A client that closes
               while blackholed is only noticed at the next "normal"
    refuse     close every proxied connection and refuse new ones until "normal"

Python 3.8+, standard library only, binds to 127.0.0.1 only.
"""

from __future__ import annotations

import argparse
import asyncio
import sys

mode = "normal"
connections: set[Pipe] = set()
# Set while traffic flows; "blackhole" clears it so forward() stops reading.
flowing: asyncio.Event | None = None


class Pipe:
    def __init__(self, client: asyncio.StreamWriter, server: asyncio.StreamWriter | None):
        self.client = client
        self.server = server

    def close(self) -> None:
        for writer in (self.client, self.server):
            if writer is not None and not writer.is_closing():
                writer.close()
        connections.discard(self)


async def forward(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, pipe: Pipe) -> None:
    try:
        while True:
            await flowing.wait()
            data = await reader.read(65536)
            if mode != "normal":
                return  # switched to blackhole/refuse while reading: drop it
            if not data:
                # Half-close: pass the EOF on and keep the other direction open.
                if writer.can_write_eof():
                    writer.write_eof()
                else:
                    pipe.close()
                return
            writer.write(data)
            await writer.drain()
    except (ConnectionError, OSError):
        pipe.close()


async def on_client(target_host: str, target_port: int, reader: asyncio.StreamReader,
                    writer: asyncio.StreamWriter) -> None:
    if mode == "refuse":
        writer.close()
        return
    pipe = Pipe(writer, None)
    connections.add(pipe)
    if mode == "blackhole":
        return  # accepted, but nothing ever reaches the server
    try:
        server_reader, server_writer = await asyncio.open_connection(target_host, target_port)
    except OSError:
        pipe.close()
        return
    if pipe not in connections or mode == "refuse":
        # "cut"/"refuse" arrived while connecting: the pipe is already gone.
        server_writer.close()
        pipe.close()
        return
    if mode == "blackhole":
        server_writer.close()  # keep the client side held and silent
        return
    pipe.server = server_writer
    await asyncio.gather(forward(reader, server_writer, pipe), forward(server_reader, writer, pipe))
    if mode == "normal":
        pipe.close()


async def on_control(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    global mode
    while line := await reader.readline():
        command = line.decode(errors="replace").strip()
        if command not in ("normal", "cut", "blackhole", "refuse"):
            writer.write(b"unknown command\n")
            await writer.drain()
            continue
        if command in ("cut", "refuse") or (command == "normal" and mode != "normal"):
            for pipe in list(connections):
                pipe.close()
        mode = "normal" if command == "cut" else command
        if mode == "normal":
            flowing.set()
        else:
            flowing.clear()
        print(f"[proxy] {command} ({len(connections)} open)", flush=True)
        writer.write(f"ok {mode}\n".encode())
        await writer.drain()
    writer.close()


async def main() -> None:
    global flowing
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--listen", type=int, default=8001)
    parser.add_argument("--target", default="127.0.0.1:8000")
    parser.add_argument("--control", type=int, default=8002)
    args = parser.parse_args()
    flowing = asyncio.Event()
    flowing.set()
    host, port = args.target.rsplit(":", 1)
    proxy = await asyncio.start_server(lambda r, w: on_client(host, int(port), r, w), "127.0.0.1", args.listen)
    control = await asyncio.start_server(on_control, "127.0.0.1", args.control)
    print(f"[proxy] 127.0.0.1:{args.listen} -> {args.target}, control on {args.control}", flush=True)
    async with proxy, control:
        await asyncio.gather(proxy.serve_forever(), control.serve_forever())


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(0)
