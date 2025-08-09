const express = require('express');
const cors = require('cors');
const app = express();

// Enable CORS for all routes
app.use(cors({
    origin: 'http://localhost:4200',
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With'],
    credentials: true
}));

// Parse JSON bodies
app.use(express.json());

// Mock API endpoints that the frontend is trying to access
app.get('/api/date-format', (req, res) => {
    res.json({
        dateFormat: 'MM/dd/yyyy',
        timeFormat: 'HH:mm:ss',
        timezone: 'UTC'
    });
});

app.get('/api/system/info', (req, res) => {
    res.json({
        version: '7.1.0',
        build: 'development',
        status: 'running'
    });
});

app.get('/api/health', (req, res) => {
    res.json({
        status: 'UP',
        components: {
            database: { status: 'UP' },
            elasticsearch: { status: 'UP' }
        }
    });
});

// Catch-all for unhandled API routes
app.use('/api*', (req, res) => {
    console.log(`API Request: ${req.method} ${req.path}`);
    res.json({
        message: 'API endpoint not implemented yet',
        path: req.path,
        method: req.method
    });
});

// Start server
const PORT = 8090;
app.listen(PORT, () => {
    console.log(`🚀 UTMStack API Proxy listening on http://localhost:${PORT}`);
    console.log(`📡 Accepting CORS requests from http://localhost:4200`);
});
