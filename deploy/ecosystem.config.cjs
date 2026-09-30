const fs = require('node:fs');

const environment = JSON.parse(
  fs.readFileSync('/etc/browser-sync/environment.json', 'utf8'),
);

module.exports = {
  apps: [
    {
      name: 'browser-sync',
      cwd: '/var/www/browser-sync',
      script: '/var/www/browser-sync/.build/release/brower_server',
      interpreter: 'none',
      args: 'serve --env production --hostname 127.0.0.1 --port 4589',
      env: environment,
    },
  ],
};
