# FleetPrompt - Phase 0: Foundation & Setup (Inertia.js + Svelte)

## Overview
This phase establishes the foundational infrastructure for FleetPrompt using:
- **Backend**: Elixir, Phoenix, Ash Framework
- **Frontend**: Svelte 5 + Inertia.js + shadcn-svelte + TypeScript
- **Database**: PostgreSQL with multi-tenancy
- **Build**: Vite (via Phoenix)

## Tech Stack

### Backend
- **Elixir 1.18+** - Functional language on BEAM
- **Phoenix 1.7+** - Web framework
- **Ash Framework 3.0+** - Declarative resources
- **Inertia Phoenix 2.5+** - Server-driven SPA adapter
- **Oban** - Background jobs

### Frontend
- **Svelte 5** - Reactive UI framework
- **Inertia.js** - Server-driven SPA
- **shadcn-svelte** - Beautiful UI components
- **TypeScript** - Type safety
- **Vite** - Fast build tool
- **TailwindCSS** - Utility-first CSS

## Step-by-Step Implementation

### Step 1: Create Phoenix Project

```bash
# Install Phoenix
mix archive.install hex phx_new

# Create project WITHOUT LiveView (we're using Inertia)
mix phx.new fleet_prompt --database postgres --no-live

cd fleet_prompt
```

### Step 2: Add Elixir Dependencies

Edit `mix.exs`:

```elixir
defp deps do
  [
    # Phoenix & Core
    {:phoenix, "~> 1.7.14"},
    {:phoenix_ecto, "~> 4.5"},
    {:ecto_sql, "~> 3.11"},
    {:postgrex, ">= 0.0.0"},
    {:phoenix_html, "~> 4.1"},
    {:phoenix_live_reload, "~> 1.5", only: :dev},
    {:phoenix_live_dashboard, "~> 0.8"},
    {:swoosh, "~> 1.16"},
    {:finch, "~> 0.18"},
    {:telemetry_metrics, "~> 1.0"},
    {:telemetry_poller, "~> 1.1"},
    {:gettext, "~> 0.24"},
    {:jason, "~> 1.4"},
    {:dns_cluster, "~> 0.1.3"},
    {:bandit, "~> 1.5"},

    # Inertia.js
    {:inertia, "~> 2.5"},

    # Ash Framework
    {:ash, "~> 3.0"},
    {:ash_postgres, "~> 2.0"},
    {:ash_phoenix, "~> 2.0"},
    {:ash_json_api, "~> 1.0"},
    {:ash_admin, "~> 0.11"},
    {:ash_state_machine, "~> 0.2"},

    # Background Jobs
    {:oban, "~> 2.17"},

    # LLM Integration
    {:req, "~> 0.5"},

    # Utilities
    {:bcrypt_elixir, "~> 3.0"},
    {:uuid, "~> 1.1"},
    {:timex, "~> 3.7"},
    
    # Development
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
  ]
end
```

Install dependencies:

```bash
mix deps.get
```

### Step 3: Configure Inertia

Edit `config/config.exs`:

```elixir
import Config

# Configure Inertia
config :inertia,
  endpoint: FleetPromptWeb.Endpoint,
  static_paths: ["/assets/app.js"],
  default_version: "1",
  ssr: true,  # Enable server-side rendering
  raise_on_ssr_failure: true

# Ash Framework domains
config :fleet_prompt,
  ash_domains: [
    FleetPrompt.Accounts,
    FleetPrompt.Agents,
    FleetPrompt.Skills,
    FleetPrompt.Workflows,
    FleetPrompt.Packages
  ]

config :fleet_prompt,
  ecto_repos: [FleetPrompt.Repo]

# ... rest of config
```

### Step 4: Update Application Supervision Tree

Edit `lib/fleet_prompt/application.ex`:

```elixir
defmodule FleetPrompt.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FleetPromptWeb.Telemetry,
      FleetPrompt.Repo,
      {DNSCluster, query: Application.get_env(:fleet_prompt, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FleetPrompt.PubSub},
      {Finch, name: FleetPrompt.Finch},
      
      # Oban for background jobs
      {Oban, Application.fetch_env!(:fleet_prompt, Oban)},
      
      # Inertia SSR
      {Inertia.SSR, path: Path.join([Application.app_dir(:fleet_prompt), "priv"])},
      
      FleetPromptWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: FleetPrompt.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    FleetPromptWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
```

