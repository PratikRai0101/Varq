#!/usr/bin/env python3
"""Loopback-only HTTP/HTTPS observer and original adversarial EPUB generator.

Standard library only. The tiny test font is an original rectangular A glyph,
not a redistributed system/commercial font. Nothing here ships in the app.
"""
import argparse
import base64
import http.server
import json
from pathlib import Path
import ssl
import threading
import time
from urllib.parse import urlsplit
import zipfile

PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")
FONT = base64.b64decode("AAEAAAAKAIAAAwAgT1MvMkUhRDUAAAEoAAAAYGNtYXAADACUAAABkAAAADRnbHlmal1qWwAAAcwAAAA0aGVhZC8+WHYAAACsAAAANmhoZWEEsgJaAAAA5AAAACRobXR4AlgAAAAAAYgAAAAGbG9jYQAaAA0AAAHEAAAABm1heHAABAAGAAABCAAAACBuYW1lecS2nAAAAgAAAAFocG9zdAAoAAAAAANoAAAAJgABAAAAAQAA5d0ZOV8PPPUAAQPoAAAAAObpCm0AAAAA5ukKbQBkAAAB9AK8AAAAAwACAAAAAAAAAAEAAAMg/zgAAAJYAAAAyAGQAAEAAAAAAAAAAAAAAAAAAAABAAEAAAACAAQAAQAAAAAAAgAAAAAAAAAAAAAAAAAAAAAAAwJYAZAABQAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAPz8/PwAAAEEAQQMg/zgAAAMgAMgAAAAAAAAAAAAAAAAAAAAgAAACWAAAAAAAAAAAAAIAAAADAAAAFAADAAEAAAAUAAQAIAAAAAQABAABAAAAQf//AAAAQf///8AAAQAAAAAAAAANABoAAAABAGQAAAH0ArwAAwAAMyERIWQBkP5wArwAAAEAZAAAAfQCvAADAAAzIREhZAGQ/nACvAAAAAAMAJYAAQAAAAAAAQARAAAAAQAAAAAAAgAHABEAAQAAAAAAAwATABgAAQAAAAAABAARAAAAAQAAAAAABQALACsAAQAAAAAABgAQADYAAwABBAkAAQAiAEYAAwABBAkAAgAOAGgAAwABBAkAAwAmAHYAAwABBAkABAAiAEYAAwABBAkABQAWAJwAAwABBAkABgAgALJWYXJxIFZlcmlmaWNhdGlvblJlZ3VsYXJWYXJxIFZlcmlmaWNhdGlvbiAxVmVyc2lvbiAxLjBWYXJxVmVyaWZpY2F0aW9uAFYAYQByAHEAIABWAGUAcgBpAGYAaQBjAGEAdABpAG8AbgBSAGUAZwB1AGwAYQByAFYAYQByAHEAIABWAGUAcgBpAGYAaQBjAGEAdABpAG8AbgAgADEAVgBlAHIAcwBpAG8AbgAgADEALgAwAFYAYQByAHEAVgBlAHIAaQBmAGkAYwBhAHQAaQBvAG4AAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAAAJAAA")


