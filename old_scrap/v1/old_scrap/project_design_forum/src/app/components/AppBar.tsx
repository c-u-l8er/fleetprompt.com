import { Search, Bell, User } from "lucide-react";
import { Input } from "./ui/input";
import { Button } from "./ui/button";
import { Badge } from "./ui/badge";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "./ui/popover";
import { OrgSwitcher } from "./OrgSwitcher";
import { Organization, Notification } from "../types";
import { formatDistanceToNow } from "date-fns";

interface AppBarProps {
  organizations: Organization[];
  currentOrg: Organization;
  onSelectOrg: (org: Organization) => void;
  notifications: Notification[];
  unreadCount: number;
}

export function AppBar({
  organizations,
  currentOrg,
  onSelectOrg,
  notifications,
  unreadCount,
}: AppBarProps) {
  return (
    <div className="border-b border-neutral-200 bg-white">
      <div className="flex items-center gap-4 px-6 py-3">
        <div className="flex items-center gap-3">
          <div className="text-lg font-semibold">
            FleetPrompt
          </div>
          <div className="h-6 w-px bg-neutral-200" />
          <OrgSwitcher
            organizations={organizations}
            currentOrg={currentOrg}
            onSelectOrg={onSelectOrg}
          />
        </div>

        <div className="flex-1 max-w-xl">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-neutral-400" />
            <Input
              type="search"
              placeholder="Search threads..."
              className="pl-9 border-neutral-300"
            />
          </div>
        </div>

        <div className="flex items-center gap-2">
          <Popover>
            <PopoverTrigger asChild>
              <Button
                variant="ghost"
                size="icon"
                className="relative"
              >
                <Bell className="h-5 w-5" />
                {unreadCount > 0 && (
                  <Badge className="absolute -top-1 -right-1 h-5 w-5 flex items-center justify-center p-0 bg-red-500 text-white text-xs">
                    {unreadCount}
                  </Badge>
                )}
              </Button>
            </PopoverTrigger>
            <PopoverContent className="w-80 p-0" align="end">
              <div className="p-4 border-b border-neutral-200">
                <div className="flex items-center justify-between">
                  <h3 className="font-semibold">
                    Notifications
                  </h3>
                  <Button
                    variant="ghost"
                    size="sm"
                    className="text-xs text-neutral-500"
                  >
                    Mark all read
                  </Button>
                </div>
              </div>
              <div className="max-h-96 overflow-auto">
                {notifications.slice(0, 5).map((notif) => (
                  <div
                    key={notif.id}
                    className={`p-4 border-b border-neutral-100 hover:bg-neutral-50 cursor-pointer ${
                      !notif.read ? "bg-blue-50" : ""
                    }`}
                  >
                    <p className="text-sm">{notif.message}</p>
                    <p className="text-xs text-neutral-500 mt-1">
                      {formatDistanceToNow(
                        new Date(notif.createdAt),
                        { addSuffix: true },
                      )}
                    </p>
                  </div>
                ))}
              </div>
            </PopoverContent>
          </Popover>

          <Button variant="ghost" size="icon">
            <User className="h-5 w-5" />
          </Button>
        </div>
      </div>
    </div>
  );
}