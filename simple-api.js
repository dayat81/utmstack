const express = require('express');
const cors = require('cors');
const app = express();

// Enable CORS for all routes
app.use(cors({
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With'],
    credentials: false
}));

// Parse JSON bodies
app.use(express.json());

// Mock API endpoints that the frontend is trying to access
app.get('/api/date-format', (req, res) => {
    console.log('GET /api/date-format');
    res.json({
        dateFormat: 'MM/dd/yyyy',
        timeFormat: 'HH:mm:ss',
        timezone: 'UTC'
    });
});

app.get('/api/system/info', (req, res) => {
    console.log('GET /api/system/info');
    res.json({
        version: '7.1.0',
        build: 'development',
        status: 'running'
    });
});

app.get('/api/health', (req, res) => {
    console.log('GET /api/health');
    res.json({
        status: 'UP',
        components: {
            database: { status: 'UP' },
            elasticsearch: { status: 'UP' }
        }
    });
});

// Default handler for unknown routes
app.use((req, res) => {
    console.log(`${req.method} ${req.path}`);
    res.json({
        message: 'Mock API endpoint',
        path: req.path,
        method: req.method,
        status: 'ok'
    });
});

// Start server
const PORT = 8090;
app.listen(PORT, () => {
    console.log(`🚀 Simple API Mock listening on http://localhost:${PORT}`);
    console.log(`📡 CORS enabled for all origins`);
});