def serve(args):
    lock = threading.Lock()
    log = Path(args.log)
    log.write_text("")

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.respond()

        def do_POST(self):
            self.rfile.read(int(self.headers.get("Content-Length", "0")))
            self.respond()

        def log_message(self, *_):
            pass

        def respond(self):
            path = urlsplit(self.path).path
            record = {"scheme": self.server.scheme, "method": self.command, "path": self.path, "time": time.time()}
            with lock:
                with log.open("a") as stream:
                    stream.write(json.dumps(record) + "\n")
            prefix, _, resource = path.rpartition("/")
            origin = f"{self.server.scheme}://127.0.0.1:{self.server.server_port}"
            status, headers = 200, {}
            if resource == "redirect-image":
                status, body, mime = 302, b"", "text/plain"
                headers["Location"] = prefix + "/redirect-target.png"
            elif resource == "style.css":
                body = f"@import url('{origin}{prefix}/style-import.css'); @font-face {{font-family: RemoteProbe{self.server.scheme};src:url('{origin}{prefix}/font.ttf')}} .remote-{self.server.scheme} {{font-family:RemoteProbe{self.server.scheme} !important}}".encode()
                mime = "text/css"
            elif resource in ("style-import.css", "direct-import.css"):
                body, mime = b".remote-probe { padding-right: 19px; }", "text/css"
            elif resource.endswith(".ttf"):
                body, mime = FONT, "font/ttf"
            elif resource.endswith(".png"):
                body, mime = PNG, "image/png"
            elif resource == "script.js":
                body = f"document.documentElement.setAttribute('data-author-external','ran');new Image().src='{origin}{prefix}/script-beacon.png';".encode()
                mime = "application/javascript"
            elif resource == "frame.html":
                body = f"<html><body>Remote frame<img src='{origin}{prefix}/frame-beacon.png'></body></html>".encode()
                mime = "text/html"
            else:
                body, mime = b"<html><body>Controlled navigation endpoint.</body></html>", "text/html"
            self.send_response(status)
            self.send_header("Content-Type", mime)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Access-Control-Allow-Origin", "*")
            for key, value in headers.items():
                self.send_header(key, value)
            self.end_headers()
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass

    servers = []
    for scheme in ("http", "https"):
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        server.daemon_threads = True
        server.scheme = scheme
        if scheme == "https":
            context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            context.load_cert_chain(args.cert, args.key)
            server.socket = context.wrap_socket(server.socket, server_side=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        servers.append(server)
    Path(args.ready).write_text(json.dumps({s.scheme: s.server_port for s in servers}))
    threading.Event().wait()


def fixtures(args):
    ports = json.loads(Path(args.ports).read_text())
    directory = Path(args.output)
    directory.mkdir(parents=True, exist_ok=True)
    for mode in ("control", "public", "private"):
        remote_head, remote_body, direct_imports, direct_styles = [], [], [], []
        inline = ["document.documentElement.setAttribute('data-author-inline','ran');"]
        events = ["document.documentElement.setAttribute('data-author-event','ran');"]
        for scheme, port in ports.items():
            base = f"{scheme}://127.0.0.1:{port}/{mode}/{scheme}"
            remote_head.append(f'<link rel="stylesheet" href="{base}/style.css"/><script src="{base}/script.js"></script>')
            direct_imports.append(f"@import url('{base}/direct-import.css');")
            direct_styles.append(f"@font-face {{font-family:DirectProbe{scheme};src:url('{base}/direct-font.ttf')}} #direct-{scheme} {{font-family:DirectProbe{scheme} !important;background-image:url('{base}/direct-background.png')}}")
            inline.append(f"new Image().src='{base}/inline-beacon.png';")
            events.append(f"new Image().src='{base}/event-beacon.png';")
            remote_body.append(f'''<p class="remote-probe remote-{scheme}">A</p><p id="direct-{scheme}">A</p>
            <img src="{base}/image.png"/><img src="{base}/redirect-image"/>
            <iframe id="frame-{scheme}" name="frame-{scheme}" src="{base}/frame.html"></iframe>
            <a id="link-{scheme}" href="{base}/link" target="frame-{scheme}">External link</a>
            <a id="main-{scheme}" href="{base}/main-link">Main-frame link</a>
            <a id="window-{scheme}" href="{base}/new-window" target="_blank">New window</a>
            <form id="form-{scheme}" action="{base}/form" method="post" target="frame-{scheme}"><input name="passage" value="fixture-only-sentinel"/><button type="submit">Submit</button></form>''')
        body = f'''<html xmlns="http://www.w3.org/1999/xhtml"><head>
        <link rel="stylesheet" href="local.css"/>{''.join(remote_head)}
        <script>{''.join(inline)}</script><script src="local-evil.js"></script>
        </head><body onload="{''.join(events)}">
        <p id="local-text">Safe local chapter.</p><p id="local-font">A</p>
        <img id="local-image" src="local.png"/><img id="data-image" src="data:image/png;base64,{base64.b64encode(PNG).decode()}"/>
        <a id="javascript-link" href="javascript:document.documentElement.setAttribute('data-author-url','ran')">Author URL script</a>
        <a id="outside-link" href="file:///etc/hosts">Outside file</a>
        {''.join(remote_body)}
        {''.join('<p>Original fixture paragraph for pagination and chapter navigation.</p>' for _ in range(80))}
        </body></html>'''
        base_http = f"http://127.0.0.1:{ports['http']}/{mode}/http"
        base_https = f"https://127.0.0.1:{ports['https']}/{mode}/https"
        chapters = {
            "chapter.xhtml": body,
            "http-redirect.xhtml": f'<html xmlns="http://www.w3.org/1999/xhtml"><head><meta http-equiv="refresh" content="0;url={base_http}/meta-redirect"/></head><body><p>HTTP redirect chapter.</p></body></html>',
            "https-redirect.xhtml": f'<html xmlns="http://www.w3.org/1999/xhtml"><head><meta http-equiv="refresh" content="0;url={base_https}/meta-redirect"/></head><body><p>HTTPS redirect chapter.</p></body></html>',
        }
        items = ''.join(f'<item id="c{i}" href="{name}" media-type="application/xhtml+xml"/>' for i, name in enumerate(chapters))
        spine = ''.join(f'<itemref idref="c{i}"/>' for i in range(len(chapters)))
        entries = {
            "mimetype": b"application/epub+zip",
            "META-INF/container.xml": b'<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
            "OEBPS/content.opf": f'<package xmlns="http://www.idpf.org/2007/opf" version="3.0"><metadata/><manifest>{items}</manifest><spine>{spine}</spine></package>'.encode(),
            "OEBPS/local.css": ("@import url('local-import.css');" + ''.join(direct_imports) + "@font-face {font-family:LocalProbe;src:url('local.ttf')} #local-font {font-family:LocalProbe !important}" + ''.join(direct_styles)).encode(),
            "OEBPS/local-import.css": b"#local-text {padding-left:17px}",
            "OEBPS/local-evil.js": b"document.documentElement.setAttribute('data-author-local','ran');",
            "OEBPS/local.png": PNG,
            "OEBPS/local.ttf": FONT,
        }
        entries.update({"OEBPS/" + name: text.encode() for name, text in chapters.items()})
        with zipfile.ZipFile(directory / f"{mode}.epub", "w") as archive:
            for name, data in entries.items():
                archive.writestr(name, data)


def verify(args):
    events = [json.loads(line) for line in Path(args.log).read_text().splitlines()]
    required = {"style.css", "style-import.css", "font.ttf", "direct-import.css", "direct-font.ttf", "direct-background.png", "image.png", "redirect-image", "redirect-target.png", "script.js", "script-beacon.png", "inline-beacon.png", "event-beacon.png", "frame.html", "frame-beacon.png", "link", "main-link", "form", "meta-redirect"}
    for scheme in ("http", "https"):
        observed = {urlsplit(e["path"]).path.rsplit("/", 1)[-1] for e in events if e["scheme"] == scheme and e["path"].startswith(f"/control/{scheme}/")}
        missing = required - observed
        if missing:
            raise SystemExit(f"Positive control missing {scheme} requests: {sorted(missing)}")
        print(f"PASS: unhardened {scheme.upper()} control observed all {len(required)} request classes")
    unexpected = [e for e in events if e["path"].startswith(("/public/", "/private/"))]
    if unexpected:
        raise SystemExit("EPUB isolation leaked requests: " + json.dumps(unexpected))
    print("PASS: zero public/private EPUB HTTP/HTTPS requests reached either server")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    modes = parser.add_subparsers(dest="mode", required=True)
    server = modes.add_parser("serve")
    for option in ("cert", "key", "ready", "log"):
        server.add_argument("--" + option, required=True)
    generator = modes.add_parser("fixtures")
    generator.add_argument("--ports", required=True)
    generator.add_argument("--output", required=True)
    checker = modes.add_parser("verify")
    checker.add_argument("--log", required=True)
    args = parser.parse_args()
    {"serve": serve, "fixtures": fixtures, "verify": verify}[args.mode](args)
