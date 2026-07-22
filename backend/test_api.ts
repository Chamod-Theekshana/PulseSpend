import jwt from 'jsonwebtoken';
import http from 'http';

const secret = 'ChamodSecretKey123455235353363tedfvfsdfefdsfdsfewrtegdfdsetet';
const token = jwt.sign({ id: 2, email: 'chamodtheekshana25@gmail.com', tokenVersion: 1 }, secret, { expiresIn: '1h' });

const data = JSON.stringify({ content: 'hello api' });

const options = {
  hostname: 'localhost',
  port: 5001,
  path: '/api/groups/1/messages',
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + token,
    'Content-Length': data.length
  }
};

const req = http.request(options, (res) => {
  console.log(`STATUS: ${res.statusCode}`);
  let body = '';
  res.on('data', (chunk) => { body += chunk; });
  res.on('end', () => console.log('BODY:', body));
});

req.on('error', (e) => {
  console.error(`problem with request: ${e.message}`);
});

req.write(data);
req.end();
