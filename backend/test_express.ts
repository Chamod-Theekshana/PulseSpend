import express from 'express';
import { validateNumericParam } from './src/middleware/validators';
import http from 'http';

const chatRoutes = express.Router({ mergeParams: true });
chatRoutes.post('/', validateNumericParam('id'), (req, res) => {
  res.json({ id: req.params.id, message: 'Success' });
});

const groupsRoutes = express.Router();
groupsRoutes.use('/:id/messages', chatRoutes);

const app = express();
app.use(express.json());
app.use('/api/groups', groupsRoutes);

app.use((err: any, req: any, res: any, next: any) => {
  res.status(500).json({ message: err.message });
});

const server = app.listen(0, () => {
  const port = (server.address() as any).port;
  
  const options = {
    hostname: 'localhost',
    port: port,
    path: '/api/groups/123/messages',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    }
  };

  const req = http.request(options, (res) => {
    console.log(`STATUS: ${res.statusCode}`);
    let data = '';
    res.on('data', (chunk) => {
      data += chunk;
    });
    res.on('end', () => {
      console.log('BODY:', data);
      server.close();
      process.exit();
    });
  });
  
  req.write(JSON.stringify({ content: 'hello' }));
  req.end();
});
