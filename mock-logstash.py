#!/usr/bin/env python3
"""
Simple mock Logstash server for development
"""
import http.server
import socketserver
import json
from urllib.parse import urlparse, parse_qs

class MockLogstashHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        """Handle GET requests"""
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        
        # Mock Logstash stats endpoint
        if self.path == '/':
            response = {
                "host": "mock-logstash",
                "version": "7.12.1",
                "http_address": "0.0.0.0:9600",
                "id": "mock-logstash-id",
                "name": "mock-logstash",
                "status": "green"
            }
        else:
            response = {"status": "ok", "message": "Mock Logstash server"}
        
        self.wfile.write(json.dumps(response).encode())

    def do_POST(self):
        """Handle POST requests"""
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        
        response = {"status": "received", "message": "Data received by mock Logstash"}
        self.wfile.write(json.dumps(response).encode())

    def log_message(self, format, *args):
        """Override to reduce log noise"""
        pass

def run_server(port=9600):
    """Run the mock Logstash server"""
    try:
        with socketserver.TCPServer(("", port), MockLogstashHandler) as httpd:
            print(f"Mock Logstash server running on port {port}")
            httpd.serve_forever()
    except OSError as e:
        if e.errno == 98:  # Address already in use
            print(f"Port {port} already in use - Logstash may already be running")
            exit(1)
        else:
            raise

if __name__ == "__main__":
    run_server()
