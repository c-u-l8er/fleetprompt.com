import { Home, MessageSquare, AlertCircle, Activity, Bookmark, User as UserIcon } from "lucide-react";
import { Link, useLocation } from "react-router-dom";

interface NavItem {
  id: string;
  label: string;
  icon: React.ElementType;
  href: string;
}

const navItems: NavItem[] = [
  { id: "home", label: "Home", icon: Home, href: "/" },
  { id: "watching", label: "Watching", icon: Bookmark, href: "/watching" },
  { id: "assigned", label: "Assigned to me", icon: UserIcon, href: "/assigned" },
  { id: "moderation", label: "Moderation Queue", icon: AlertCircle, href: "/moderation" },
  { id: "agent-activity", label: "Agent Activity", icon: Activity, href: "/agent-activity" },
];

export function Sidebar() {
  const location = useLocation();

  return (
    <div className="w-64 border-r border-neutral-200 bg-white h-full overflow-auto">
      <div className="p-4">
        <h3 className="text-xs font-semibold text-neutral-500 uppercase tracking-wider mb-2">
          Forum
        </h3>
        <nav className="space-y-1">
          {navItems.map((item) => {
            const Icon = item.icon;
            const isActive = location.pathname === item.href;
            
            return (
              <Link
                key={item.id}
                to={item.href}
                className={`flex items-center gap-3 px-3 py-2 rounded-md text-sm transition-colors ${
                  isActive
                    ? "bg-neutral-100 text-neutral-900 font-medium"
                    : "text-neutral-600 hover:bg-neutral-50 hover:text-neutral-900"
                }`}
              >
                <Icon className="h-5 w-5" />
                {item.label}
              </Link>
            );
          })}
        </nav>

        <div className="mt-8">
          <h3 className="text-xs font-semibold text-neutral-500 uppercase tracking-wider mb-2">
            Categories
          </h3>
          <nav className="space-y-1">
            <Link
              to="/category/cat-1"
              className="block px-3 py-2 rounded-md text-sm text-neutral-600 hover:bg-neutral-50 hover:text-neutral-900"
            >
              <MessageSquare className="h-4 w-4 inline mr-2" />
              General Support
            </Link>
            <Link
              to="/category/cat-2"
              className="block px-3 py-2 rounded-md text-sm text-neutral-600 hover:bg-neutral-50 hover:text-neutral-900"
            >
              <MessageSquare className="h-4 w-4 inline mr-2" />
              Feature Requests
            </Link>
            <Link
              to="/category/cat-3"
              className="block px-3 py-2 rounded-md text-sm text-neutral-600 hover:bg-neutral-50 hover:text-neutral-900"
            >
              <MessageSquare className="h-4 w-4 inline mr-2" />
              Technical Issues
            </Link>
            <Link
              to="/category/cat-4"
              className="block px-3 py-2 rounded-md text-sm text-neutral-600 hover:bg-neutral-50 hover:text-neutral-900"
            >
              <MessageSquare className="h-4 w-4 inline mr-2" />
              API & Integration
            </Link>
          </nav>
        </div>

        <div className="mt-8">
          <h3 className="text-xs font-semibold text-neutral-500 uppercase tracking-wider mb-2">
            Saved Filters
          </h3>
          <nav className="space-y-1">
            <Link
              to="/filter/unanswered"
              className="block px-3 py-2 rounded-md text-sm text-neutral-600 hover:bg-neutral-50 hover:text-neutral-900"
            >
              Unanswered
            </Link>
            <Link
              to="/filter/agent-involved"
              className="block px-3 py-2 rounded-md text-sm text-neutral-600 hover:bg-neutral-50 hover:text-neutral-900"
            >
              Agent Involved
            </Link>
          </nav>
        </div>
      </div>
    </div>
  );
}
