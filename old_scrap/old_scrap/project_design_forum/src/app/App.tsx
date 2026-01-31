import { useState } from "react";
import { BrowserRouter as Router, Routes, Route } from "react-router-dom";
import { Toaster } from "./components/ui/sonner";
import { AppBar } from "./components/AppBar";
import { Sidebar } from "./components/Sidebar";
import { HomePage } from "./pages/HomePage";
import { CategoryDetailPage } from "./pages/CategoryDetailPage";
import { ThreadDetailPage } from "./pages/ThreadDetailPage";
import { CreateThreadPage } from "./pages/CreateThreadPage";
import { ModerationQueuePage } from "./pages/ModerationQueuePage";
import { AgentActivityPage } from "./pages/AgentActivityPage";
import { PlaceholderPage } from "./pages/PlaceholderPage";
import { organizations, notifications, currentUser } from "./mockData";
import { Bookmark, User } from "lucide-react";

export default function App() {
  const [currentOrg, setCurrentOrg] = useState(organizations[0]);
  const unreadNotifications = notifications.filter(n => !n.read).length;

  return (
    <Router>
      <div className="h-screen flex flex-col bg-neutral-50">
        <AppBar
          organizations={organizations}
          currentOrg={currentOrg}
          onSelectOrg={setCurrentOrg}
          notifications={notifications}
          unreadCount={unreadNotifications}
        />
        
        <div className="flex-1 flex overflow-hidden">
          <Sidebar />
          
          <main className="flex-1 overflow-auto">
            <Routes>
              <Route path="/" element={<HomePage />} />
              <Route path="/category/:categoryId" element={<CategoryDetailPage />} />
              <Route path="/category/:categoryId/new-thread" element={<CreateThreadPage />} />
              <Route path="/thread/:threadId" element={<ThreadDetailPage />} />
              <Route path="/moderation" element={<ModerationQueuePage />} />
              <Route path="/agent-activity" element={<AgentActivityPage />} />
              <Route 
                path="/watching" 
                element={<PlaceholderPage title="Watching" description="Threads you're watching" icon={Bookmark} />} 
              />
              <Route 
                path="/assigned" 
                element={<PlaceholderPage title="Assigned to Me" description="Threads assigned to you" icon={User} />} 
              />
            </Routes>
          </main>
        </div>

        <Toaster />
      </div>
    </Router>
  );
}