### Step 5: Configure Router for Inertia

Edit `lib/fleet_prompt_web/router.ex`:

```elixir
defmodule FleetPromptWeb.Router do
  use FleetPromptWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug Inertia.Plug  # Add Inertia plug
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FleetPromptWeb do
    pipe_through :browser

    get "/", PageController, :home
  end
end
```

### Step 6: Update Controller Helper

Edit `lib/fleet_prompt_web.ex`:

```elixir
defmodule FleetPromptWeb do
  # ... existing code ...

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: FleetPromptWeb.Layouts]

      import Plug.Conn
      import FleetPromptWeb.Gettext
      import Inertia.Controller  # Add Inertia controller

      unquote(verified_routes())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
      
      import Inertia.HTML  # Add Inertia HTML helpers
    end
  end

  # ... rest of file
end
```

### Step 7: Create Inertia Layout

Create `lib/fleet_prompt_web/controllers/page_html/app.html.heex`:

```heex
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={get_csrf_token()} />
    <.live_title>
      <%= assigns[:page_title] || "FleetPrompt" %>
    </.live_title>
    <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
    <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}>
    </script>
  </head>
  <body>
    <%= @inner_content %>
  </body>
</html>
```

### Step 8: Setup Frontend (Svelte + Vite + TypeScript)

Remove default JavaScript setup:

```bash
rm -rf assets/js assets/css
```

Initialize new frontend:

```bash
cd assets

# Initialize package.json
npm init -y

# Install Vite and Svelte
npm install -D vite @sveltejs/vite-plugin-svelte svelte

# Install Inertia
npm install @inertiajs/svelte

# Install TypeScript
npm install -D typescript @tsconfig/svelte

# Install TailwindCSS
npm install -D tailwindcss postcss autoprefixer
npx tailwindcss init -p

# Install shadcn-svelte dependencies
npm install -D @internationalized/date
npm install bits-ui clsx tailwind-merge tailwind-variants
npm install lucide-svelte

cd ..
```

### Step 9: Configure package.json

Edit `assets/package.json`:

```json
{
  "name": "fleet_prompt",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "watch": "vite build --watch"
  },
  "devDependencies": {
    "@sveltejs/vite-plugin-svelte": "^4.0.0",
    "@tsconfig/svelte": "^5.0.4",
    "autoprefixer": "^10.4.20",
    "postcss": "^8.4.49",
    "svelte": "^5.2.7",
    "tailwindcss": "^3.4.17",
    "typescript": "^5.7.2",
    "vite": "^6.0.3"
  },
  "dependencies": {
    "@inertiajs/svelte": "^2.0.0",
    "@internationalized/date": "^3.6.0",
    "bits-ui": "^1.0.3",
    "clsx": "^2.1.1",
    "lucide-svelte": "^0.469.0",
    "tailwind-merge": "^2.6.0",
    "tailwind-variants": "^0.3.0"
  }
}
```

### Step 10: Create Vite Config

Create `assets/vite.config.ts`:

```typescript
import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import path from 'path';

export default defineConfig({
  plugins: [svelte()],
  resolve: {
    alias: {
      '$lib': path.resolve(__dirname, './src/lib')
    }
  },
  build: {
    outDir: '../priv/static/assets',
    emptyOutDir: true,
    manifest: true,
    rollupOptions: {
      input: {
        app: './src/app.ts'
      },
      output: {
        entryFileNames: '[name].js',
        chunkFileNames: '[name].js',
        assetFileNames: '[name].[ext]'
      }
    }
  }
});
```

### Step 11: Configure TailwindCSS

Edit `assets/tailwind.config.js`:

