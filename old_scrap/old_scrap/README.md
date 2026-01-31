FleetPrompt
========

### Production
```bash
fly deploy --app fleetprompt

fly ssh console --machine 7847221ce7dd18 -C "mix ash_postgres.migrate --tenants"
```

### Development
```bash
cd ./frontend
vite build --watch

cd ./backend
mix deps.get
mix phx.server

# run migrations within ./backend
mix ash_postgres.migrate --tenants

# populate db with data
mix run priv/repo/seeds.exs
```

Login credentials:
  Email: admin@demo.com
  Password: password123

Admin panel:
  http://localhost:4000/admin


### configuration
```bash
export OPENROUTER_API_KEY="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"
export OPENROUTER_DEFAULT_MODEL="anthropic/claude-3.5-sonnet"
export OPENROUTER_SITE_URL="http://localhost:4000"
export OPENROUTER_APP_NAME="FleetPrompt (dev)"
```
