#!/usr/bin/env python3
"""Tiny HTTP server for FotballTray - serves match data and cached images to QML plasmoid"""
import http.server
import json
import mimetypes
import os

CACHE_FILE = os.path.expanduser("~/.cache/fotballtray/matches.json")
TEAMS_FILE = os.path.expanduser("~/.cache/fotballtray/teams.json")
LEAGUES_FILE = os.path.expanduser("~/.cache/fotballtray/leagues.json")
TOURNAMENT_FILE = os.path.expanduser("~/.cache/fotballtray/tournament.json")
IMAGES_DIR = os.path.expanduser("~/.cache/fotballtray/images")
PORT = 9876

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ('/', '/matches.json'):
            self._serve_json()
        elif self.path == '/teams.json':
            self._serve_teams()
        elif self.path == '/leagues.json':
            self._serve_leagues()
        elif self.path == '/tournament.json':
            self._serve_tournament()
        elif self.path.startswith('/img/'):
            self._serve_image(self.path[5:])
        else:
            self._send_404()

    def _serve_json(self):
        self._serve_file(CACHE_FILE, 'application/json', no_cache=True)

    def _serve_teams(self):
        self._serve_file(TEAMS_FILE, 'application/json', no_cache=True)

    def _serve_leagues(self):
        self._serve_file(LEAGUES_FILE, 'application/json', no_cache=True)

    def _serve_tournament(self):
        self._serve_file(TOURNAMENT_FILE, 'application/json', no_cache=True)

    def _serve_file(self, filepath, content_type, no_cache=False):
        try:
            with open(filepath) as f:
                data = f.read()
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Access-Control-Allow-Origin', '*')
            if no_cache:
                self.send_header('Cache-Control', 'no-cache')
            self.end_headers()
            self.wfile.write(data.encode())
        except FileNotFoundError:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'{"error":"not found"}')

    def _serve_image(self, filename):
        if not filename or '..' in filename or '/' in filename:
            self._send_404()
            return
        filepath = os.path.join(IMAGES_DIR, filename)
        if not os.path.isfile(filepath):
            self._send_404()
            return
        try:
            content_type, _ = mimetypes.guess_type(filepath)
            if not content_type:
                content_type = 'application/octet-stream'
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Cache-Control', 'public, max-age=86400')
            self.end_headers()
            with open(filepath, 'rb') as f:
                self.wfile.write(f.read())
        except Exception:
            self._send_404()

    def _send_404(self):
        self.send_response(404)
        self.end_headers()
        self.wfile.write(b'{}')

    def log_message(self, format, *args):
        pass  # Silent

if __name__ == '__main__':
    os.makedirs(IMAGES_DIR, exist_ok=True)
    server = http.server.HTTPServer(('127.0.0.1', PORT), Handler)
    print(f"FotballTray HTTP server on 127.0.0.1:{PORT}")
    server.serve_forever()