```javascript
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    './src/**/*.{html,js,svelte,ts}',
    '../lib/fleet_prompt_web/**/*.{ex,heex}'
  ],
  theme: {
    extend: {
      colors: {
        border: "hsl(var(--border))",
        input: "hsl(var(--input))",
        ring: "hsl(var(--ring))",
        background: "hsl(var(--background))",
        foreground: "hsl(var(--foreground))",
        primary: {
          DEFAULT: "hsl(var(--primary))",
          foreground: "hsl(var(--primary-foreground))",
        },
        secondary: {
          DEFAULT: "hsl(var(--secondary))",
          foreground: "hsl(var(--secondary-foreground))",
        },
        destructive: {
          DEFAULT: "hsl(var(--destructive))",
          foreground: "hsl(var(--destructive-foreground))",
        },
        muted: {
          DEFAULT: "hsl(var(--muted))",
          foreground: "hsl(var(--muted-foreground))",
        },
        accent: {
          DEFAULT: "hsl(var(--accent))",
          foreground: "hsl(var(--accent-foreground))",
        },
        popover: {
          DEFAULT: "hsl(var(--popover))",
          foreground: "hsl(var(--popover-foreground))",
        },
        card: {
          DEFAULT: "hsl(var(--card))",
          foreground: "hsl(var(--card-foreground))",
        },
      },
      borderRadius: {
        lg: "var(--radius)",
        md: "calc(var(--radius) - 2px)",
        sm: "calc(var(--radius) - 4px)",
      },
    },
  },
  plugins: [],
}
```

### Step 12: Create TypeScript Config

Create `assets/tsconfig.json`:

```json
{
  "extends": "@tsconfig/svelte/tsconfig.json",
  "compilerOptions": {
    "target": "ESNext",
    "useDefineForClassFields": true,
    "module": "ESNext",
    "resolveJsonModule": true,
    "allowJs": true,
    "checkJs": true,
    "isolatedModules": true,
    "paths": {
      "$lib": ["./src/lib"],
      "$lib/*": ["./src/lib/*"]
    }
  },
  "include": ["src/**/*.ts", "src/**/*.js", "src/**/*.svelte"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

Create `assets/tsconfig.node.json`:

```json
{
  "compilerOptions": {
    "composite": true,
    "module": "ESNext",
    "moduleResolution": "bundler"
  },
  "include": ["vite.config.ts"]
}
```

### Step 13: Create Frontend Structure

```bash
cd assets

mkdir -p src/lib/components/ui
mkdir -p src/lib/utils
mkdir -p src/pages

# Create main files
touch src/app.ts
touch src/app.css
touch src/lib/utils/cn.ts
```

Create `assets/src/app.ts`:

```typescript
import { createInertiaApp } from '@inertiajs/svelte';
import './app.css';

createInertiaApp({
  resolve: name => {
    const pages = import.meta.glob('./pages/**/*.svelte', { eager: true });
    return pages[`./pages/${name}.svelte`];
  },
  setup({ el, App }) {
    new App({ target: el });
  },
});
```

Create `assets/src/app.css`:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  :root {
    --background: 0 0% 100%;
    --foreground: 222.2 84% 4.9%;
    --card: 0 0% 100%;
    --card-foreground: 222.2 84% 4.9%;
    --popover: 0 0% 100%;
    --popover-foreground: 222.2 84% 4.9%;
    --primary: 221.2 83.2% 53.3%;
    --primary-foreground: 210 40% 98%;
    --secondary: 210 40% 96.1%;
    --secondary-foreground: 222.2 47.4% 11.2%;
    --muted: 210 40% 96.1%;
    --muted-foreground: 215.4 16.3% 46.9%;
    --accent: 210 40% 96.1%;
    --accent-foreground: 222.2 47.4% 11.2%;
    --destructive: 0 84.2% 60.2%;
    --destructive-foreground: 210 40% 98%;
    --border: 214.3 31.8% 91.4%;
    --input: 214.3 31.8% 91.4%;
    --ring: 221.2 83.2% 53.3%;
    --radius: 0.5rem;
  }

  .dark {
    --background: 222.2 84% 4.9%;
    --foreground: 210 40% 98%;
    --card: 222.2 84% 4.9%;
    --card-foreground: 210 40% 98%;
    --popover: 222.2 84% 4.9%;
    --popover-foreground: 210 40% 98%;
    --primary: 217.2 91.2% 59.8%;
    --primary-foreground: 222.2 47.4% 11.2%;
    --secondary: 217.2 32.6% 17.5%;
    --secondary-foreground: 210 40% 98%;
    --muted: 217.2 32.6% 17.5%;
    --muted-foreground: 215 20.2% 65.1%;
    --accent: 217.2 32.6% 17.5%;
    --accent-foreground: 210 40% 98%;
    --destructive: 0 62.8% 30.6%;
    --destructive-foreground: 210 40% 98%;
    --border: 217.2 32.6% 17.5%;
    --input: 217.2 32.6% 17.5%;
    --ring: 224.3 76.3% 48%;
  }
}
```

