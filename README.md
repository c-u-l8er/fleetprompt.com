FleetPrompt
========

### Production
```bash
fly deploy --app fleetprompt
```

### Development
```bash
cd ./frontend
vite build --watch

cd ./backend
mix deps.get
mix phx.server
```

Login credentials:
  Email: admin@demo.com
  Password: password123

Admin panel:
  http://localhost:4000/admin