Create `assets/src/lib/utils/cn.ts`:

```typescript
import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

### Step 14: Create First Page

Create `assets/src/pages/Home.svelte`:

```svelte
<script lang="ts">
  import { inertia } from '@inertiajs/svelte';
  
  interface Props {
    message: string;
  }
  
  let { message }: Props = $props();
</script>

<div class="min-h-screen bg-background flex items-center justify-center">
  <div class="text-center">
    <h1 class="text-4xl font-bold text-foreground mb-4">
      Welcome to FleetPrompt
    </h1>
    <p class="text-muted-foreground mb-8">
      {message}
    </p>
    <a
      use:inertia
      href="/dashboard"
      class="inline-flex items-center justify-center rounded-md text-sm font-medium ring-offset-background transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50 bg-primary text-primary-foreground hover:bg-primary/90 h-10 px-4 py-2"
    >
      Get Started
    </a>
  </div>
</div>
```

### Step 15: Update Phoenix Endpoint Config

Edit `config/dev.exs`:

```elixir
config :fleet_prompt, FleetPromptWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "...",
  watchers: [
    node: ["node_modules/.bin/vite", "build", "--watch", cd: Path.expand("../assets", __DIR__)]
  ]
```

### Step 16: Update Controller

Edit `lib/fleet_prompt_web/controllers/page_controller.ex`:

```elixir
defmodule FleetPromptWeb.PageController do
  use FleetPromptWeb, :controller

  def home(conn, _params) do
    render_inertia(conn, "Home",
      props: %{
        message: "Deploy AI agent fleets in minutes"
      }
    )
  end
end
```

### Step 17: Create SSR Entry Point

Create `priv/ssr.js`:

```javascript
import { createInertiaApp } from '@inertiajs/svelte/server';
import createServer from '@inertiajs/svelte/server';

createServer(page =>
  createInertiaApp({
    page,
    resolve: name => {
      const pages = import.meta.glob('../assets/src/pages/**/*.svelte', { eager: true });
      return pages[`../assets/src/pages/${name}.svelte`];
    },
  })
);
```

### Step 18: Build and Run

```bash
# Install frontend dependencies
cd assets && npm install && cd ..

# Create database
mix ecto.create

# Build frontend
cd assets && npm run build && cd ..

# Start Phoenix server
mix phx.server
```

Visit `http://localhost:4000` - you should see your Svelte app!

## Verification Checklist

- [ ] Phoenix server starts
- [ ] Vite builds assets
- [ ] Inertia renders Svelte page
- [ ] Hot reload works in development
- [ ] TypeScript compiles without errors
- [ ] TailwindCSS styles applied
- [ ] SSR working (check page source)

## Expected Project Structure

```
fleet_prompt/
├── lib/
│   ├── fleet_prompt/         # Backend domain logic
│   └── fleet_prompt_web/     # Phoenix web layer
├── assets/
│   ├── src/
│   │   ├── lib/
│   │   │   ├── components/ui/  # shadcn-svelte components
│   │   │   └── utils/
│   │   ├── pages/              # Inertia pages
│   │   ├── app.ts
│   │   └── app.css
│   ├── package.json
│   ├── vite.config.ts
│   └── tailwind.config.js
├── priv/
│   ├── static/assets/        # Built assets
│   └── ssr.js               # SSR entry
└── mix.exs
```

## Next Phase

**Phase 1: Core Resources & Multi-Tenancy (with Inertia pages)**

---

**Completion Status:** Phase 0 establishes Inertia + Svelte foundation.
